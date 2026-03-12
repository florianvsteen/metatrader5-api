#!/bin/bash
source /scripts/02-common.sh
log_message "RUNNING" "04-install-mt5.sh"

if [ -e "$mt5file" ]; then
    log_message "INFO" "MT5 already installed, skipping."
else
    log_message "INFO" "MT5 not found. Installing..."

    # Set Wine to Windows 10 mode
    $wine_executable reg add "HKEY_CURRENT_USER\\Software\\Wine" /v Version /t REG_SZ /d "win10" /f

    # Wait for network to be available (MetaQuotes CDN must be reachable)
    log_message "INFO" "Waiting for network connectivity..."
    for i in $(seq 1 10); do
        if nc -z download.mql5.com 443 2>/dev/null; then
            log_message "INFO" "Network ready."
            break
        fi
        log_message "INFO" "Network not ready, attempt $i/10, waiting 5s..."
        sleep 5
    done

    # Download the installer
    log_message "INFO" "Downloading MT5 installer..."
    wget --tries=3 --timeout=60 -O /tmp/mt5setup.exe "$mt5setup_url"
    if [ $? -ne 0 ]; then
        log_message "ERROR" "Failed to download MT5 installer."
        exit 1
    fi

    # Run installer - DISPLAY must be set for Wine GUI
    log_message "INFO" "Installing MetaTrader 5..."
    DISPLAY=:0 $wine_executable /tmp/mt5setup.exe /auto
    
    # Wait for installation to complete (installer runs async)
    log_message "INFO" "Waiting for MT5 installation to complete..."
    for i in $(seq 1 60); do
        if [ -e "$mt5file" ]; then
            log_message "INFO" "MT5 installation confirmed."
            break
        fi
        sleep 5
    done

    rm -f /tmp/mt5setup.exe
fi

# Launch MT5
if [ -e "$mt5file" ]; then
    log_message "INFO" "Launching MT5..."
    DISPLAY=:0 $wine_executable "$mt5file" &
else
    log_message "ERROR" "MT5 binary not found after installation attempt."
fi
