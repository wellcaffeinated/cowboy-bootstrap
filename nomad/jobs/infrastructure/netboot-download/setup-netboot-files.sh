#!/usr/bin/env bash
set -euo pipefail

# This script orchestrates the download and setup of all necessary files
# for a multi-architecture UEFI PXE netboot environment for Ubuntu Server.

# --- Configuration ---
UBUNTU_VERSION=${1:-"24.04"}
ARCH_LIST=${2:-"arm64 amd64"}
NETBOOT_ROOT=${3:-"/netboot"}

# --- Functions ---

usage() {
    cat <<EOF
Usage: $0 [version] [arch_list] [netboot_root]

Orchestrates the download and setup of UEFI PXE netboot files for Ubuntu Server.

Arguments:
  version         The Ubuntu version to download (default: "24.04").
  arch_list       A space-separated list of architectures (default: "arm64 amd64").
  netboot_root    The root directory for TFTP/HTTP files (default: "/netboot").

Example:
  $0 24.04 "arm64 amd64" /opt/netboot
EOF
    exit 1
}

# --- Main Execution ---

echo "==> Starting Ubuntu Netboot Setup"
echo "    Version:        ${UBUNTU_VERSION}"
echo "    Architectures:  ${ARCH_LIST}"
echo "    Netboot Root:   ${NETBOOT_ROOT}"
echo

# Create the main grub directory and initialize the grub.cfg file.
GRUB_CFG_PATH="${NETBOOT_ROOT}/grub/grub.cfg"
echo "==> Initializing main GRUB configuration at ${GRUB_CFG_PATH}..."
mkdir -p "${NETBOOT_ROOT}/grub"
cat > "${GRUB_CFG_PATH}" << EOF
set timeout=5
set default="0"

EOF
echo "    - Main grub.cfg created."

# Temporary directory for all downloads and ISO mounting.
WORK_DIR=$(mktemp -d)
trap 'echo "==> Cleaning up temporary directory..."; rm -rf "${WORK_DIR}"' EXIT
cd "${WORK_DIR}"
echo "==> Working in temporary directory: ${WORK_DIR}"


# Loop through each requested architecture and set up its files.
for arch in ${ARCH_LIST}; do
    echo
    echo "================================================="
    echo "==> Processing architecture: ${arch}"
    echo "================================================="

    # --- Architecture-specific configuration ---
    GRUB_EFI_URL=""
    GRUB_EFI_FILENAME=""
    GRUB_PLATFORM_VAR=""

    case "${arch}" in
      "arm64")
        GRUB_EFI_URL="http://ports.ubuntu.com/pool/main/g/grub2-signed/grub-efi-arm64-signed_1.187.6+2.06-2ubuntu14.4_arm64.deb"
        GRUB_EFI_FILENAME="grubnetaa64.efi.signed"
        GRUB_PLATFORM_VAR="efi-arm64"
        ;;
      "amd64")
        GRUB_EFI_URL="http://archive.ubuntu.com/ubuntu/pool/main/g/grub2-signed/grub-efi-amd64-signed_1.187.6+2.06-2ubuntu14.4_amd64.deb"
        GRUB_EFI_FILENAME="grubnetx64.efi.signed"
        GRUB_PLATFORM_VAR="efi-x86_64"
        ;;
      *)
        echo "WARNING: Unsupported architecture '${arch}'. Skipping." >&2
        continue
        ;;
    esac
    
    # Create arch-specific directory structure.
    CASPER_DIR="${NETBOOT_ROOT}/casper-${arch}"
    echo "==> Creating directory: ${CASPER_DIR}"
    mkdir -p "${CASPER_DIR}"

    # 1. Download and verify the Ubuntu Server ISO for the current architecture.
    ISO_DOWNLOAD_DIR="${WORK_DIR}/iso-${arch}"
    mkdir -p "${ISO_DOWNLOAD_DIR}"
    /usr/local/bin/verify-ubuntu-image.sh "${UBUNTU_VERSION}" "${arch}" "${ISO_DOWNLOAD_DIR}"
    ISO_FILE_PATH=$(find "${ISO_DOWNLOAD_DIR}" -name "*.iso" -type f -print -quit)
    if [ -z "${ISO_FILE_PATH}" ]; then
        echo "FATAL: ISO file for ${arch} not found after download." >&2
        exit 1
    fi
    echo "==> ISO for ${arch} located at: ${ISO_FILE_PATH}"

    # 2. Mount the ISO to extract boot files.
    MOUNT_DIR="${WORK_DIR}/mnt-${arch}"
    mkdir -p "${MOUNT_DIR}"
    echo "==> Mounting ISO image for ${arch} at ${MOUNT_DIR}..."
    mount -o loop "${ISO_FILE_PATH}" "${MOUNT_DIR}"

    # 3. Copy kernel and initrd from the ISO to the arch-specific netboot directory.
    echo "==> Copying vmlinuz and initrd for ${arch}..."
    cp "${MOUNT_DIR}/casper/vmlinuz" "${CASPER_DIR}/vmlinuz"
    cp "${MOUNT_DIR}/casper/initrd" "${CASPER_DIR}/initrd"
    echo "    - vmlinuz and initrd placed in ${CASPER_DIR}/"

    # 4. Download and place the signed GRUB EFI bootloader.
    echo "==> Downloading signed GRUB EFI bootloader for ${arch}..."
    curl -fSL -o "grub-${arch}.deb" "${GRUB_EFI_URL}"
    # Extract the specific bootloader file from the .deb package.
    dpkg-deb -x "grub-${arch}.deb" "${WORK_DIR}/grub-pkg-${arch}"
    
    # The path inside the deb package is different for amd64 vs arm64
    if [ "${arch}" == "amd64" ]; then
        cp "${WORK_DIR}/grub-pkg-${arch}/usr/lib/grub/x86_64-efi-signed/${GRUB_EFI_FILENAME}" "${NETBOOT_ROOT}/${GRUB_EFI_FILENAME}"
    else # arm64
        cp "${WORK_DIR}/grub-pkg-${arch}/usr/lib/grub/arm64-efi-signed/${GRUB_EFI_FILENAME}" "${NETBOOT_ROOT}/${GRUB_EFI_FILENAME}"
    fi
    echo "    - ${GRUB_EFI_FILENAME} placed in ${NETBOOT_ROOT}/"

    # 5. Append the architecture-specific entry to the main grub.cfg file.
    echo "==> Appending ${arch} configuration to ${GRUB_CFG_PATH}..."
    cat >> "${GRUB_CFG_PATH}" << EOF

if [ "\${grub_platform}" == "${GRUB_PLATFORM_VAR}" ]; then
  menuentry "Ubuntu Server ${UBUNTU_VERSION} Autoinstall (${arch})" {
    linux /casper-${arch}/vmlinuz autoinstall "ds=nocloud-net;s=http://<HTTP_SERVER_IP_OR_DNS>/cloud-init/" ---
    initrd /casper-${arch}/initrd
  }
fi
EOF
    echo "    - ${arch} entry added successfully."

    # 6. Unmount the ISO.
    echo "==> Unmounting ISO image for ${arch}..."
    umount "${MOUNT_DIR}"
done

echo
echo "✅✅ Multi-arch netboot setup complete!"
echo "   TFTP Root: ${NETBOOT_ROOT}"
echo "   Next steps: Configure your DHCP server to provide the correct bootloader per architecture (e.g., grubnetaa64.efi.signed for arm64)."