# Raspberry Pi 4 PXE Boot Configuration

This directory contains boot configuration for Raspberry Pi 4 devices to enable PXE network boot.

## Boot Order

The `bootconf.txt` configures the boot order as:
1. **USB** (0x4)
2. **SD Card** (0x1)
3. **Network/PXE** (0x2)

Boot order value: `0x421` (read right to left)

## Quick Install (One-Liner)

On your Raspberry Pi 4, run:

```bash
curl -sSL https://raw.githubusercontent.com/wellcaffeinated/cowboy-bootstrap/master/devices/rpi4/install-bootconf.sh | sudo bash
```

Or using wget:

```bash
wget -qO- https://raw.githubusercontent.com/wellcaffeinated/cowboy-bootstrap/master/devices/rpi4/install-bootconf.sh | sudo bash
```

## Applying Configuration to Raspberry Pi 4

### Method 1: Update EEPROM with rpi-eeprom-config

1. Boot your Raspberry Pi with Raspberry Pi OS
2. Update the EEPROM tools:
   ```bash
   sudo apt update
   sudo apt install rpi-eeprom
   ```

3. Read current EEPROM config:
   ```bash
   sudo rpi-eeprom-config
   ```

4. Apply the new boot configuration:
   ```bash
   sudo rpi-eeprom-config --edit
   ```
   Then paste the contents of `bootconf.txt` and save

5. Reboot to apply:
   ```bash
   sudo reboot
   ```

### Method 2: Flash EEPROM with custom config

1. Read current EEPROM:
   ```bash
   sudo rpi-eeprom-config > current-bootconf.txt
   ```

2. Merge your settings from `bootconf.txt` with `current-bootconf.txt`

3. Create new EEPROM image:
   ```bash
   sudo rpi-eeprom-config --out pieeprom-new.bin --config current-bootconf.txt /lib/firmware/raspberrypi/bootloader/stable/pieeprom-*.bin
   ```

4. Flash the new EEPROM:
   ```bash
   sudo rpi-eeprom-update -d -f pieeprom-new.bin
   sudo reboot
   ```

## Verify Configuration

After reboot, verify the settings:
```bash
sudo rpi-eeprom-config
```

Check for `BOOT_ORDER=0x421` in the output.

## Network Boot Requirements

For PXE boot to work, ensure:
- DHCP server provides IP address
- DHCP option 66 points to TFTP server
- DHCP option 67 specifies boot file (e.g., `bootcode.bin` or iPXE)
- TFTP server has boot files in the correct directory structure
