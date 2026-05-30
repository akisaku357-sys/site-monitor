#!/bin/bash
cd /workspace
while true; do
    python3 -u /workspace/website_monitor.py >> /workspace/monitor.log 2>&1
    echo "Script crashed at $(date), restarting in 5 seconds..." >> /workspace/monitor.log
    sleep 5
done
