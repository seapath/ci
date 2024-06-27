#!/usr/bin/env python3
import json
import sys

with open(".scannerwork/sonar-report.json", "r") as fd:
    raw = fd.read()

sonar_result = json.loads(raw)

nb_issues = 0

if "issues" in sonar_result:
    for issue in sonar_result["issues"]:
        if issue["status"] == "OPEN" and issue["severity"] in (
            "BLOCKER",
            "CRITICAL",
            "MAJOR",
            "MINOR",
        ):
            nb_issues += 1

if nb_issues > 0:
    sys.exit(1)
