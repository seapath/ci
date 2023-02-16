#!/bin/bash
#
# Copyright (C) 2023, RTE (http://www.rte-france.com)
# SPDX-License-Identifier: Apache-2.0
#
# This script download the sources of a specific pull request,
# then test it and upload a report given the test results.
set -e

die() {
	echo "CI internal failure : $@" 1>&2
	exit 1
}

# Standard help message
usage()
{
    cat <<EOF
    This script is the main launcher for the SEAPATH CI.
    It is separated in three functions in order to display logs properly.
    They should be called one after another.
USAGE:
    ./launch.sh <init|conf|test>
EOF
}

# Download and prepare the pull request sources
initialization() {
  if ! type -p cqfd > /dev/null; then
    die "cqfd not found"
  fi

  # Get sources
  git clone -q https://github.com/seapath/ansible
  cd ansible
  git fetch -q origin ${GITHUB_REF}
  git checkout -q FETCH_HEAD
  echo "Pull request sources got succesfully"

  # Prepare ansible repository
  cqfd init
  cqfd -b prepare
  echo "Sources prepared succesfully"
}

# Launch Debian configuration and hardening
configure_debian() {
  cd ansible
  LOCAL_ANSIBLE_DIR=/home/virtu/ansible # Local dir that contains keys and inventories
  CQFD_EXTRA_RUN_ARGS="-v $LOCAL_ANSIBLE_DIR:/tmp/ci-seapath-github" \
  cqfd run ansible-playbook \
  -i /tmp/ci-seapath-github/seapath_inventories/seapath_cluster_ci.yml \
  -i /tmp/ci-seapath-github/seapath_inventories/seapath_ovs_ci.yml \
  --key-file /tmp/ci-seapath-github/ci_rsa \
  --skip-tags "package-install" \
  playbooks/ci_configure.yaml
  echo "Debian set up succesfully"
}

# Prepare and launch cukinia test
# Send the result of the tests as return code
launch_system_tests() {
  cd ansible
  LOCAL_ANSIBLE_DIR=/home/virtu/ansible # Local dir that contains keys and inventories
  CQFD_EXTRA_RUN_ARGS="-v $LOCAL_ANSIBLE_DIR:/tmp/ci-seapath-github" \
  cqfd run ansible-playbook \
  -i /tmp/ci-seapath-github/seapath_inventories/seapath_cluster_ci.yml \
  -i /tmp/ci-seapath-github/seapath_inventories/seapath_ovs_ci.yml \
  --key-file /tmp/ci-seapath-github/ci_rsa \
  --skip-tags "package-install" \
  playbooks/ci_test.yaml
  echo "Test tools deployed successfully"

  # Display test results
  if grep -q "<failure" $CUKINIA_TEST_DIR/*; then
    echo "Test fails"
    exit 1
  else
    echo "All tests pass"
    exit 0
  fi
}

# Deploy subscriber and publisher, generate SV and measure latency time
launch_latency_tests() {
  # TODO
}

# Generate the test report and upload it
generate_report() {

  # Generate test report
  CUKINIA_TEST_DIR=${WORK_DIR}/cukinia
  mkdir $CUKINIA_TEST_DIR
  mv ${WORK_DIR}/ansible/*.xml $CUKINIA_TEST_DIR
  cd ${WORK_DIR}/ci/report-generator
  # TODO: Generate and add latency graphs
  cqfd -q init
  if ! CQFD_EXTRA_RUN_ARGS="-v ${CUKINIA_TEST_DIR}:/tmp/cukinia-res" cqfd -q run; then
    die "cqfd error"
  fi

  # Upload report
  PR_N=`echo $GITHUB_REF | cut -d '/' -f 3`
  TIME=`date +%F_%Hh%Mm%S`
  REPORT_NAME=test-report_${GITHUB_RUN_ID}_${GITHUB_RUN_ATTEMPT}_${TIME}.pdf
  REPORT_DIR=${WORK_DIR}/reports/docs/reports/PR-${PR_N}

  git clone -q --depth 1 -b reports git@github.com:seapath/ci.git \
  --config core.sshCommand="ssh -i ~/.ssh/ci_rsa" $WORK_DIR/reports
  mkdir -p $REPORT_DIR
  mv ${WORK_DIR}/ci/report-generator/main.pdf $REPORT_DIR/$REPORT_NAME
  cd $REPORT_DIR
  git config --local user.email "ci.seapath@gmail.com"
  git config --local user.name "Seapath CI"
  git config --local core.sshCommand "ssh -i ~/.ssh/ci_rsa"
  git add $REPORT_NAME
  git commit -q -m "upload report $REPORT_NAME"
  git push -q origin reports

  echo See test Report at \
  https://github.com/seapath/ci/blob/reports/docs/reports/PR-${PR_N}/${REPORT_NAME}
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
