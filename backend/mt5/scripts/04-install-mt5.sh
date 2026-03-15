#!/bin/bash
source /scripts/02-common.sh

log_message "RUNNING" "04-install-mt5.sh"

# Wait for display
log_message "INFO" "Waiting for display..."
for i in $(seq 1 20); do
    DISPLAY=:0 xdpyinfo >/dev/null 2>&1 && break
    log_message "INFO" "Display not ready, attempt $i/20..."
    sleep 3
done
log_message "INFO" "Display ready."

# Initialize Wine prefix if first run
if [ ! -f "$WINEPREFIX/system.reg" ]; then
    log_message "INFO" "Initializing Wine prefix (first run)..."
    DISPLAY=:0 wineboot --init
    DISPLAY=:0 wineserver --wait

    # Set Windows 10 mode
    DISPLAY=:0 $wine_executable reg add "HKEY_CURRENT_USER\\Software\\Wine" /v Version /t REG_SZ /d "win10" /f 2>/dev/null
    DISPLAY=:0 wineserver --wait
    log_message "INFO" "Wine prefix initialized."
else
    log_message "INFO" "Wine prefix already exists, skipping init."
fi

# Launch MT5
if [ -e "$mt5file" ]; then
    log_message "INFO" "Launching MT5: $mt5file"
    DISPLAY=:0 $wine_executable "$mt5file" &
else
    log_message "ERROR" "MT5 binary not found at: $mt5file"
    log_message "INFO" "Contents of Program Files:"
    ls "$WINEPREFIX/drive_c/Program Files/" 2>/dev/null
    log_message "INFO" "Please copy MetaTrader 5 installation folder to:"
    log_message "INFO" "$WINEPREFIX/drive_c/Program Files/MetaTrader 5/"
fi
