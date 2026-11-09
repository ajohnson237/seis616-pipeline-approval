#!/bin/bash
# CodeDeploy AfterInstall hook.
# Installs the app's Python packages into a virtual environment. Installing them system-wide
# on Ubuntu 22.04 fails because pip cannot replace the OS-managed 'blinker' package Flask needs.
set -e
apt-get update -y
apt-get install -y python3-pip python3-venv
python3 -m venv /opt/python-venv
/opt/python-venv/bin/pip install -r /opt/python-app/requirements.txt
