#!/bin/bash

#==============================================================================
# Arch R - Wi-Fi Connection Script
#==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Arch R Wi-Fi Setup ===${NC}"
echo ""

#------------------------------------------------------------------------------
# Check for Wi-Fi interface
#------------------------------------------------------------------------------
echo "Checking for Wi-Fi interface..."

IFACE=""
for iface in wlan0 wlan1 wlp1s0; do
    if [ -d "/sys/class/net/$iface" ]; then
        IFACE="$iface"
        break
    fi
done

if [ -z "$IFACE" ]; then
    echo -e "${RED}No Wi-Fi interface found!${NC}"
    echo ""
    echo "Troubleshooting:"
    echo "  1. Make sure Wi-Fi adapter is connected"
    echo "  2. Check if driver is loaded: lsmod | grep aic"
    echo "  3. Check dmesg for errors: dmesg | grep -i wifi"
    exit 1
fi

echo -e "${GREEN}Found interface: $IFACE${NC}"
echo ""

#------------------------------------------------------------------------------
# Check NetworkManager
#------------------------------------------------------------------------------
if command -v nmcli &> /dev/null; then
    # Use NetworkManager
    echo "Scanning for networks..."
    echo ""
    
    nmcli device wifi rescan 2>/dev/null
    sleep 2
    
    echo "Available networks:"
    nmcli device wifi list
    echo ""
    
    read -p "Enter network name (SSID): " SSID
    read -sp "Enter password: " PASSWORD
    echo ""
    
    echo "Connecting to $SSID..."
    nmcli device wifi connect "$SSID" password "$PASSWORD"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Connected successfully!${NC}"
        echo ""
        echo "IP Address:"
        ip -4 addr show "$IFACE" | grep inet
    else
        echo -e "${RED}Connection failed!${NC}"
        exit 1
    fi
    
else
    # Fallback to wpa_supplicant
    echo "NetworkManager not available, using wpa_supplicant..."
    
    read -p "Enter network name (SSID): " SSID
    read -sp "Enter password: " PASSWORD
    echo ""
    
    # Create wpa_supplicant config
    WPA_CONF="/tmp/wpa_temp.conf"
    wpa_passphrase "$SSID" "$PASSWORD" > "$WPA_CONF"
    
    # Stop any existing wpa_supplicant
    killall wpa_supplicant 2>/dev/null
    
    # Start wpa_supplicant
    wpa_supplicant -B -i "$IFACE" -c "$WPA_CONF"
    sleep 2
    
    # Get IP via DHCP
    dhcpcd "$IFACE"
    
    echo -e "${GREEN}Connection attempted!${NC}"
    echo ""
    echo "IP Address:"
    ip -4 addr show "$IFACE" | grep inet
fi
