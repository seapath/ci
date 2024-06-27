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
    '''
    Custom class to get property value in TestCase
    '''
    def get_property_value(self, name):
        '''
        Gets a property from a testcase.
        '''
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
    '''
    Check in the first test if there is an id. If yes return True otherwise
    return False
    '''
    for test in suite:
        if(CukiniaTest.fromelem(test).get_property_value("cukinia.id")):
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


def write_table_line(test, adoc_file, has_test_id):

    table_line_test_id = textwrap.dedent(
        """
        |{_testid_}
        {{set:cellbgcolor!}}
        """
    )

    table_line = textwrap.dedent(
        """
        |{_testname_}
        {{set:cellbgcolor!}}
        |{_result_}
        {{set:cellbgcolor:{_color_}}}
        """
    )

    if has_test_id:
        adoc_file.write(table_line_test_id.format(
            _testid_=test.get_property_value("cukinia.id")))

    if test.is_passed:
        adoc_file.write(
            table_line.format(
                _testname_=test.name.replace('|', '|'),
                _result_="PASS",
                _color_=GREEN_COLOR,
            )
        )
    else:
        adoc_file.write(
            table_line.format(
                _testname_=test.name.replace('|', '|'),
                _result_="FAIL",
                _color_=RED_COLOR
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

def add_compliance_matrix(matrix, xml_files):
    if not os.path.exists(matrix):
        die("Matrix file {} doesn't exists".format(matrix))
    if not os.path.isfile(matrix):
        die("Matrix file {} is not a file".format(matrix))
    matrix_header = textwrap.dedent(
        """
            ===== Matrix {_matrixname_}
            [options="header",cols="6,2,1",frame=all, grid=all]
            |===
            |Requirement |Test id |Status
        """
        )
    with open(f"{args.include_dir}/test-{os.path.basename(matrix)}.adoc", "w", encoding="utf-8") as adoc_file:
        adoc_file.write(matrix_header.format(_matrixname_=matrix))
        with open(matrix, "r", encoding="utf-8") as matrix_file:
            requirements = list(sorted(csv.reader(matrix_file)))
            # requirements is a list, each item of the list has the form
            # ["requirement name", test_ID]
            write_matrix_tests(requirements, xml_files, adoc_file)
            matrix_footer = textwrap.dedent(
                """
                |===
                """
            )
            adoc_file.write(matrix_footer)


def write_matrix_tests(requirements, xml_files, adoc_file):
    matrix_line_req = textwrap.dedent(
        """
        .{_nbtests_}+|{_req_}
        {{set:cellbgcolor!}}
        """
    )
    matrix_line_test = textwrap.dedent(
        """
        |{_id_}
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
        present, passed = check_test(test_id, xml_files)
        if not present:
            adoc_file.write(
                matrix_line_test.format(
                    _id_=test_id,
                    _status_="ABSENT",
                    _color_=ORANGE_COLOR,
                )
            )
            die(f"ERROR : Test id {test_id} is not present")
        elif passed:
            adoc_file.write(
                matrix_line_test.format(
                    _id_=test_id,
                    _status_="PASS",
                    _color_=GREEN_COLOR,
                )
            )
        else:
            adoc_file.write(
                matrix_line_test.format(
                    _id_=test_id,
                    _status_="FAIL",
                    _color_=RED_COLOR,
                )
            )

# This function read all the xml and look for all tests that matches a given ID.
# It return present=True if the ID is found at least once
# It return passed=False if at least one test is failed.
def check_test(test_id, xml_files):

    present = False
    passed = True

    for xml in xml_files:
        for suite in xml:
            for test in suite:
                current_id = CukiniaTest.fromelem(test).get_property_value(
                    "cukinia.id"
                )
                if current_id == test_id:
                    present = True
                    if not test.is_passed:
                        passed = False
    return present, passed

def generate_adoc(file):
    with open(f"{args.include_dir}/test-{os.path.basename(file)}.adoc", "w", encoding="utf-8") as adoc_file:
        xml_file = JUnitXml.fromfile(file)
        for suite in xml_file:
            has_test_id = check_for_id(suite)
            write_table_header(suite, adoc_file, has_test_id)
            for test in suite:
                write_table_line(CukiniaTest.fromelem(test), adoc_file,
                                 has_test_id)
            write_table_footer(suite, adoc_file)
            if args.compliance_matrix:
                if not has_test_id:
                    die(
                    "Can't include compliance matrix, test id feature is not enabled"
                    )

# Report generation
def open_test_files(directory):
    if not os.path.isdir(directory):
        die("Directory {} does not exists".format(directory))
    files = glob.glob(os.path.join(directory, "*.xml"))
    if not files:
        die("No test file found in {}".format(directory))
    xml_files = []
    for f in files:
        xml_files.append(JUnitXml.fromfile(f))
        generate_adoc(f)
    return xml_files

def parse_arguments():
    parser= argparse.ArgumentParser()
    parser.add_argument(
        "-i",
        "--include_dir",
        help="""source directory to use for xml files and additionnal
        adoc files.""",
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

if __name__ == '__main__':
    args = parse_arguments()
    xml_files = open_test_files(args.include_dir)
    if args.compliance_matrix:
        for matrix in args.compliance_matrix:
            add_compliance_matrix(matrix, xml_files)
