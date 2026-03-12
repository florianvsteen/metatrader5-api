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
    DISPLAY=:0 wineserver --wait
    log_message "INFO" "Wine prefix initialized."

    # --- FIX: manually seed ucrtbase.dll into syswow64 ---
    # winetricks cannot install vcrun2019 because regedit itself needs ucrtbase.dll
    # Wine ships 32-bit DLLs on the host in /usr/lib/i386-linux-gnu/wine/
    # We copy them directly into the Wine prefix syswow64 directory.
    log_message "INFO" "Seeding 32-bit ucrtbase.dll into Wine prefix..."

    SYSWOW64="$WINEPREFIX/drive_c/windows/syswow64"
    SYSTEM32="$WINEPREFIX/drive_c/windows/system32"

    # Wine 32-bit DLL locations on Debian/Ubuntu
    WINE32_PATHS=(
        "/usr/lib/i386-linux-gnu/wine/i386-windows"
        "/usr/lib/i386-linux-gnu/wine"
        "/usr/lib32/wine/i386-windows"
        "/usr/lib32/wine"
    )

    wine32_dir=""
    for p in "${WINE32_PATHS[@]}"; do
        if [ -f "$p/ucrtbase.dll" ]; then
            wine32_dir="$p"
            log_message "INFO" "Found Wine 32-bit DLLs at: $p"
            break
        fi
    done

    if [ -n "$wine32_dir" ]; then
        # Copy key 32-bit DLLs that are missing from syswow64
        for dll in ucrtbase.dll sechost.dll; do
            if [ -f "$wine32_dir/$dll" ] && [ ! -f "$SYSWOW64/$dll" ]; then
                cp "$wine32_dir/$dll" "$SYSWOW64/$dll"
                log_message "INFO" "Copied $dll to syswow64"
            fi
        done
    else
        log_message "WARNING" "Wine 32-bit DLL directory not found. Searching..."
        find /usr/lib -name "ucrtbase.dll" 2>/dev/null | head -5 | while read f; do
            log_message "INFO" "Found: $f"
        done

        # Try to install wine32 packages if missing
        log_message "INFO" "Attempting to install wine32 i386 support..."
        dpkg --add-architecture i386 2>/dev/null || true
        apt-get update -qq 2>/dev/null || true
        apt-get install -y -qq wine32 2>/dev/null || true

        # Search again after potential install
        for p in "${WINE32_PATHS[@]}"; do
            if [ -f "$p/ucrtbase.dll" ]; then
                wine32_dir="$p"
                break
            fi
        done
        if [ -n "$wine32_dir" ]; then
            cp "$wine32_dir/ucrtbase.dll" "$SYSWOW64/ucrtbase.dll" 2>/dev/null || true
            log_message "INFO" "Copied ucrtbase.dll after wine32 install"
        fi
    fi

    # Verify the DLL is now present
    if [ -f "$SYSWOW64/ucrtbase.dll" ]; then
        log_message "INFO" "OK: ucrtbase.dll is present in syswow64"
    else
        log_message "WARNING" "ucrtbase.dll still missing - install may still fail"
    fi

    # Set Wine to Windows 10 mode
    log_message "INFO" "Setting Wine to Windows 10 mode..."
    DISPLAY=:0 $wine_executable reg add "HKEY_CURRENT_USER\\Software\\Wine" /v Version /t REG_SZ /d "win10" /f 2>/dev/null
    DISPLAY=:0 wineserver --wait

    # Now install vcrun2019 - regedit should work now that ucrtbase exists
    log_message "INFO" "Installing vcrun2019 (forced)..."
    DISPLAY=:0 winetricks -q --force vcrun2019 2>&1 || log_message "WARNING" "vcrun2019 install had errors (may be ok)"
    DISPLAY=:0 wineserver --wait

    # Install winhttp
    log_message "INFO" "Installing winhttp..."
    DISPLAY=:0 winetricks -q winhttp 2>&1 || true
    DISPLAY=:0 wineserver --wait

    # Wait for network
    log_message "INFO" "Waiting for network..."
    for i in $(seq 1 10); do
        wget -q --spider https://download.mql5.com 2>/dev/null && break
        log_message "INFO" "Network not ready, attempt $i/10..."
        sleep 5
    done

    # Download installer
    log_message "INFO" "Downloading MT5 installer..."
    wget --tries=5 --timeout=120 --waitretry=10 \
        --user-agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64)" \
        -O /tmp/mt5setup.exe "$mt5setup_url"

    if [ ! -s /tmp/mt5setup.exe ]; then
        log_message "ERROR" "Download failed or file is empty."
        exit 1
    fi
    log_message "INFO" "Download complete: $(ls -lh /tmp/mt5setup.exe | awk '{print $5}')"

    # Run MT5 installer
    log_message "INFO" "Running MT5 installer..."
    DISPLAY=:0 WINEDEBUG=err+all \
        $wine_executable /tmp/mt5setup.exe /auto \
        "/InstallPath=C:\\Program Files\\MetaTrader 5" 2>&1 | tee /tmp/mt5_wine_debug.log
    DISPLAY=:0 wineserver --wait

    # Show only unique errors
    log_message "INFO" "=== UNIQUE WINE ERRORS ==="
    grep -i "err:" /tmp/mt5_wine_debug.log 2>/dev/null | sort -u | head -30
    log_message "INFO" "=== END ERRORS ==="

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

# Verify and launch
if [ -e "$mt5file" ]; then
    log_message "INFO" "MT5 installed successfully. Launching..."
    DISPLAY=:0 $wine_executable "$mt5file" &
else
    log_message "ERROR" "MT5 binary not found after all install attempts."
    log_message "INFO" "Listing Wine C drive for diagnostics..."
    find "$WINEPREFIX/drive_c/Program Files" -maxdepth 2 2>/dev/null | head -20
fi
