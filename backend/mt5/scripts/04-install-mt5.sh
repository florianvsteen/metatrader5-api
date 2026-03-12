#!/bin/bash
source /scripts/02-common.sh

exec 1> >(tee -a /var/log/mt5_setup.log) 2>&1

log_message "RUNNING" "04-install-mt5.sh"

if [ -e "$mt5file" ]; then
    log_message "INFO" "MT5 already installed, skipping."
else
    log_message "INFO" "MT5 not found. Installing..."

    # Wait for display to be ready
    log_message "INFO" "Waiting for display..."
    for i in $(seq 1 20); do
        DISPLAY=:0 xdpyinfo >/dev/null 2>&1 && break
        log_message "INFO" "Display not ready, attempt $i/20..."
        sleep 3
    done
    log_message "INFO" "Display is ready."

    # Initialize Wine prefix fully
    log_message "INFO" "Initializing Wine prefix..."
    DISPLAY=:0 wineboot --init
    log_message "INFO" "Waiting for Wine prefix to finish initializing..."
    DISPLAY=:0 wineserver --wait
    log_message "INFO" "Wine prefix initialized."

    # Set Wine to Windows 10 mode
    log_message "INFO" "Setting Wine to Windows 10 mode..."
    DISPLAY=:0 $wine_executable reg add "HKEY_CURRENT_USER\\Software\\Wine" /v Version /t REG_SZ /d "win10" /f
    DISPLAY=:0 wineserver --wait

    # Install root certificates so Wine can verify MetaQuotes CDN TLS
    log_message "INFO" "Installing Wine certificates..."
    DISPLAY=:0 winetricks -q certs
    DISPLAY=:0 wineserver --wait

    # Install winhttp so the MT5 installer can make HTTPS calls internally
    log_message "INFO" "Installing winhttp..."
    DISPLAY=:0 winetricks -q winhttp
    DISPLAY=:0 wineserver --wait

    # Wait for network
    log_message "INFO" "Waiting for network..."
    for i in $(seq 1 10); do
        wget -q --spider https://download.mql5.com 2>/dev/null && break
        log_message "INFO" "Network not ready, attempt $i/10..."
        sleep 5
    done
    log_message "INFO" "Network is ready."

    # Download installer
    log_message "INFO" "Downloading MT5 installer..."
    wget --tries=5 --timeout=120 --waitretry=10 \
        --user-agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64)" \
        -O /tmp/mt5setup.exe "$mt5setup_url"

    if [ ! -f /tmp/mt5setup.exe ] || [ ! -s /tmp/mt5setup.exe ]; then
        log_message "ERROR" "Download failed or file is empty."
        exit 1
    fi
    log_message "INFO" "Download complete: $(ls -lh /tmp/mt5setup.exe | awk '{print $5}')"

    # Run installer with HTTP debug logging
    log_message "INFO" "Running MT5 installer..."
    DISPLAY=:0 WINEDEBUG=+winhttp,+wininet,err+all \
        $wine_executable /tmp/mt5setup.exe /auto 2>&1 | tee -a /var/log/mt5_wine_debug.log
    DISPLAY=:0 wineserver --wait
    log_message "INFO" "Installer process exited."

    # Dump relevant Wine HTTP debug lines
    log_message "INFO" "=== WINE HTTP DEBUG ==="
    grep -i "winhttp\|wininet\|connect\|error\|fail\|https\|download" \
        /var/log/mt5_wine_debug.log 2>/dev/null | head -50

    # Poll for completion
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
