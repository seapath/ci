# Continuous Integration on SEAPATH

This repository hosts the code of the CI used on the Ansible repository.

A user guide of the CI is available on [the Wiki page](https://wiki.lfenergy.org/display/SEAP/Continuous+integration+on+SEAPATH).

## Prerequisites

To use CI you must create the file /etc/seapath-ci.conf.This file is a shell
source file where it can be defined variables used by the CI script.
Only `PRIVATE_INVENTORIES_REPO_URL` is mandatory.
- `PRIVATE_INVENTORIES_REPO_URL`: git URL to fetch inventories
- `SEAPATH_BASE_REPO`: git main URL part. eg: github.com/seapath
- `SEAPATH_SSH_BASE_REPO`: git main ssh URL part. eg: git@github.com:seapath
- `REPO_PRIVATE_KEYFILE`: path of the SSH git private key used for pushing the report.
- `ANSIBLE_INVENTORY`: Ansible inventory environment variable as described here: https://docs.ansible.com/ansible/latest/reference_appendices/config.html#envvar-ANSIBLE_INVENTORY
- `SVTOOLS_TARBALL`: path to the svtools binary tarball
- `TRAFGEN_TARBALL`: path to the tafgen binary tarball
- `CA_DIR`: path to the directory containing syslog certificate

## Technical implementation

The CI is called through a GitHub Action on Ansible debian-main branch. The script is contained in `.github/workflows/ci-debian.yml`

It is separated in five functions.
- `initialization` which download and prepare Ansible sources to test
- `configure_debian` which setup and hardened Debian
- `launch_system_test` which deploy cukinia tests, and run it.
- `launch_latency_tests` which launch latency tests on the cluster.
- `generate_report` which generate and upload the final report.

Every of these functions is called in a different step in the GitHub Action in order to get categorized logs.
Every of these function can fail and this will be visible in the steps on Github.

### Initialization

This step creates a temporary directory for the CI and download the CI sources in it. It then downloads and prepare the pull request sources to test.

### Configuration

Before the configuration, a rollback to a default version of Debian is called in order for one CI job not to influence others.
Debian setup and hardening is then launched.
Every of these command are run through Ansible inside a docker container with the use of [cqfd](https://github.com/savoirfairelinux/cqfd).

This `configure_debian` part can fail if there is a problem in the Ansible playbooks of the pull request. In that case, the CI will stop there and will not create any test report. This is of course visible on the GitHub action logs.
This is the only step of the CI that can fail.

### System tests

If configuration is done correctly, the testing process will begin using Ansible and cqfd again.
The test software [Cukinia](https://github.com/savoirfairelinux/cukinia) is deployed on the machine along with test configuration files. The tests are launched and the xml result file is copied back to the runner.

### Latency tests

In order to fit to the IEC-61850 norm, latency tests are run on all cluster machines. Each hypervisor embed a subscriber programm that will receive Sample Values from a unique publisher.
All results will then be gathered in graphs in order to be integrated in the report.
This step only launched if the system tests step is succesful.

### Report Generation

A report generator contained on this CI repository transform this the cukinia xml file and the latency graphs into a beautiful pdf. This report is then uploaded on the branch `reports` on this repository and the link is echo at the end of the script.

Finally, a clean process removes the temporary directory.
