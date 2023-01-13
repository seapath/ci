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

if test "$#" -ne 2; then
  usage
  die "invalid usage"
fi

# Prerequisite
if ! type -p cqfd > /dev/null; then
  die "cqfd not found"
fi

PR_BRANCH=$1
PR_HASH=`echo $2 | cut -b 1-7`
CI_DIR=`pwd`
PR_N=`echo $PR_BRANCH | cut -d '/' -f 3`
TIME=`date +%Hh%Mm%S`
CUKINIA_TEST_DIR=$CI_DIR/cukinia_tests
REPORT_NAME=test-report_${PR_HASH}_${TIME}.pdf
REPORT_DIR=$CI_DIR/site/docs/reports/PR-${PR_N}

# Get sources
git clone -q git@github.com:seapath/ansible.git
cd ansible
git fetch -q origin ${PR_BRANCH}
git checkout -q FETCH_HEAD

# Launch tests
LOCAL_ANSIBLE_DIR=/home/virtu/ansible # Local dir that contains keys and inventories
docker run -it --rm -w /mnt -v $(pwd):/mnt -v $LOCAL_ANSIBLE_DIR:/tmp \
ansible:2.9 ansible-playbook \
-i /tmp/seapath_inventories/seapath_cluster_ci.yml \
-i /tmp/seapath_inventories/seapath_ovs_ci.yml \
--key-file /tmp/ci_rsa --skip-tags "package-install" \
/tmp/playbooks/ci_the_one_playbook.yaml

# Create report
cd $CI_DIR/ci/report-generator
cqfd -q init
CQFD_EXTRA_RUN_ARGS="-v $CI_DIR/ansible:/tmp/cukinia-res"
if ! cqfd -q run; then
  die "cqfd error"
fi

# Upload report
git clone -q --depth 1 -b site git@github.com:seapath/ci.git $CI_DIR/site
mkdir -p $REPORT_DIR
mv $CI_DIR/ci/report-generator/main.pdf $REPORT_DIR/$REPORT_NAME
cd $REPORT_DIR
git add $REPORT_NAME
git commit -q -m "upload report $REPORT_NAME"
git push -q origin site

# Give link
echo See test Report at \
https://seapath.github.io/ci/reports/PR-${PR_N}/${REPORT_NAME}

# grep for succes
if grep -q "<failure" $CUKINIA_TEST_DIR/*; then
  RES=1
else
  RES=0
fi

# remove github clone dir and cukinia test dir
rm -rf $CI_DIR
exit $RES
