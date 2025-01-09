#!/bin/bash
#
# Copyright (C) 2023-2024 Savoir-faire Linux, Inc.
# SPDX-License-Identifier: Apache-2.0
#
# This script download the sources of a specific pull request,
# then test it and upload a report given the test results.


if [ "${RUNNER_DEBUG}" == "1" ] ; then
set -x
fi
set -e

die() {
	echo "CI internal failure : $*" 1>&2
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
if [ -z "${INVENTORY_VM}" ] ; then
  INVENTORY_VM=inventories_private/ci_vms.yml
fi
if [ -z "${INVENTORY_PUBLISHER}" ]; then
  INVENTORY_PUBLISHER=inventories_private/ci_publisher.yml
fi
if [ -z "${ANSIBLE_INVENTORY}" ] ; then
  ANSIBLE_INVENTORY="inventories_private/ci_yocto_standalone.yaml,inventories_private/ci_yocto_standalone_aaeon.yaml"
fi
CQFD_EXTRA_RUN_ARGS="-e ANSIBLE_INVENTORY=${ANSIBLE_INVENTORY}"
export CQFD_EXTRA_RUN_ARGS

if [ -z "${PCAP_LOOP}" ] ; then
	PCAP_LOOP=10
fi

if [ -z "${PCAP}" ] ; then
	PCAP="8_streams_4000_SV.pcap"
fi

# Standard help message
usage()
{
    cat <<EOF
    This script is the main launcher for the SEAPATH CI.
    It is separated in many functions in order to display logs properly.
    They should be called one after another.
USAGE:
    ./launch.sh <init|conf|system|deploy_vms|test_vms|test_latency|report>
DESCRIPTION:
    - init: download and prepare the sources.
    - conf: configure SEAPATH.
    - system: launch system tests and gather results.
    - deploy_vms: deploy virtual machines on the standalone machine.
    - test_vms: prepare and launch cukinia tests for VMs.
    - test_latency: prepare and launch latency tests.
    - report: build and upload the test report.
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

  # Prepare ansible repository
  cqfd init
  cqfd -b prepare
  echo "Sources prepared succesfully"

  # Prepare openlab
  cqfd -C ../ci/openlab init
}

# Launch SEAPATH configuration and hardening
configure_seapath() {
  cd ansible
  cqfd run ansible-playbook \
  --skip-tags "package-install" \
  playbooks/ci_standalone_setup.yaml
  echo "SEAPATH set up succesfully"
}

# Prepare and launch cukinia test
# Send the result of the tests as return code
launch_system_tests() {
  cd ansible
  cqfd run ansible-playbook \
  --limit "standalone_machine,cluster_machines" \
  playbooks/ci_all_machines_tests.yaml
  echo "System tests launched successfully"

  # Generate cyclictest report parts
  CPU_CORES=$(cat "${WORK_DIR}/ansible/system_info.adoc" | grep "physical CPUs" |  grep -o "[0-9]\+")
  cd ../ci/openlab
  mv "${WORK_DIR}/ansible/cyclictest_yoctoCI.txt" .
  cqfd run scripts/gen_cyclic_test.sh \
    -i "../cyclictest_yoctoCI.txt" \
    -o "../doc/cyclictest_results_hyp.png" \
    -n "${CPU_CORES}" \
    -l 100

  # Generate test report part
  INCLUDE_DIR=${WORK_DIR}/ci/openlab/include
  mkdir "$INCLUDE_DIR"
  mv "${WORK_DIR}"/ansible/cukinia_*.xml "$INCLUDE_DIR"
  mv "${WORK_DIR}"/ansible/src/bp28-compliance-matrices/* "$INCLUDE_DIR"
  mv "${WORK_DIR}"/ansible/system_info.adoc "$INCLUDE_DIR"
  mv "${WORK_DIR}"/ci/openlab/scripts/cyclictest.adoc "$INCLUDE_DIR/cyclictest_hyp.adoc"

  # Check for kernel backtrace error. This is a random error so it must not
  # stop the CI but just display a warning
  # See https://github.com/seapath/ansible/issues/164
  if grep '<failure' "$INCLUDE_DIR"/*.xml | grep -q '00080'; then
     echo -e "\033[0;33mWarning :\033[0m kernel back trace detected, see \
         https://github.com/seapath/ansible/issues/164"
  fi

  if grep -q "FAILED" "$INCLUDE_DIR/cyclictest_hyp.adoc"; then
    echo "Test fails, See test report in the section 'Upload test report'"
    exit 1
  fi

  # Display test results
  if grep '<failure' "$INCLUDE_DIR"/*.xml | grep -q -v '00080'; then
    echo "Test fails, See test report in the section 'Upload test report'"
    exit 1
  else
    echo "All tests pass"
    exit 0
  fi
}

# Deploy virtual machines on the standalone machine
deploy_vms() {
  # Add VM inventory file
  # This file cannot be added at the beginning of launch-yocto.sh because it is
  # used only during these steps
  ANSIBLE_INVENTORY="${ANSIBLE_INVENTORY},${INVENTORY_VM}"
  CQFD_EXTRA_RUN_ARGS="${CQFD_EXTRA_RUN_ARGS} -e ANSIBLE_INVENTORY=${ANSIBLE_INVENTORY} -v /etc/seapath-ci/vm_file:${WORK_DIR}/ansible/vm_images"

  cd ansible
  cqfd run ansible-playbook \
  playbooks/ci_vms_standalone_ptp.yaml
  echo "test VMs deployed successfully"
}

# Prepare and launch cukinia tests for VMs
# Send the result of the tests as return code
test_vms() {
  # Add VM inventory file
  # This file cannot be added at the beginning of launch-yocto.sh because it is
  # used only during these steps
  ANSIBLE_INVENTORY="${ANSIBLE_INVENTORY},${INVENTORY_VM}"
  CQFD_EXTRA_RUN_ARGS="${CQFD_EXTRA_RUN_ARGS} -e ANSIBLE_INVENTORY=${ANSIBLE_INVENTORY}"

  cd ansible
  cqfd run ansible-playbook \
  --limit VMs \
  playbooks/ci_all_machines_tests.yaml
  echo "System tests launched successfully"

  # Generate test report part
  INCLUDE_DIR=${WORK_DIR}/ci/openlab/include
  mv "${WORK_DIR}"/ansible/cukinia_*.xml "$INCLUDE_DIR"

  # Generate cyclictest report part
  cd ../ci/openlab
  mv "${WORK_DIR}/ansible/cyclictest_guest0.txt" .
  cqfd run scripts/gen_cyclic_test.sh \
    -i "../cyclictest_guest0.txt" \
    -o "../doc/cyclictest_results_vm.png" \
    -n 2 \
    -l 100

  mv "${WORK_DIR}/ci/openlab/scripts/cyclictest.adoc" "$INCLUDE_DIR/cyclictest_vm.adoc"

  if grep -q "FAILED" "$INCLUDE_DIR/cyclictest_vm.adoc"; then
    echo "Test fails, See test report in the section 'Upload test report'"
    exit 1
  fi

  # Display test results
  if grep '<failure' "$INCLUDE_DIR"/*.xml | grep -q -v '00080'; then
    echo "Test fails, See test report in the section 'Upload test report'"
    exit 1
  else
    echo "All tests pass"
    exit 0
  fi
}

# Prepare and launch latency tests
test_latency() {

  # Add inventory files
  # This file cannot be added at the beginning of launch-yocto.sh because it is
  # used only during these steps
  ANSIBLE_INVENTORY="${ANSIBLE_INVENTORY},${INVENTORY_VM},${INVENTORY_PUBLISHER}"
  CQFD_EXTRA_RUN_ARGS="${CQFD_EXTRA_RUN_ARGS} -e ANSIBLE_INVENTORY=${ANSIBLE_INVENTORY}"

  # Build sv_timestamp_logger
  git clone --recurse-submodules -q "https://${SEAPATH_BASE_REPO}/sv_timestamp_logger" ${WORK_DIR}/sv_timestamp_logger
  cd ${WORK_DIR}/sv_timestamp_logger
  docker build . --tag sv_timestamp_logger -f Dockerfile
  docker image save -o sv_timestamp_logger.tar sv_timestamp_logger
  if [ ! -e  "${WORK_DIR}/ansible/ci_latency_tests/build/" ]; then
      mkdir "${WORK_DIR}/ansible/ci_latency_tests/build/"
  fi
  mv sv_timestamp_logger.tar ${WORK_DIR}/ansible/ci_latency_tests/build/
  echo "sv_timestamp_logger built succesfully"

  # Call playbook
  cd ${WORK_DIR}/ansible
  cqfd run ansible-playbook \
  --limit "yoctoCI,guest0,sv_publisher" \
  playbooks/ci_latency_tests.yaml \
  -e "pcap=${PCAP}" \
  -e "pcap_loop=${PCAP_LOOP}"
  echo "Latency tests launched succesfully"

  # Analyse SV timestamps with sv_timestamp_analysis
  sv_timestamp_path="${WORK_DIR}/ansible/ci_latency_tests/sv-timestamp-analysis"
  
  git clone -q "https://${SEAPATH_BASE_REPO}/sv-timestamp-analysis" ${sv_timestamp_path}
  cqfd -d "${sv_timestamp_path}/.cqfd" -f "${sv_timestamp_path}/.cqfdrc" init

  cqfd -d "${sv_timestamp_path}/.cqfd" -f "${sv_timestamp_path}/.cqfdrc" run \
    python3 ${sv_timestamp_path}/sv_timestamp_analysis.py \
      --sub "${WORK_DIR}/ansible/ci_latency_tests/results/ts_guest0.txt" \
      --pub "${WORK_DIR}/ansible/ci_latency_tests/results/ts_sv_publisher.txt" \
      --subscriber_name "guest0" \
      --stream "0" \
      --max_latency "250" \
      --display_max_latency \
      -o "${WORK_DIR}/ansible/ci_latency_tests"

  # Check if latency tests passed
  if grep -q "FAILED" "${WORK_DIR}/ansible/ci_latency_tests/results/latency_tests.adoc"; then
    echo "Test fails, See test report in the section 'Upload test report'"
    exit 1
  else
    echo "All tests pass"
  fi

  # Move report and images to the test report directory
  cp "${WORK_DIR}/ansible/ci_latency_tests/results/latency_tests.adoc" "${WORK_DIR}/ci/openlab/include/"
  mv ${WORK_DIR}/ansible/ci_latency_tests/results/histogram*guest*.png ${WORK_DIR}/ci/openlab/doc/
}

# Generate the test report and upload it
generate_report() {

  cd "${WORK_DIR}/ci/openlab"
  # Replace test-report-pdf default logo by SEAPATH one
  mv "${WORK_DIR}/ci/seapath-themes/logo.png" "themes/sfl.png"

  # Write time duration
  if [ $PCAP_LOOP -ge 60 ]; then
    TEST_DURATION="$(( $PCAP_LOOP / 60 )) minutes"
  else
    TEST_DURATION="$PCAP_LOOP seconds"
  fi
  sed -i "s/@@TEST_DURATION@@/$TEST_DURATION/g" test-report.adoc

  # Generate Yocto CI tests part
  cqfd -q init
  if ! CQFD_EXTRA_RUN_ARGS="" cqfd -q run ./report.py \
          -m -i include \
          -x include/cukinia_yoctoCI.xml \
          -c include/ANSSI-BP28-M-Recommendations.csv \
          -c include/ANSSI-BP28-MI-Recommendations.csv \
          -c include/ANSSI-BP28-MIE-Recommendations.csv; then
            die "cqfd error"
  fi

  # Generate VM tests part
  if ! CQFD_EXTRA_RUN_ARGS="" cqfd -q run ./report.py \
          -m -i include \
          -x include/cukinia_guest0.xml \
          -x include/cukinia_guest1.xml; then
            die "cqfd error"
  fi

  # Generate test report
  if ! CQFD_EXTRA_RUN_ARGS="" cqfd -q run asciidoctor-pdf \
        -r ./extended-pdf-converter.rb \
          -a revdate=$(date "+%-d\ %B\ %Y,\ %H:%M:%S\ %Z") \
          -a year=$(date +%Y) \
          -a author=SEAPATH \
          -a project=\"SEAPATH Yocto\" \
          test-report.adoc; then
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
  # If the report is the first of the PR, the branch need to be created.
  # Otherwise, it just have to be switched on.
  git clone -q --depth 1 -b reports-base-commit \
    "${SEAPATH_SSH_BASE_REPO}/ci.git" "$WORK_DIR/reports"
  cd "$WORK_DIR/reports"
  if ! git ls-remote origin "$REPORT_BRANCH" | grep -q "$REPORT_BRANCH"; then
    git branch "$REPORT_BRANCH"
  else
    git fetch -q origin "$REPORT_BRANCH":"$REPORT_BRANCH"
  fi
  git switch -q "$REPORT_BRANCH"

  mkdir -p "$REPORT_DIR"
  mv "${WORK_DIR}"/ci/openlab/test-report.pdf "$REPORT_DIR/$REPORT_NAME"
  git config --local user.email "ci.seapath@gmail.com"
  git config --local user.name "Seapath CI"
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
    configure_seapath
    exit 0
    ;;
  system)
    launch_system_tests
    exit 0
    ;;
  deploy_vms)
    deploy_vms
    exit 0
    ;;
  test_vms)
    test_vms
    exit 0
    ;;
  test_latency)
    test_latency
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
