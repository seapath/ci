#!/bin/bash -e



LATENCY_ADOC_FILE=$(readlink -f "include/latency-test-reports.adoc")
STATS_FILE="include/stats_results"


if [ -f $LATENCY_ADOC_FILE ] ; then
    rm $LATENCY_ADOC_FILE
fi

if [ -f $STATS_FILE ] ; then
    rm $STATS_FILE
fi

if [ -z $1 ] ; then
    echo "Fatal: test result directory not given"
    echo "Hint: ./compile_latency.sh <TEST_RESULTS_DIR>"
    exit 1
fi

# If a previous test was aborted, check if $STATS_FILE and $LATENCY_ADOC_FILE
# exists, and deleting them if so

generate_latency_results()
{
    # Generate graph and stats associated to a publisher and subscriber test
    # Parameters: $1: publisher result file
    # $2: subscriber result file

    local PUB_DATA_FILE=$1
    local SUB_DATA_FILE=$2
    python3 timestamp_analysis/timestamp_analysis.py \
    $PUB_DATA_FILE \
    $SUB_DATA_FILE >> $STATS_FILE
}


add_latency_results()
{
    # Generate and add latency tests results to final report
    # Parameter: $1: path to tests results directory
    echo "==  Latency tests results ==" >> "$LATENCY_ADOC_FILE"
    local TESTS_RESULTS_DIR=$1
    local SUB_RESULTS_FILES_HYPERVISOR="${TESTS_RESULTS_DIR}sub*hypervisor*" # Getting all sub files results
    local PUB_RESULT_FILE_HYPERVISOR="${TESTS_RESULTS_DIR}/pub_results_hypervisor_standalone" # Publisher file result

    # Compute hypervisor subscriber tests results
    for SUB_RESULT_FILE in $SUB_RESULTS_FILES_HYPERVISOR # For each sub result file
    do
        generate_latency_results $PUB_RESULT_FILE_HYPERVISOR $SUB_RESULT_FILE # Generate graph and stats associate to it
        local SUB_MACHINE_NAME="$(echo $SUB_RESULT_FILE|cut -d'/' -f4|cut -d'_' -f4)" # Getting sub hypervisor machine name
        # Output example: $SUB_RESULT_FILE = /tmp/tests_results/sub_results_hypervisor_virtu-ci1 --> $SUB_MACHINE_NAME = virtu-ci1

        echo "=== $SUB_MACHINE_NAME" >> "$LATENCY_ADOC_FILE" # Subtitle for each subscriber
        echo "image::./include/sub_"$SUB_MACHINE_NAME"_delay.png[]" >> "$LATENCY_ADOC_FILE" # Include delay graph
        echo "image::./include/pub_standalone_interval_between.png[]" >> "$LATENCY_ADOC_FILE" # Include time between packets graph
        echo " " >> "$LATENCY_ADOC_FILE"

        sed -i 's/$/ +/' $STATS_FILE # Add '+' character at the end of each file sub stat line for making carriage return
        cat $STATS_FILE >> "$LATENCY_ADOC_FILE" # Add sub stats data in report file
        echo " " >> "$LATENCY_ADOC_FILE"
        rm "$STATS_FILE"
    done


}

add_latency_results $1
