#! /usr/bin/python3

import os
import sys
import glob
from junitparser.junitparser import TestCase, JUnitXml, Properties
import textwrap
import argparse
import csv

GREEN_COLOR = "#90EE90"
RED_COLOR = "#F08080"
ORANGE_COLOR = "#ee6644"


class CukiniaTest(TestCase):
    """
    Custom class to get property value in TestCase
    """

    def get_property_value(self, name):
        """
        Gets a property from a testcase.
        """
        props = self.child(Properties)
        if props is None:
            return None
        for prop in props:
            if prop.name == name:
                return prop.value
        return None


def die(error_string):
    print("ERROR : ", error_string)
    sys.exit(1)


# Cukinia test generation
def check_for_id(suite):
    """
    Check in the first test if there is an id. If yes return True otherwise
    return False
    """
    for test in suite:
        if CukiniaTest.fromelem(test).get_property_value("cukinia.id"):
            return True
        else:
            return False


def write_table_header(suite, adoc_file, has_test_id):

    table_header = textwrap.dedent(
        """
        ===== Tests {_suitename_} {_machinepart_}
        [options="header",cols="{_colsize_}",frame=all, grid=all]
        |===
        {_testid_}|Tests |Results
        """
    )

    # Weird tricks to get the classname of the first test of the suite
    # This classname is used as machine name.
    machine_name = next(iter(suite)).classname
    if args.add_machine_name:
        machine_part = "for {}".format(machine_name)
    else:
        machine_part = ""

    if has_test_id:
        adoc_file.write(
            table_header.format(
                _suitename_=suite.name,
                _machinepart_=machine_part,
                _colsize_="2,6,1",
                _testid_="|Test ID",
            )
        )
    else:
        adoc_file.write(
            table_header.format(
                _suitename_=suite.name,
                _machinepart_=machine_part,
                _colsize_="8,1",
                _testid_="",
            )
        )


def write_table_line(test, adoc_file, has_test_id, assigned_anchors):

    table_line_test_id = textwrap.dedent(
        """
        |{_testid_}
        {{set:cellbgcolor!}}
        """
    )

    table_line = textwrap.dedent(
        """
        |{_testanchor_}{_testname_}
        {{set:cellbgcolor!}}
        |{_result_}
        {{set:cellbgcolor:{_color_}}}
        """
    )

    test_anchor = ""
    if has_test_id:
        test_id = test.get_property_value("cukinia.id")
        adoc_file.write(table_line_test_id.format(_testid_=test_id))

        if args.add_machine_name:
            test_anchor = f"[[{test.classname}_{test_id}]]".replace(" ", "_")
        else:
            test_anchor = f"[[{test_id}]]".replace(" ", "_")

        if test_anchor in assigned_anchors:
            test_anchor = ""
        else:
            assigned_anchors.add(test_anchor)

    if test.is_passed:
        adoc_file.write(
            table_line.format(
                _testanchor_=test_anchor,
                _testname_=test.name.replace("|", "|"),
                _result_="PASS",
                _color_=GREEN_COLOR,
            )
        )
    else:
        adoc_file.write(
            table_line.format(
                _testanchor_=test_anchor,
                _testname_=test.name.replace("|", "|"),
                _result_="FAIL",
                _color_=RED_COLOR,
            )
        )


def write_table_footer(suite, adoc_file):
    table_footer = textwrap.dedent(
        """
        |===
        * number of tests: {_nbtests_}
        * number of failures: {_nbfailures_}

        """
    )
    adoc_file.write(
        table_footer.format(_nbtests_=suite.tests, _nbfailures_=suite.failures)
    )


# Generate a compliance matrix for each machine
def generate_compliance_matrix_adoc(matrix, xml_files):

    matrix_header = textwrap.dedent(
        """
            ===== Matrix {_matrixname_} for {_machine_}
            [options="header",cols="6,2,1",frame=all, grid=all]
            |===
            |Requirement |Test id |Status
        """
    )

    matrix_footer = textwrap.dedent(
        """
        |===
        """
    )

    machines_list = []
    for xml in xml_files:
        for suite in xml:
            for test in suite:
                if test.classname not in machines_list:
                    machines_list.append(test.classname)

    return_code = 0

    if not os.path.exists(matrix):
        die("Matrix file {} doesn't exists".format(matrix))
    if not os.path.isfile(matrix):
        die("Matrix file {} is not a file".format(matrix))

    for machine in machines_list:
        with open(
            f"{args.include_dir}/test-{machine}-{os.path.basename(matrix)}.adoc",
            "w",
            encoding="utf-8",
        ) as adoc_file:
            with open(matrix, "r", encoding="utf-8") as matrix_file:
                requirements = list(sorted(csv.reader(matrix_file)))
                # requirements is a list, each item of the list has the form
                # ["requirement name", test_ID]

                adoc_file.write(
                    matrix_header.format(
                        _matrixname_=matrix,
                        _machine_=machine,
                    )
                )

                ret = write_matrix_tests(requirements, machine, xml_files, adoc_file)
                if ret == 1:
                    return_code = 1

                adoc_file.write(matrix_footer)

    return return_code


def write_matrix_tests(requirements, machine_name, xml_files, adoc_file):

    return_code = 0

    matrix_line_req = textwrap.dedent(
        """
        .{_nbtests_}+|{_req_}
        {{set:cellbgcolor!}}
        """
    )
    matrix_line_test = textwrap.dedent(
        """
        |<<{_testlink_},{_id_}>>
        {{set:cellbgcolor!}}
        |{_status_}
        {{set:cellbgcolor:{_color_}}}
        """
    )
    current_requirement = ""
    for req, test_id in requirements:
        # This code section uses the span rows feature of asciidoc
        # https://docs.asciidoctor.org/asciidoc/latest/tables/span-cells/
        if req != current_requirement:
            current_requirement = req
            nb_tests = sum([current_requirement == r[0] for r in requirements])
            # nb_tests control the number of lines the requirement cell will
            # be spanned. This number should be equal to the number of times
            # the same requirement appears
            adoc_file.write(
                matrix_line_req.format(
                    _nbtests_=nb_tests,
                    _req_=req,
                )
            )
        present, passed = check_test(test_id, machine_name, xml_files)
        if args.add_machine_name:
            test_link = f"{machine_name}_{test_id}".replace(" ", "_")
        else:
            test_link = f"{test_id}".replace(" ", "_")
        if not present:
            adoc_file.write(
                matrix_line_test.format(
                    _testlink_=test_link,
                    _id_=test_id,
                    _status_="ABSENT",
                    _color_=ORANGE_COLOR,
                )
            )
            print(f"Test id {test_id} is not present for {machine_name}")
            return_code = 1
        elif passed:
            adoc_file.write(
                matrix_line_test.format(
                    _testlink_=test_link,
                    _id_=test_id,
                    _status_="PASS",
                    _color_=GREEN_COLOR,
                )
            )
        else:
            adoc_file.write(
                matrix_line_test.format(
                    _testlink_=test_link,
                    _id_=test_id,
                    _status_="FAIL",
                    _color_=RED_COLOR,
                )
            )
    return return_code


# This function read all the xml and look for all tests that matches a given ID.
# It return present=True if the ID is found at least once
# It return passed=False if at least one test is failed.
def check_test(test_id, machine_name, xml_files):

    present = False
    passed = True

    for xml in xml_files:
        for suite in xml:
            for test in suite:
                current_id = CukiniaTest.fromelem(test).get_property_value("cukinia.id")
                if current_id == test_id:
                    if test.classname == machine_name or not args.add_machine_name:
                        present = True
                        if not test.is_passed:
                            passed = False
    return present, passed


def generate_xml_adoc(file, assigned_anchors):
    with open(
        f"{args.include_dir}/test-{os.path.basename(file)}.adoc", "w", encoding="utf-8"
    ) as adoc_file:
        xml_file = JUnitXml.fromfile(file)
        for suite in xml_file:
            has_test_id = check_for_id(suite)
            write_table_header(suite, adoc_file, has_test_id)
            for test in suite:
                write_table_line(CukiniaTest.fromelem(test), adoc_file, has_test_id, assigned_anchors)
            write_table_footer(suite, adoc_file)


def parse_arguments():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "-i",
        "--include_dir",
        help="""source directory to use for xml files and additionnal
        adoc files.""",
    )
    parser.add_argument(
        "-x",
        "--xml_files",
        action="append",
        help="""specific xml files to use.""",
    )
    parser.add_argument(
        "-c",
        "--compliance_matrix",
        action="append",
        help="""add the compliance matrix specified in the file.
        Can be used multiple times for multiple matrices to add.""",
    )
    parser.add_argument(
        "-m",
        "--add_machine_name",
        const=True,
        default=False,
        help="""Add the name of the machine in the title of each tables.
        This machine name should be given in the test suite
        using the classname feature of cukinia.""",
        action="store_const",
    )
    return parser.parse_args()


if __name__ == "__main__":
    return_code = 0
    args = parse_arguments()

    # Each test result line is an asciidoc anchor, so it can be accessed
    # when clicking in the compliance matrix
    # If a test id is used multiple times, the same anchor will be used.
    # To avoid that, this set keeps tracks of all assigned anchors.
    assigned_anchors = set()

    xml_files = []
    for f in args.xml_files:
        generate_xml_adoc(f, assigned_anchors)
        xml_files.append(JUnitXml.fromfile(f))

    if args.compliance_matrix:
        for matrix in args.compliance_matrix:
            ret = generate_compliance_matrix_adoc(matrix, xml_files)
            if ret == 1:
                return_code = 1
    sys.exit(return_code)
