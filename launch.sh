#!/bin/bash
#
# Copyright (C) 2023, RTE (http://www.rte-france.com)
# SPDX-License-Identifier: Apache-2.0
#
# This script download the sources of a specific pull request,
# then test it and upload a report given the test results.
set -e

die() {
	echo "ci configuration failed: $@" 1>&2
	exit 1
}

# Standard help message
usage()
{
    cat <<EOF
USAGE:
    ./launch.sh <pull-request-refs> <pull-request-sha>
EOF
}

# Configure and prepare the CI
configuration() {
  if test "$#" -ne 2; then
    usage
    die "invalid usage"
  fi

  # Prerequisite
  if ! type -p cqfd > /dev/null; then
    die "cqfd not found"
  fi

  # Get sources
  git clone -q https://github.com/seapath/ansible
  cd ansible
  git fetch -q origin ${GITHUB_REF}
  git checkout -q FETCH_HEAD

  cqfd init
  cqfd -b prepare
}

# Launch setup and hardening Debian
setup_debian() {
  cd ansible
  LOCAL_ANSIBLE_DIR=/home/virtu/ansible # Local dir that contains keys and inventories
  CQFD_EXTRA_RUN_ARGS="-v $LOCAL_ANSIBLE_DIR:/tmp" cqfd run ansible-playbook \
  -i /tmp/seapath_inventories/seapath_cluster_ci.yml \
  -i /tmp/seapath_inventories/seapath_ovs_ci.yml \
  --key-file /tmp/ci_rsa --skip-tags "package-install" \
  playbooks/ci_restore_snapshot.yaml \
  playbooks/cluster_setup_debian.yaml \
  playbooks/cluster_setup_hardened_debian.yaml
}

# Prepare, launch test and upload test report
launch_test() {
  WORK_DIR=`pwd`

  cd ansible
  LOCAL_ANSIBLE_DIR=/home/virtu/ansible # Local dir that contains keys and inventories
  CQFD_EXTRA_RUN_ARGS="-v $LOCAL_ANSIBLE_DIR:/tmp" cqfd run ansible-playbook \
  -i /tmp/seapath_inventories/seapath_cluster_ci.yml \
  -i /tmp/seapath_inventories/seapath_ovs_ci.yml \
  --key-file /tmp/ci_rsa --skip-tags "package-install" \
  playbooks/test_deploy_cukinia.yaml \
  playbooks/test_deploy_cukinia_tests.yaml \
  playbooks/test_run_cukinia.yaml

  # Create report

  CUKINIA_TEST_DIR=${WORK_DIR}/cukinia
  mkdir $CUKINIA_TEST_DIR
  mv $WORK_DIR/ansible/*.xml $CUKINIA_TEST_DIR
  cd $WORK_DIR/ci/report-generator
  cqfd -q init
  if ! CQFD_EXTRA_RUN_ARGS="-v $CUKINIA_TEST_DIR:/tmp/cukinia-res" cqfd -q run; then
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
  mv $WORK_DIR/ci/report-generator/main.pdf $REPORT_DIR/$REPORT_NAME
  cd $REPORT_DIR
  git config --local user.email "ci.seapath@gmail.com"
  git config --local user.name "Seapath CI"
  git config --local core.sshCommand "ssh -i ~/.ssh/ci_rsa"
  git add $REPORT_NAME
  git commit -q -m "upload report $REPORT_NAME"
  git push -q origin reports

  # Give link
  echo See test Report at \
  https://github.com/seapath/ci/blob/reports/docs/reports/PR-${PR_N}/${REPORT_NAME}

  # grep for succes
  if grep -q "<failure" $CUKINIA_TEST_DIR/*; then
    RES=1
  else
    RES=0
  fi

  # remove github clone dir and cukinia test dir
  rm -rf $WORK_DIR
  exit $RES
}

configuration
setup
test
