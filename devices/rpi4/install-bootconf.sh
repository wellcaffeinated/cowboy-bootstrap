#!/bin/bash
set -euo pipefail

# Raspberry Pi 4 PXE Boot Configuration Installer
# Usage: curl -sSL <url-to-this-script> | sudo bash

echo "========================================"
echo "Raspberry Pi 4 PXE Boot Setup"
echo "========================================"
echo

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "ERROR: This script must be run as root (use sudo)"
   exit 1
fi

# Check if running on Raspberry Pi
if [[ ! -f /proc/device-tree/model ]]; then
    echo "ERROR: Not running on a Raspberry Pi"
    exit 1
fi

MODEL=$(cat /proc/device-tree/model | tr -d '\0')
echo "Detected: $MODEL"

# Verify it's a Raspberry Pi 4
if [[ ! "$MODEL" =~ "Raspberry Pi 4" ]]; then
    echo "WARNING: This script is designed for Raspberry Pi 4"
    echo "Detected model: $MODEL"
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo
echo "Installing/updating rpi-eeprom tools..."
apt-get update -qq
apt-get install -y rpi-eeprom

echo
echo "Current EEPROM configuration:"
echo "----------------------------"
rpi-eeprom-config | grep -E "BOOT_ORDER|NET_BOOT" || echo "(no boot settings found)"
echo

# Create temporary bootconf file
BOOTCONF_FILE=$(mktemp)
trap "rm -f $BOOTCONF_FILE" EXIT

cat > "$BOOTCONF_FILE" <<'EOF'
# Raspberry Pi 4 Boot Configuration for PXE Network Boot

[all]
# Disable boot UART output for cleaner boot
BOOT_UART=0

# Enable wake on GPIO
WAKE_ON_GPIO=1

# Don't power off on halt (useful for debugging)
POWER_OFF_ON_HALT=0

# Boot order: Network first, then SD card, then USB
# 0x1 = SD card boot
# 0x2 = Network boot
# 0x4 = USB boot
# Order is right to left, so 0x421 = try USB, then SD, then network
BOOT_ORDER=0x421

# Network boot configuration
# TFTP_PREFIX: 0 = use serial number as subdirectory
TFTP_PREFIX=0

# Enable network boot with IPv4
NET_BOOT_IPV4=1

# Disable IPv6 network boot (optional, for performance)
NET_BOOT_IPV6=0

# Network timeout in milliseconds
NET_BOOT_TIMEOUT=10000

# DHCP timeout
DHCP_TIMEOUT=10000

# Use DHCP option 66 (TFTP server) and 67 (bootfile name)
DHCP_OPTION66=1
DHCP_OPTION67=1
EOF

echo "Applying boot configuration..."
echo "Boot order: USB → SD Card → Network (0x421)"

# Get latest stable EEPROM image
LATEST_EEPROM=$(ls -t /lib/firmware/raspberrypi/bootloader/stable/pieeprom-*.bin 2>/dev/null | head -n1)

if [[ -z "$LATEST_EEPROM" ]]; then
    echo "ERROR: Could not find EEPROM image in /lib/firmware/raspberrypi/bootloader/stable/"
    exit 1
fi

echo "Using EEPROM image: $(basename $LATEST_EEPROM)"

# Create new EEPROM image with custom config
NEW_EEPROM=$(mktemp)
trap "rm -f $BOOTCONF_FILE $NEW_EEPROM" EXIT

rpi-eeprom-config --out "$NEW_EEPROM" --config "$BOOTCONF_FILE" "$LATEST_EEPROM"

echo
echo "Flashing EEPROM with new configuration..."
rpi-eeprom-update -d -f "$NEW_EEPROM"

echo
echo "========================================"
echo "SUCCESS! Boot configuration updated"
echo "========================================"
echo
echo "New configuration:"
echo "-----------------"
rpi-eeprom-config "$NEW_EEPROM" | grep -E "BOOT_ORDER|NET_BOOT"
echo
echo "A REBOOT is required for changes to take effect."
echo
read -p "Reboot now? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Rebooting in 3 seconds..."
    sleep 3
    reboot
else
    echo "Please reboot manually when ready: sudo reboot"
fi
