# Continuous Integration on SEAPATH

This repository hosts the code of the CI used on the Ansible repository.

A user guide of the CI is available on [the Wiki page](https://wiki.lfenergy.org/display/SEAP/Continuous+integration+on+SEAPATH).

## Technical implementation

The CI is called through a GitHub Action on Ansible debian-main branch. The script is contained in `.github/workflows/ci-debian.yml`

It is separated in three functions.
- `initialization` which download and prepare Ansible sources to test
- `configure_debian` which setup and hardened Debian
- `launch_test` which deploy tests, run it and upload the test report

Every of these functions is called in a different step in the GitHub Action in order to get categorized logs.

### Initialization

This step creates a temporary directory for the CI and download the CI sources in it. It then downloads and prepare the pull request sources to test.

### Configuration

Before the configuration, a rollback to a default version of Debian is called in order for one CI job not to influence others.
Debian setup and hardening is then launched.
Every of these command are run through Ansible inside a docker container with the use of [cqfd](https://github.com/savoirfairelinux/cqfd).

This `configure_debian` part can fail if there is a problem in the Ansible playbooks of the pull request. In that case, the CI will stop there and will not create any test report. This is of course visible on the GitHub action logs.
This is the only step of the CI that can fail.

### Tests

If configuration is done correctly, the testing process will begin using Ansible and cqfd again.
The test software [Cukinia](https://github.com/savoirfairelinux/cukinia) is deployed on the machine along with test configuration files. The tests are launched and the xml result file is copied back to the runner.
A report generator contained on this CI repository transform this xml file into a beautiful pdf. This report is then uploaded on the branch `reports` on this repository and the link is echo at the end of the script.

The CI end by testing if some failures are present in the xml file and sending an appropriate exit code. This is used in GitHub action to display the CI as failed.
Finally, a clean process removes the temporary directory.
