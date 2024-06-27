#!/bin/bash
set -e
pylint --exit-zero $(fdfind -e py --exclude conf.py) \
    >pylint-report.txt
/opt/sonar-scanner/bin/sonar-scanner

detect_sonar_errors.py
