#!/bin/bash
source /scripts/02-common.sh

exec 1> >(tee -a /var/log/mt5_setup.log) 2>&1

log_message "RUNNING" "04-install-mt5.sh"

if [ -e "$mt5file" ]; then
    log_message "INFO" "MT5 already installed, skipping."
else
    log_message "INFO" "MT5 not found. Installing..."

    # Set Wine to Windows 10 mode
    DISPLAY=:0 $wine_executable reg add "HKEY_CURRENT_USER\\Software\\Wine" /v Version /t REG_SZ /d "win10" /f

    # Wait for network
    log_message "INFO" "Waiting for network..."
    for i in $(seq 1 10); do
        wget -q --spider https://download.mql5.com 2>/dev/null && break
        log_message "INFO" "Network not ready, attempt $i/10..."
        sleep 5
    done

    # Download installer via Linux wget (bypasses Wine network stack)
    log_message "INFO" "Downloading MT5 installer..."
    wget --tries=5 --timeout=120 --waitretry=10 \
        --user-agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64)" \
        -O /tmp/mt5setup.exe "$mt5setup_url"

    if [ ! -f /tmp/mt5setup.exe ] || [ ! -s /tmp/mt5setup.exe ]; then
        log_message "ERROR" "Download failed or file is empty."
        exit 1
    fi

    log_message "INFO" "Running MT5 installer..."
    DISPLAY=:0 WINEDEBUG=err+all $wine_executable /tmp/mt5setup.exe /auto

    # Poll for completion — installer runs async
    log_message "INFO" "Waiting for MT5 to finish installing..."
    for i in $(seq 1 72); do
        if [ -e "$mt5file" ]; then
            log_message "INFO" "MT5 binary detected at iteration $i."
            break
        fi
        log_message "INFO" "Waiting... ($i/72)"
        sleep 5
    done

    rm -f /tmp/mt5setup.exe
fi

# Verify and launch
if [ -e "$mt5file" ]; then
    log_message "INFO" "MT5 installed. Launching..."
    DISPLAY=:0 $wine_executable "$mt5file" &
else
    log_message "ERROR" "MT5 binary not found after install. See logs above for Wine errors."
fi
