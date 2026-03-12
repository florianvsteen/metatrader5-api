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

    # Initialize Wine prefix
    log_message "INFO" "Initializing Wine prefix..."
    DISPLAY=:0 wineboot --init
    DISPLAY=:0 wineserver --wait

    # Set Wine to Windows 10 mode
    DISPLAY=:0 $wine_executable reg add "HKEY_CURRENT_USER\\Software\\Wine" /v Version /t REG_SZ /d "win10" /f 2>/dev/null
    DISPLAY=:0 wineserver --wait

    # Install winhttp (this works fine)
    log_message "INFO" "Installing winhttp..."
    DISPLAY=:0 winetricks -q winhttp 2>&1 || true
    DISPLAY=:0 wineserver --wait

    # --- Manually fix ucrtbase.dll AFTER all winetricks calls ---
    # winetricks vcrun2019 deletes ucrtbase.dll from syswow64 then fails to reinstall it
    # So we skip winetricks vcrun2019 entirely and fix the DLL directly
    log_message "INFO" "Fixing ucrtbase.dll in syswow64..."

    SYSWOW64="$WINEPREFIX/drive_c/windows/syswow64"

    # Wine ships its own ucrtbase.dll for 32-bit in the host filesystem
    # Find it and copy into the prefix
    WINE32_DLL=""
    for search_path in \
        "/usr/lib/i386-linux-gnu/wine/i386-windows/ucrtbase.dll" \
        "/usr/lib/i386-linux-gnu/wine/ucrtbase.dll" \
        "/usr/lib32/wine/i386-windows/ucrtbase.dll" \
        "/usr/lib32/wine/ucrtbase.dll"; do
        if [ -f "$search_path" ]; then
            WINE32_DLL="$search_path"
            log_message "INFO" "Found Wine 32-bit ucrtbase.dll: $search_path"
            break
        fi
    done

    if [ -z "$WINE32_DLL" ]; then
        log_message "INFO" "Searching entire /usr for ucrtbase.dll..."
        WINE32_DLL=$(find /usr/lib -name "ucrtbase.dll" -path "*i386*" 2>/dev/null | head -1)
        if [ -z "$WINE32_DLL" ]; then
            WINE32_DLL=$(find /usr/lib -name "ucrtbase.dll" 2>/dev/null | head -1)
        fi
        log_message "INFO" "Found via search: $WINE32_DLL"
    fi

    if [ -n "$WINE32_DLL" ]; then
        cp -f "$WINE32_DLL" "$SYSWOW64/ucrtbase.dll"
        log_message "INFO" "Copied ucrtbase.dll to syswow64"
    else
        log_message "ERROR" "ucrtbase.dll not found anywhere on host!"
        log_message "INFO" "All DLLs in /usr/lib/i386-linux-gnu/wine/:"
        ls /usr/lib/i386-linux-gnu/wine/ 2>/dev/null | head -20
        log_message "INFO" "All DLLs in /usr/lib32/wine/ (if exists):"
        ls /usr/lib32/wine/ 2>/dev/null | head -20
    fi

    # Set DLL overrides in registry for the CRT dlls (what vcrun2019 does)
    # This tells Wine to use native DLLs for these
    log_message "INFO" "Setting DLL overrides for CRT..."
    for dll in ucrtbase vcruntime140 msvcp140 concrt140 vcomp140 atl140; do
        DISPLAY=:0 $wine_executable reg add \
            "HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides" \
            /v "$dll" /t REG_SZ /d "native,builtin" /f 2>/dev/null || true
    done
    DISPLAY=:0 wineserver --wait

    # Verify DLL is in place
    if [ -f "$SYSWOW64/ucrtbase.dll" ]; then
        log_message "INFO" "VERIFIED: ucrtbase.dll present in syswow64 ($(ls -lh $SYSWOW64/ucrtbase.dll | awk '{print $5}'))"
    else
        log_message "ERROR" "ucrtbase.dll still missing from syswow64!"
    fi

    # Wait for network
    log_message "INFO" "Waiting for network..."
    for i in $(seq 1 10); do
        wget -q --spider https://download.mql5.com 2>/dev/null && break
        sleep 5
    done

    # Download installer
    log_message "INFO" "Downloading MT5 installer..."
    wget --tries=5 --timeout=120 --waitretry=10 \
        --user-agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64)" \
        -O /tmp/mt5setup.exe "$mt5setup_url"

    if [ ! -s /tmp/mt5setup.exe ]; then
        log_message "ERROR" "Download failed."
        exit 1
    fi
    log_message "INFO" "Download complete: $(ls -lh /tmp/mt5setup.exe | awk '{print $5}')"

    # Run installer
    log_message "INFO" "Running MT5 installer..."
    DISPLAY=:0 WINEDEBUG=err+all \
        $wine_executable /tmp/mt5setup.exe /auto \
        "/InstallPath=C:\\Program Files\\MetaTrader 5" 2>&1 | tee /tmp/mt5_wine_debug.log
    DISPLAY=:0 wineserver --wait

    # Unique errors only
    log_message "INFO" "=== UNIQUE WINE ERRORS ==="
    grep "err:" /tmp/mt5_wine_debug.log 2>/dev/null | sort -u | head -20
    log_message "INFO" "=== END ==="

    # Poll for binary
    log_message "INFO" "Waiting for MT5 binary (up to 6 min)..."
    for i in $(seq 1 72); do
        if [ -e "$mt5file" ]; then
            log_message "INFO" "MT5 binary detected at iteration $i."
            break
        fi
        [ $((i % 6)) -eq 0 ] && log_message "INFO" "Waiting... ($i/72)"
        sleep 5
    done

    rm -f /tmp/mt5setup.exe
fi

if [ -e "$mt5file" ]; then
    log_message "INFO" "Launching MT5..."
    DISPLAY=:0 $wine_executable "$mt5file" &
else
    log_message "ERROR" "MT5 binary not found."
    log_message "INFO" "Listing Program Files:"
    find "$WINEPREFIX/drive_c/Program Files" -maxdepth 2 2>/dev/null | head -20
    log_message "INFO" "Checking syswow64 for ucrtbase:"
    ls -la "$WINEPREFIX/drive_c/windows/syswow64/ucrtbase.dll" 2>/dev/null || log_message "INFO" "Not there"
fi
