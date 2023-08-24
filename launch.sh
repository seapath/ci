#!/bin/bash
#
# Copyright (C) 2023, RTE (http://www.rte-france.com)
# SPDX-License-Identifier: Apache-2.0
#
# This script download the sources of a specific pull request,
# then test it and upload a report given the test results.


if [ "${RUNNER_DEBUG}" == "1" ] ; then
set -x
fi
set -e

die() {
	echo "CI internal failure : $@" 1>&2
	exit 1
}

# Source CI configuration file
# This file must at least define the PRIVATE_INVENTORIES_REPO_URL variable
source /etc/seapath-ci.conf

if [ -z "${PRIVATE_INVENTORIES_REPO_URL}" ] ; then
  die "PRIVATE_INVENTORIES_REPO_URL not defined!"
fi

# default variables
if [ -z "${SEAPATH_BASE_REPO}" ] ; then
    SEAPATH_BASE_REPO="github.com/seapath"
fi
if [ -z "${SEAPATH_SSH_BASE_REPO}" ] ; then
    SEAPATH_SSH_BASE_REPO="git@github.com:seapath"
fi
if [ -z "${REPO_PRIVATE_KEYFILE}" ] ; then
  REPO_PRIVATE_KEYFILE=inventories_private/ci_rsa
fi

if [ -z "${ANSIBLE_INVENTORY}" ] ; then
  ANSIBLE_INVENTORY="inventories_private/seapath_cluster_ci.yml,inventories_private/seapath_standalone_rt.yml"
fi
if [ -z "${SVTOOLS_TARBALL}" ] ; then
  SVTOOLS_TARBALL="/home/virtu/ci-latency-tools/IEC61850_svtools/"
fi
if [ -z "${TRAFGEN_TARBALL}" ] ; then
  TRAFGEN_TARBALL="/home/virtu/ci-latency-tools/sv_generator/"
fi

CQFD_EXTRA_RUN_ARGS="-e ANSIBLE_INVENTORY=${ANSIBLE_INVENTORY} -v ${SVTOOLS_TARBALL}:$WORK_DIR/ansible/src/svtools/ -v ${TRAFGEN_TARBALL}:$WORK_DIR/ansible/src/trafgen/"

# If REPO_PRIVATE_KEYFILE is an absolute path bind it inside cqfd
if [[ "${REPO_PRIVATE_KEYFILE}" == /* ]] ; then
  CQFD_EXTRA_RUN_ARGS="${CQFD_EXTRA_RUN_ARGS} -v $REPO_PRIVATE_KEYFILE:/tmp/ci_ssh_key "
  PRIVATE_KEYFILE_PATH=/tmp/ci_ssh_key
else
  PRIVATE_KEYFILE_PATH="${REPO_PRIVATE_KEYFILE}"
fi

if [ -n "${CA_DIR}" ] ; then
  CQFD_EXTRA_RUN_ARGS="${CQFD_EXTRA_RUN_ARGS} -v ${CA_DIR}:$WORK_DIR/ansible/src/ca"
fi

export CQFD_EXTRA_RUN_ARGS

# Standard help message
usage()
{
    cat <<EOF
    This script is the main launcher for the SEAPATH CI.
    It is separated in many functions in order to display logs properly.
    They should be called one after another.
USAGE:
    ./launch.sh <init|conf|system|vm|latency|report>
DESCRIPTION:
    - init : download and prepare the sources.
    - conf : configure the debian OS to build SEAPATH.
    - system : launch system tests and gather results.
    - vm : launch tests inside a virtual machine in the cluster.
    - latency : launch latency tests and gather results.
    - report : build and upload the test report.
EOF
}

# Download and prepare the pull request sources
initialization() {
  if ! type -p cqfd > /dev/null; then
    die "cqfd not found"
  fi

  # Get sources
  git clone -q "https://${SEAPATH_BASE_REPO}/ansible"
  cd ansible
  git fetch -q origin "${GITHUB_REF}"
  git checkout -q FETCH_HEAD
  echo "Pull request sources got succesfully"

  # Get inventories
  git clone -q "${PRIVATE_INVENTORIES_REPO_URL}" inventories_private
  chmod 600 "${PRIVATE_KEYFILE_PATH}"

  # Prepare ansible repository
  cqfd init
  cqfd -b prepare
  echo "Sources prepared succesfully"
}

# Launch Debian configuration and hardening
configure_debian() {
  cd ansible
  cqfd run ansible-playbook \
  --key-file "${PRIVATE_KEYFILE_PATH}" \
  --skip-tags "package-install" \
  --limit 'all:!ci-tool' \
  playbooks/ci_configure.yaml
  echo "Debian set up succesfully"
}

# Prepare and launch cukinia test
# Send the result of the tests as return code
launch_system_tests() {
  cd ansible
  cqfd run ansible-playbook \
  --key-file "${PRIVATE_KEYFILE_PATH}" \
  --skip-tags "package-install" \
  --limit 'all:!ci-tool' \
  playbooks/ci_test.yaml
  echo "System tests launched successfully"

  # Generate test report part
  INCLUDE_DIR=${WORK_DIR}/ci/report-generator/include
  mkdir "$INCLUDE_DIR"
  mv ${WORK_DIR}/ansible/*.xml $INCLUDE_DIR # Test files
  cp ${WORK_DIR}/ansible/src/cukinia-tests/*.csv $INCLUDE_DIR # Compliance matrix
  cd ${WORK_DIR}/ci/report-generator
  cqfd -q init
  if ! cqfd -q -b generate_test_part; then
    die "cqfd error"
  fi

  # Check for kernel backtrace error. This is a random error so it must not
  # stop the CI but just display a warning
  # See https://github.com/seapath/ansible/issues/164
  if grep '<failure' $INCLUDE_DIR/*.xml | grep -q '00080'; then
     echo -e "\033[0;33mWarning :\033[0m kernel back trace detected, see \
         https://github.com/seapath/ansible/issues/164"
  fi

  # Display test results
  if grep '<failure' $INCLUDE_DIR/*.xml | grep -q -v '00080'; then
    echo "Test fails, See test report in the section 'Upload test report'"
    exit 1
  else
    echo "All tests pass"
    exit 0
  fi
}

# Deploy a Virtual machine on the cluster and launch cukinia tests in it.
# Fetch results
launch_vm_tests() {
  # Add VM inventory file
  # This file cannot be added at the beginnig of launch.sh cause it is used
  # only during thes step
  ANSIBLE_INVENTORY="${ANSIBLE_INVENTORY},inventories_private/vm.yml"
  CQFD_EXTRA_RUN_ARGS="${CQFD_EXTRA_RUN_ARGS} -e ANSIBLE_INVENTORY=${ANSIBLE_INVENTORY} -v /etc/seapath-ci/vm_file:${WORK_DIR}/ansible/vm_images"

  cd ansible
  cqfd run ansible-playbook \
  --key-file "${PRIVATE_KEYFILE_PATH}" \
  playbooks/deploy_vms_cluster.yaml
  echo "test VM deployed successfully"

  cqfd run ansible-playbook \
  --key-file "${PRIVATE_KEYFILE_PATH}" \
  --limit VMs \
  playbooks/cluster_setup_debian.yaml \
  playbooks/cluster_setup_hardened_debian.yaml

  cqfd run ansible-playbook \
  --key-file "${PRIVATE_KEYFILE_PATH}" \
  --limit VMs \
  playbooks/ci_test.yaml

  # Generate test report part
  # This part relaunch the test report generator with all cukinia test file
  # including the physical machine and the VM.
  # This actually redo what was done in the launch_system_tests but with the VM file
  # That's the best way I found to integrate this properly
  INCLUDE_DIR=${WORK_DIR}/ci/report-generator/include
  mv ${WORK_DIR}/ansible/*.xml $INCLUDE_DIR # Test files
  cd ${WORK_DIR}/ci/report-generator
  cqfd -q init
  if ! cqfd -q -b generate_test_part; then
    die "cqfd error"
  fi

  # Display test results
  if grep -q '<failure' $INCLUDE_DIR/*.xml; then
    echo "Test fails, See test report in the section 'Upload test report'"
    exit 1
  else
    echo "All tests pass"
    exit 0
  fi
}


# Deploy subscriber and publisher, generate SV and measure latency time
launch_latency_tests() {
  cd ansible
  cqfd run ansible-playbook \
  --key-file "${PRIVATE_KEYFILE_PATH}" \
  --skip-tags "package-install" \
  playbooks/test_run_latency_tests.yaml

  # Generate latency report part
  LATENCY_TEST_DIR="${WORK_DIR}/latency"
  mkdir $LATENCY_TEST_DIR
  mv -v ${WORK_DIR}/ansible/tests_results/* $LATENCY_TEST_DIR
  cd ${WORK_DIR}/ci/report-generator
  if ! CQFD_EXTRA_RUN_ARGS="-v $LATENCY_TEST_DIR:/tmp/tests_results" \
    cqfd -q -b generate_latency_part; then
    die "cqfd error"
  fi

  echo "See latency report in the section 'Upload test report'"

  # TODO : Add return value : false if we exceed max latency
}

# Generate the test report and upload it
generate_report() {

  # Generate pdf
  cd "${WORK_DIR}/ci/report-generator"
  if ! CQFD_EXTRA_RUN_ARGS="" cqfd -q run; then
    die "cqfd error"
  fi
  echo "Test report generated successfully"

  # Upload report
  PR_N=$(echo "$GITHUB_REF" | cut -d '/' -f 3)
  TIME=$(date +%F_%Hh%Mm%S)
  REPORT_NAME="test-report_${GITHUB_RUN_ID}_${GITHUB_RUN_ATTEMPT}_${TIME}.pdf"
  REPORT_DIR="${WORK_DIR}/reports/docs/reports/PR-${PR_N}"
  REPORT_BRANCH="reports-PR${PR_N}"

  # The CI repo have one branche per pull request.
  # If the report is the first of the PR, the branch needs to be created.
  # Otherwise, it just have to be switched on.
  git clone -q --depth 1 -b reports-base-commit \
    --config core.sshCommand="ssh -i ~/.ssh/ci_rsa" \
    "${SEAPATH_SSH_BASE_REPO}/ci.git" "$WORK_DIR/reports"
  cd "$WORK_DIR/reports"
  if ! git ls-remote origin "$REPORT_BRANCH" | grep -q "$REPORT_BRANCH"; then
    git branch "$REPORT_BRANCH"
  else
    git fetch -q origin "$REPORT_BRANCH":"$REPORT_BRANCH"
  fi
  git switch -q "$REPORT_BRANCH"

  mkdir -p "$REPORT_DIR"
  mv "${WORK_DIR}"/ci/report-generator/test-report.pdf "$REPORT_DIR/$REPORT_NAME"
  git config --local user.email "ci.seapath@gmail.com"
  git config --local user.name "Seapath CI"
  git config --local core.sshCommand "ssh -i ~/.ssh/ci_rsa"
  git add "$REPORT_DIR/$REPORT_NAME"
  git commit -q -m "upload report $REPORT_NAME"
  git push -q origin "$REPORT_BRANCH"
  echo "Test report uploaded successfully"

  echo See test Report at \
  "https://${SEAPATH_BASE_REPO}/ci/blob/${REPORT_BRANCH}/docs/reports/PR-${PR_N}/${REPORT_NAME}"
}

case "$1" in
  init)
    initialization
    exit 0
    ;;
  conf)
    configure_debian
    exit 0
    ;;
  system)
    launch_system_tests
    exit 0
    ;;
  vm)
    launch_vm_tests
    exit 0
    ;;
  latency)
    launch_latency_tests
    exit 0
    ;;
  report)
    generate_report
    exit 0
    ;;
  *)
    usage
    die "Unknown command"
    ;;
esac
