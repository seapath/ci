#!/bin/bash
#
# Copyright (C) 2023, RTE (http://www.rte-france.com)
# Copyright (C) 2024 Savoir-faire Linux, Inc.
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
if [ -z "${INVENTORY_VM}" ] ; then
  INVENTORY_VM=inventories_private/vm.yml
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
  --limit 'all:!ci-tool' \
  playbooks/ci_test.yaml
  echo "System tests launched successfully"

  # Move tests results to test-report-pdf directory
  INCLUDE_DIR=${WORK_DIR}/ci/test-report-pdf/include
  mkdir "$INCLUDE_DIR"
  mv ${WORK_DIR}/ansible/cukinia_*.xml $INCLUDE_DIR # Test files
  cp ${WORK_DIR}/ansible/roles/debian_tests/cukinia-tests/*.csv $INCLUDE_DIR # Compliance matrix

  # Check for kernel backtrace error. This is a random error so it must not
  # stop the CI but just display a warning
  # See https://github.com/seapath/ansible/issues/164
  if grep '<failure' $INCLUDE_DIR/*.xml | grep -q '00080'; then
     echo -e "\033[0;33mWarning :\033[0m kernel back trace detected, see \
         https://github.com/seapath/ansible/issues/164"
  fi

  # Display test results
  if grep '<failure' $INCLUDE_DIR/*.xml | grep -q -v '00080'; then
    grep FAIL $INCLUDE_DIR/*.xml || true
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
  cd ansible

  # Add VM inventory file
  # This file cannot be added at the beginnig of launch.sh cause it is used
  # only during thes step
  ANSIBLE_INVENTORY_VM="${ANSIBLE_INVENTORY},${INVENTORY_VM_CLUSTER}"
  CQFD_EXTRA_RUN_ARGS="${CQFD_EXTRA_RUN_ARGS} -e ANSIBLE_INVENTORY=${ANSIBLE_INVENTORY_VM} -v /etc/seapath-ci/vm_file:${WORK_DIR}/ansible/vm_images"
  cqfd run ansible-playbook \
  --key-file "${PRIVATE_KEYFILE_PATH}" \
  playbooks/deploy_vms_cluster.yaml
  echo "test VM deployed successfully on cluster"

  cqfd run ansible-playbook \
  --key-file "${PRIVATE_KEYFILE_PATH}" \
  --limit VMs \
  playbooks/seapath_setup_prerequisdebian.yaml \
  playbooks/seapath_setup_hardened_debian.yaml \
  playbooks/ci_prepare_VMs.yaml

  cqfd run ansible-playbook \
  --key-file "${PRIVATE_KEYFILE_PATH}" \
  --limit VMs \
  playbooks/ci_test.yaml

  ANSIBLE_INVENTORY_VM="${ANSIBLE_INVENTORY},${INVENTORY_VM_STANDALONE}"
  CQFD_EXTRA_RUN_ARGS="${CQFD_EXTRA_RUN_ARGS} -e ANSIBLE_INVENTORY=${ANSIBLE_INVENTORY_VM} -v /etc/seapath-ci/vm_file:${WORK_DIR}/ansible/vm_images"
  cqfd run ansible-playbook \
  --key-file "${PRIVATE_KEYFILE_PATH}" \
  playbooks/deploy_vms_standalone.yaml
  echo "test VM deployed successfully on standalone"

  cqfd run ansible-playbook \
  --key-file "${PRIVATE_KEYFILE_PATH}" \
  --limit VMs \
  playbooks/seapath_setup_prerequisdebian.yaml \
  playbooks/seapath_setup_hardened_debian.yaml \
  playbooks/ci_prepare_VMs.yaml

  cqfd run ansible-playbook \
  --key-file "${PRIVATE_KEYFILE_PATH}" \
  --limit VMs \
  playbooks/ci_test.yaml

  # Move VM test results to test-report-pdf
  INCLUDE_DIR=${WORK_DIR}/ci/test-report-pdf/include
  mv ${WORK_DIR}/ansible/cukinia_*.xml $INCLUDE_DIR # Test files


  # Display test results
  if grep '<failure' $INCLUDE_DIR/*.xml | grep -q -v '00080'; then
    grep FAIL $INCLUDE_DIR/*.xml || true
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
  playbooks/test_run_latency_tests.yaml

  # Generate latency report part
  LATENCY_TEST_DIR="${WORK_DIR}/ci/latency-results"
  mkdir $LATENCY_TEST_DIR
  mv ${WORK_DIR}/ansible/tests_results/* $LATENCY_TEST_DIR
  cd ${WORK_DIR}/ci/latency-tests-analysis
  cqfd -q init
  if ! CQFD_EXTRA_RUN_ARGS="-v $LATENCY_TEST_DIR:/tmp/tests_results" \
    cqfd -q run ./compile_latency.sh /tmp/tests_results/; then
    die "cqfd error"
  fi

  # This move is needed for test-report-pdf to work correctly.
  # By copying the latency reports adoc in the include directory under the
  # "notes.adoc" name, it will automatically be append at the end of the report.
  mv latency-test-reports.adoc "${WORK_DIR}/ci/test-report-pdf/include/notes.adoc"
  # Move images generated by compile_latency.sh
  mv include/* "${WORK_DIR}/ci/test-report-pdf/include/"

  echo "See latency report in the section 'Upload test report'"

  # TODO : Add return value : false if we exceed max latency
}

# Generate the test report and upload it
generate_report() {

  cd "${WORK_DIR}/ci/test-report-pdf"
  # Replace test-report-pdf default logo by SEAPATH one
  mv ../seapath-themes/logo.png themes/sfl.png
  sed -i 's/contact@savoirfairelinux/seapath@savoirfairelinux/g' test-report.adoc
  # Change contact mailing list to seapath SFL mailing list

  # Generate test report
  cqfd -q init
  if ! CQFD_EXTRA_RUN_ARGS="" cqfd -q run ./compile.py \
      -m -i include -C SEAPATH -p \"SEAPATH Debian\" \
      -c include/ANSSI-BP28-Recommandations-M.csv \
      -c include/ANSSI-BP28-Recommandations-MI.csv \
      -c include/ANSSI-BP28-Recommandations-MIR.csv; then
    die "cqfd error"
  fi
  echo "Test report generated successfully"
 
  # Upload report
  PR_N=$(echo "$GITHUB_REF" | cut -d '/' -f 3)
  TIME=$(date +%F_%Hh%Mm%S)
  REPORT_NAME="test-report_${GITHUB_RUN_ID}_${GITHUB_RUN_ATTEMPT}_${TIME}.pdf"
  REPORT_DIR="${WORK_DIR}/reports/docs/reports/PR-${PR_N}"
  REPORT_BRANCH="reports-PR${PR_N}"

  # The CI repo have one branch per pull request.
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
  mv "${WORK_DIR}"/ci/test-report-pdf/test-report.pdf "$REPORT_DIR/$REPORT_NAME"
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
