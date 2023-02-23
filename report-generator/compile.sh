#!/bin/bash
#
# asciidoc-report an asciidoc pdf builder
#
# Copyright (C) 2022-2023 Savoir-faire Linux Inc.
#
# This program is free software, distributed under the Apache License
# version 2.0, as well as the GNU General Public License version 3, at
# your own convenience. See LICENSE and LICENSE.GPLv3 for details.

TEST_ADOC_FILE=$(readlink -f "include/test-reports.adoc")

# Standard help message
usage()
{
    cat <<EOF
NAME:
    asciidoc-report an asciidoc pdf builder.
    Copyright (C) 2022-2023 Savoir-faire Linux Inc.

USAGE:
    ./compile.sh [options]

OPTIONS:
    -h: display this message
    -i <dir>: source Junit directory to use
    -s: Split test name and ID. Test name must be formated as ID - test name.
EOF
}

die()
{
    echo "error: $1"
    exit 1
}

integrate_all()
{
    [ -d "$XML_SRC_DIR" ] || die "$XML_SRC_DIR does not exist"
    [ -f "$TEST_ADOC_FILE" ] && rm "$TEST_ADOC_FILE"
    echo "== Test reports" > "$TEST_ADOC_FILE"

    for f in $(find "$XML_SRC_DIR" -name "*.xml"); do
        add_xml_to_adoc "$f" "$TEST_ADOC_FILE"
    done
}

generate_row()
{
    local i="$1"
    local j="$2"
    local testcase="$3"
    local xml="$4"
    local green_color="#90EE90"
    local red_color="#F08080"

    # Sanitize testcase (escape |)
    testcase=$(echo "$testcase" | sed 's/|/\\|/g')

    if [ -n "$USE_ID" ] ; then
        test_id=$(echo "$testcase" | awk -F ' - ' '{print $1}')
        testcase_name=$(echo "$testcase" | awk -F ' - ' '{$1=""; print }')
        if [ -z "$testcase_name" ] ; then
            testcase_name="$test_id"
            test_id=""
        fi
        echo "|${test_id}" >> "$TEST_ADOC_FILE"
        # Reset color
        echo "{set:cellbgcolor!}" >> "$TEST_ADOC_FILE"
        echo "|${testcase_name}" >> "$TEST_ADOC_FILE"
    else
        testcase_name="$testcase"
        echo "|${testcase_name}" >> "$TEST_ADOC_FILE"
        # Reset color
        echo "{set:cellbgcolor!}" >> "$TEST_ADOC_FILE"
    fi
    if $(xmlstarlet -q sel -t  -v "////testsuites/testsuite[$i]/testcase[$j]/failure" "$xml")
    then
        echo "|FAIL{set:cellbgcolor:$red_color}" >> "$TEST_ADOC_FILE"
    else
        echo "|PASS{set:cellbgcolor:$green_color}" >> "$TEST_ADOC_FILE"
    fi
}

add_xml_to_adoc()
{
    local xml="$1"
    local nb_suites="$(( $(xmlstarlet sel -t -v  '//testsuite/@name' "$xml"\
        |wc -l) +1 ))"
    for i in $(seq 1 ${nb_suites}) ; do
        local testname=$(xmlstarlet sel -t -v "//testsuite[$i]/@name" "$xml")
        local classname=$(xmlstarlet sel -t -v "//testsuite[$i]/testcase[1]/@classname" "$xml")
        local nb_tests=$(xmlstarlet sel -t -v "//testsuite[$i]/@tests" "$xml")
        local failures=$(xmlstarlet sel -t -v "//testsuite[$i]/@failures" "$xml")
        local cols='"7,1"'
        if [ -z "$testname" -o "$testname" == "default" ] ; then
            testname=$(basename $xml)
        fi
        echo -n "=== Tests $testname" >> "$TEST_ADOC_FILE"
        if [ -n "$classname" -a "$classname" != "cukinia" ] ; then
            echo -n " for $classname" >> "$TEST_ADOC_FILE"
        fi
        echo >> "$TEST_ADOC_FILE"
        if [ -n "$USE_ID" ] ; then
            cols='"2,7,1"'
        fi

        echo "[options=\"header\",cols=$cols,frame=all, grid=all]" >> "$TEST_ADOC_FILE"
        echo "|===" >> "$TEST_ADOC_FILE"
        if [ -n "$USE_ID" ] ; then
            echo -n "|Test ID" >> "$TEST_ADOC_FILE"
        fi
        echo "|Tests |Results" >> "$TEST_ADOC_FILE"

        local j=1
        while read testcase ; do
            generate_row "$i" "$j" "$testcase" "$xml"
            let j++
        done < <(xmlstarlet sel -t -v "//testsuite[$i]/testcase/@name" "$xml")
        echo "|===" >> "$TEST_ADOC_FILE"
        echo "{set:cellbgcolor!}" >> "$TEST_ADOC_FILE"
        echo "" >> "$TEST_ADOC_FILE"
        echo "* number of tests: $nb_tests" >> "$TEST_ADOC_FILE"
        echo "* number of failures: $failures" >> "$TEST_ADOC_FILE"
        echo "" >> "$TEST_ADOC_FILE"
    done

}

while getopts ":si:h" opt; do
    case $opt in
    i)
        XML_SRC_DIR="$OPTARG"
        ;;
    s)
        USE_ID="true"
        ;;
    h)
        usage
        exit 0
        ;;
    esac
done
shift $((OPTIND-1))

if [ -z "$XML_SRC_DIR" ] || [ ! -d "$XML_SRC_DIR" ] ; then
    die "$XML_SRC_DIR is not found or is not a directory"
fi

integrate_all
