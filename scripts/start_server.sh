#!/bin/bash
# CodeDeploy ApplicationStart hook.
isExistApp=$(pgrep -f /opt/python-app/app.py)
if [[ -z $isExistApp ]]; then
    cd /opt/python-app || exit 1
    nohup /opt/python-venv/bin/python /opt/python-app/app.py > /var/log/python-app.log 2>&1 < /dev/null &
fi
