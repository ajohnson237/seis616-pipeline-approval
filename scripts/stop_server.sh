#!/bin/bash
# CodeDeploy ApplicationStop hook.
isExistApp=$(pgrep -f /opt/python-app/app.py)
if [[ -n $isExistApp ]]; then
    kill $isExistApp
    sleep 2
fi
exit 0
