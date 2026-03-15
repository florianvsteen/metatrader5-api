#!/bin/bash
source /scripts/02-common.sh

log_message "RUNNING" "07-start-wine-flask.sh"

# Wait for MT5 to be fully running before starting Flask
log_message "INFO" "Waiting for MT5 terminal to be ready..."
for i in $(seq 1 30); do
    if pgrep -f "terminal64.exe" > /dev/null; then
        log_message "INFO" "MT5 terminal detected, waiting 10s for full initialization..."
        sleep 10
        break
    fi
    log_message "INFO" "Waiting for MT5... ($i/30)"
    sleep 5
done

log_message "INFO" "Starting Flask server in Wine environment..."
wine python /app/app.py &
FLASK_PID=$!

sleep 5

if ps -p $FLASK_PID > /dev/null; then
    log_message "INFO" "Flask server started with PID $FLASK_PID."
else
    log_message "ERROR" "Failed to start Flask server."
    exit 1
fi
