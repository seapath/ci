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

CQFD_EXTRA_RUN_ARGS="-e ANSIBLE_INVENTORY=${ANSIBLE_INVENTORY}"

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
    ./launch.sh <init|conf|system|vm|report>
DESCRIPTION:
    - init : download and prepare the sources.
    - conf : configure the Centos OS to build SEAPATH.
    - system : launch system tests and gather results.
    - vm : launch tests inside a virtual machine in the cluster.
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

# Launch Centos configuration and hardening
configure_centos() {
  cd ansible
  cqfd run ansible-playbook \
  --key-file "${PRIVATE_KEYFILE_PATH}" \
  --limit 'all:!ci-tool' \
  playbooks/ci_configure.yaml
  echo "Centos set up succesfully"
}

# Prepare and launch cukinia test
# Send the result of the tests as return code
launch_system_tests() {
  cd ansible
  cqfd run ansible-playbook \
  --key-file "${PRIVATE_KEYFILE_PATH}" \
  --limit 'all:!ci-tool' \
  playbooks/ci_centos_test.yaml
  echo "System tests launched successfully"

  # Move tests results to test-report-pdf directory
  INCLUDE_DIR=${WORK_DIR}/ci/test-report-pdf/include
  mkdir "$INCLUDE_DIR"
  mv ${WORK_DIR}/ansible/cukinia_*.xml $INCLUDE_DIR # Test files

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
    echo "Test fails, See associated test report"
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
  ANSIBLE_INVENTORY="${ANSIBLE_INVENTORY},${INVENTORY_VM}"
  CQFD_EXTRA_RUN_ARGS="${CQFD_EXTRA_RUN_ARGS} -e ANSIBLE_INVENTORY=${ANSIBLE_INVENTORY} -v /etc/seapath-ci/vm_file:${WORK_DIR}/ansible/vm_images"

  cd ansible
  cqfd run ansible-playbook \
  --key-file "${PRIVATE_KEYFILE_PATH}" \
  playbooks/deploy_vms_cluster.yaml
  echo "test VM deployed successfully"

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
    echo "Test fails, See associated test report"
    exit 1
  else
    echo "All tests pass"
    exit 0
  fi
}

# Generate the test report
generate_report() {

  cd "${WORK_DIR}/ci/test-report-pdf"
  # Replace test-report-pdf default logo by SEAPATH one
  mv ../seapath-themes/logo.png themes/sfl.png
  sed -i 's/contact@savoirfairelinux/seapath@savoirfairelinux/g' test-report.adoc
  # Change contact mailing list to seapath SFL mailing list

  # Generate test report
  cqfd -q init
  if ! CQFD_EXTRA_RUN_ARGS="" cqfd -q run ./compile.py \
      -m -i include -C SEAPATH -p \"SEAPATH Centos Stream 9\" ; then
    die "cqfd error"
  fi
  echo "Test report generated successfully"

  mv "${WORK_DIR}"/ci/test-report-pdf/test-report.pdf "${WORK_DIR}"/seapath-test-report.pdf
}

case "$1" in
  init)
    initialization
    exit 0
    ;;
  conf)
    configure_centos
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
