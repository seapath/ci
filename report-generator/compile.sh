#!/bin/bash
#
# asciidoc-report an asciidoc pdf builder
#
# Copyright (C) 2022-2023 Savoir-faire Linux Inc.
#
# This program is free software, distributed under the Apache License
# version 2.0, as well as the GNU General Public License version 3, at
# your own convenience. See LICENSE and LICENSE.GPLv3 for details.

TMP_ADOC_FILE=$(readlink -f "test-reports-content.adoc")
GREEN_COLOR="#90EE90"
RED_COLOR="#F08080"
ORANGE_COLOR="#ee6644"

# Standard help message
usage()
{
    cat <<EOF
NAME:
    test-report-pdf an asciidoc pdf test report builder.
    Copyright (C) 2022-2023 Savoir-faire Linux Inc.

SYNOPSIS:
    ./compile.sh [options]

DESCRIPTION:
    This script will automatically look for all .xml files contained in the
    source directory and integrate them in the test report. By default, one
    table will be created for each file containing all test one after another.

    Different tables can be generated for the same file using cukinia tests
    suites in cukinia (`logging suite "string"`).

    A machine name can be specified in the table title using cukinia class
    (`logging class "string"`).

OPTIONS:
    -h: display this message
    -i <dir>: source directory to use for xml files and additionnal adoc files
              ( default is example/ )
    -s: Split test name and ID. Test name must be formated as ID - test name.
EOF
}

die()
{
    echo "error: $1"
    exit 1
}

generate_adoc()
{
    [ -d "$SRC_DIR" ] || die "$SRC_DIR does not exist"
    [ -f "$TMP_ADOC_FILE" ] && rm "$TMP_ADOC_FILE"

    echo "include::$SRC_DIR/prerequisites.adoc[opts=optional]" > "$TMP_ADOC_FILE"
    echo "" >> "$TMP_ADOC_FILE" # new line needed for a new page in asciidoc

    echo "== Test reports" >> "$TMP_ADOC_FILE"

    mapfile -t TEST_FILES < <(find "$SRC_DIR" -name "*.xml")
    for f in "${TEST_FILES[@]}"; do
        echo "including test file $f"
        add_test_file_to_adoc "$f"
    done

    mapfile -t COMP_MAT_FILES < <(find "$SRC_DIR" -name "*.csv")
    if [ -n "${COMP_MAT_FILES[*]}" ] ; then
      echo "== Compliance Matrices" >> "$TMP_ADOC_FILE"
    fi

    for f in "${COMP_MAT_FILES[@]}"; do
        if [ -z "$USE_ID" ] ; then
            echo "can't include $f, test id feature is not enabled"
        else
            echo "including compliance matrix $f"
            add_compliance_matrix "$f"
        fi
    done

    echo "include::$SRC_DIR/notes.adoc[opts=optional]" >> "$TMP_ADOC_FILE"
}

generate_test_row()
{
    local i="$1"
    local j="$2"
    local testcase="$3"
    local xml="$4"

    # Sanitize testcase (escape |)
    testcase=$(echo "$testcase" | sed 's/|/\\|/g')

    if [ -n "$USE_ID" ] ; then
        test_id=$(echo "$testcase" | awk -F ' - ' '{print $1}')
        testcase_name=$(echo "$testcase" | awk -F ' - ' '{$1=""; print }')
        if [ -z "$testcase_name" ] ; then
            testcase_name="$test_id"
            test_id=""
        fi
        echo "|${test_id}" >> "$TMP_ADOC_FILE"
        # Reset color
        echo "{set:cellbgcolor!}" >> "$TMP_ADOC_FILE"
        echo "|${testcase_name}" >> "$TMP_ADOC_FILE"
    else
        testcase_name="$testcase"
        echo "|${testcase_name}" >> "$TMP_ADOC_FILE"
        # Reset color
        echo "{set:cellbgcolor!}" >> "$TMP_ADOC_FILE"
    fi
    if xmlstarlet -q sel -t  -v "////testsuites/testsuite[$i]/testcase[$j]/failure" "$xml"
    then
        echo "|FAIL{set:cellbgcolor:$RED_COLOR}" >> "$TMP_ADOC_FILE"
    else
        echo "|PASS{set:cellbgcolor:$GREEN_COLOR}" >> "$TMP_ADOC_FILE"
    fi
}

add_test_file_to_adoc()
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
        if [ -z "$testname" ] || [ "$testname" == "default" ] ; then
            testname=$(basename "$xml")
        fi
        echo -n "=== Tests $testname" >> "$TMP_ADOC_FILE"
        if [ -n "$classname" ] && [ "$classname" != "cukinia" ] ; then
            echo -n " for $classname" >> "$TMP_ADOC_FILE"
        fi
        echo >> "$TMP_ADOC_FILE"
        if [ -n "$USE_ID" ] ; then
            cols='"2,7,1"'
        fi

        echo "[options=\"header\",cols=$cols,frame=all, grid=all]" >> "$TMP_ADOC_FILE"
        echo "|===" >> "$TMP_ADOC_FILE"
        if [ -n "$USE_ID" ] ; then
            echo -n "|Test ID" >> "$TMP_ADOC_FILE"
        fi
        echo "|Tests |Results" >> "$TMP_ADOC_FILE"

        local j=1
        local testcases=$(xmlstarlet sel -t -v "//testsuite[$i]/testcase/@name" "$xml")
        echo "$testcases" | while read testcase ; do
            generate_test_row "$i" "$j" "$testcase" "$xml"
            let j++
        done
        echo "|===" >> "$TMP_ADOC_FILE"
        echo "{set:cellbgcolor!}" >> "$TMP_ADOC_FILE"
        echo "" >> "$TMP_ADOC_FILE"
        echo "* number of tests: $nb_tests" >> "$TMP_ADOC_FILE"
        echo "* number of failures: $failures" >> "$TMP_ADOC_FILE"
        echo "" >> "$TMP_ADOC_FILE"
    done
}

add_compliance_matrix()
{
  local MATRIX_FILE="$1"

  echo "=== $(basename "$MATRIX_FILE")" >> "$TMP_ADOC_FILE"

  echo "[options=\"header\",cols=\"6,2,1\",frame=all, grid=all]" >> "$TMP_ADOC_FILE"
  echo "|===" >> "$TMP_ADOC_FILE"
  echo "|Requirement |Test id |Status" >> "$TMP_ADOC_FILE"

  current_requirement=""
  sort "$MATRIX_FILE" | while IFS="," read -r requirement id
  do
    # Display the requirement, eventually fitting multiple lines
    if [ "$current_requirement" != "$requirement" ]; then
      nb_tests=$(grep -c "$requirement," "$MATRIX_FILE")
      echo ".$nb_tests+| $requirement" >> "$TMP_ADOC_FILE";
      echo "{set:cellbgcolor!}" >> "$TMP_ADOC_FILE" # Reset color
      current_requirement="$requirement"
    fi
    # Color reset is needed two times cause we use lines spaning in requirements

    # Display a test id in the second column
    echo "|$id" >> "$TMP_ADOC_FILE"
    echo "{set:cellbgcolor!}" >> "$TMP_ADOC_FILE" # Reset color

    # Display the status of the test in the third column
    if grep "<!\[CDATA\[$id" "${TEST_FILES[@]}" | grep -q '<failure'; then
      echo "|FAIL{set:cellbgcolor:$RED_COLOR}" >> "$TMP_ADOC_FILE"
    elif grep -q "name=\"$id" "${TEST_FILES[@]}"; then
      echo "|PASS{set:cellbgcolor:$GREEN_COLOR}" >> "$TMP_ADOC_FILE"
    else
      echo "|ABSENT{set:cellbgcolor:$ORANGE_COLOR}" >> "$TMP_ADOC_FILE"
    fi
  done

  echo "|===" >> "$TMP_ADOC_FILE"
}

SRC_DIR="example"
while getopts ":si:h" opt; do
    case $opt in
    i)
        SRC_DIR="$OPTARG"
        ;;
    s)
        USE_ID="true"
        ;;
    h)
        usage
        exit 0
        ;;
    *)
        echo "Unrecognized option"
        usage
        exit 1
    esac
done
shift $((OPTIND-1))

if [ -z "$SRC_DIR" ] || [ ! -d "$SRC_DIR" ] ; then
    die "$SRC_DIR is not found or is not a directory"
fi

generate_adoc
