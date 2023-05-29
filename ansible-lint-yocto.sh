#!/bin/bash
#
# Copyright (C) 2023, RTE (http://www.rte-france.com)
# SPDX-License-Identifier: Apache-2.0
#
# This script download the sources of a specific pull request,
# then configure and launch ansible-lint on it
set -e

die() {
  echo "linter internal failure : $@" 1>&2
  exit 1
}

# Standard help message
usage()
{
    cat <<EOF
    This script is the launcher for the ansible-linter on SEAPATH ansible.
    It is separated in two functions in order to display logs properly.
    They should be called one after another.
USAGE:
    ./launch.sh <init|lint>
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
  echo "Pull request sources downloaded succesfully"

  # Prepare ansible repository
  echo "RUN apt-get install -y ansible-lint" >> .cqfd/docker/Dockerfile
  cqfd init
  cqfd -b prepare
  echo "Sources prepared succesfully"
}

# Launch ansible-lint
ansible_lint() {
  cp ci/ansible-lint.conf ansible
  cd ansible
  INVENTORY=/home/github/ci-private-files/ci_yocto_standalone.yaml
  CQFD_EXTRA_RUN_ARGS=" \
    -v $INVENTORY:/etc/ansible/hosts/ci_yocto_standalone.yaml \
    -v $WORK_DIR/ansible/ceph-ansible/roles:/etc/ansible/roles \
    " \
  cqfd run ansible-lint -c ansible-lint.conf
}

case "$1" in
  init)
    initialization
    exit 0
    ;;
  lint)
    ansible_lint
    exit 0
    ;;
  *)
    usage
    die "Unknown command"
    ;;
esac
