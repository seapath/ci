#!/bin/bash
#
# Copyright (C) 2023, RTE (http://www.rte-france.com)
# Copyright (C) 2024 Savoir-faire Linux, Inc.
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
  # Get sources
  git clone -q https://github.com/seapath/ansible
  cd ansible
  git fetch -q origin ${GITHUB_REF}
  git checkout -q FETCH_HEAD
  echo "Pull request sources downloaded succesfully"
  if [ ! -f ansible-lint.conf ] ; then
      echo "No ansible-lint available. Skipping linting."
      exit 0
  fi
  # Get cqfd
  wget https://raw.githubusercontent.com/savoirfairelinux/cqfd/8142616feca2a2832693f43dfe70b31c64e723f0/cqfd -O cqfd
  chmod +x cqfd
  touch .gitconfig
  # Prepare ansible repository
  ./cqfd init
  ./cqfd -b prepare
  echo "Sources prepared succesfully"
}

# Launch ansible-lint
ansible_lint() {
  cd ansible
  if [ ! -f ansible-lint.conf ] ; then
      echo "No ansible-lint available. Skipping linting."
      exit 0
  fi
  ./cqfd -b ansible-lint
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
