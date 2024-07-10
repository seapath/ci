# Copyright (C) 2023 Savoir-faire Linux, Inc.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND noninteractive

RUN set -x \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        asciidoc \
        black \
        fd-find \
        make \
        openjdk-8-jre-headless \
        pylint \
        python3 \
        python3-pip \
        python3-sphinx \
        ruby \
        ruby-asciidoctor-pdf \
        unzip \
        wget \
        gnuplot \
    && rm -rf /var/lib/apt/lists/

RUN pip install junitparser==3.1.0

ARG sonar_version=4.7.0.2747
ARG sonar_repo=https://binaries.sonarsource.com/Distribution/sonar-scanner-cli
RUN set -x \
    && wget -O /tmp/sonar-scanner.zip \
    "${sonar_repo}/sonar-scanner-cli-${sonar_version}.zip" \
    && cd /opt \
    && unzip /tmp/sonar-scanner.zip \
    && rm -f sonar-scanner.zip
RUN ln -s "/opt/sonar-scanner-${sonar_version}" /opt/sonar-scanner
RUN echo 'sonar.host.url=http://j1.sfl.team:9000/' \
    > /opt/sonar-scanner/conf/sonar-scanner.properties
COPY python-sonar.sh /usr/bin/python-sonar.sh
COPY detect_sonar_errors.py /usr/bin/detect_sonar_errors.py

# Install cukinia to compile examples
ADD https://raw.githubusercontent.com/savoirfairelinux/cukinia/master/cukinia /usr/bin/cukinia
RUN chmod +xr /usr/bin/cukinia
