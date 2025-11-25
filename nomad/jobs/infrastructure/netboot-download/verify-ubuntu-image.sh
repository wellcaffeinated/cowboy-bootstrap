#!/usr/bin/env bash
set -euo pipefail

# End-to-end script to download an Ubuntu Server ISO, verify its integrity
# and authenticity, and place it in a specified output directory.

# --- Configuration ---

# Ubuntu's official release signing keys. These are long-lived and can be
# verified from multiple sources.
# Find them at: https://wiki.ubuntu.com/SecurityTeam/FAQ
declare -a UBUNTU_GPG_KEYS=(
    "C598 6B4F 1257 FFA8 6632  CBA7 4618 1433 FBB7 5451"
    "8439 38DF 228D 22F7 B374  2BC0 D94A A3F0 EFE2 1092"
)
KEYSERVER="keyserver.ubuntu.com"

# --- Functions ---

usage() {
    cat <<EOF
Usage: $0 <version> <arch> <output_dir>

Downloads and verifies a Ubuntu Server ISO.

Arguments:
  version     The Ubuntu version to download (e.g., "22.04.4", "24.04").
  arch        The architecture (e.g., "amd64", "arm64").
  output_dir  The directory to place the verified ISO in.

Example:
  $0 24.04 amd64 /var/www/html/netboot/ubuntu
EOF
    exit 1
}

# --- Argument Validation ---

if [ "$#" -ne 3 ]; then
    usage
fi

UBUNTU_VERSION="$1"
ARCH="$2"
OUTPUT_DIR="$3"
ISO_FILENAME="ubuntu-${UBUNTU_VERSION}-live-server-${ARCH}.iso"
BASE_URL="https://releases.ubuntu.com/${UBUNTU_VERSION}"

# --- Execution ---

# Create a temporary directory for all downloads and work.
# This ensures that we don't leave partial artifacts in the output directory.
# The 'trap' command ensures this directory is cleaned up on script exit,
# whether it succeeds or fails.
WORK_DIR=$(mktemp -d)
trap 'echo "==> Cleaning up temporary directory..."; rm -rf "${WORK_DIR}"' EXIT

cd "${WORK_DIR}"
echo "==> Working in temporary directory: ${WORK_DIR}"

# Create an isolated, temporary GPG home to not interfere with the user's keys.
export GNUPGHOME
GNUPGHOME=$(mktemp -d)
echo "==> Using temporary GPG home: ${GNUPGHOME}"

declare -a verified_fingerprints=()

# Process each key defined in UBUNTU_GPG_KEYS.
for key in "${UBUNTU_GPG_KEYS[@]}"; do
    # Normalize the key, removing any spaces, to handle pasted fingerprints.
    normalized_key="${key// /}"

    echo "==> Verifying authenticity of GPG key: ${key}"

    # 1. Fetch key from the primary server (Ubuntu's keyserver) into our main GPG home.
    echo "  - Fetching key from primary server (${KEYSERVER})..."
    if ! gpg --quiet --keyserver "${KEYSERVER}" --recv-keys "${normalized_key}"; then
        echo "FATAL: Could not retrieve key ${key} from primary server ${KEYSERVER}." >&2
        exit 1
    fi

    # Sanity check: Verify the key is associated with the expected Ubuntu identity.
    # This protects against accidentally hardcoding a completely wrong key ID.
    echo "  - Sanity checking key's user ID..."
    if ! gpg --list-keys --with-colons "${normalized_key}" | grep -q 'cdimage@ubuntu.com'; then
        echo "FATAL: Key ID ${key} is NOT associated with the expected 'cdimage@ubuntu.com' user ID." >&2
        echo "This may mean the wrong key ID was hardcoded in the script. Aborting." >&2
        echo "The key ID ${key} belongs to:" >&2
        gpg --list-keys "${normalized_key}"
        exit 1
    fi
    
    # 2. Get its fingerprint to use as the reference.
    reference_fingerprint=$(gpg --fingerprint --with-colons "${normalized_key}" | awk -F: '/^fpr:/ {print $10}')
    if [ -z "${reference_fingerprint}" ]; then
        echo "FATAL: Could not parse fingerprint for key ${key} from ${KEYSERVER}." >&2
        exit 1
    fi
    echo "  - Reference fingerprint: ${reference_fingerprint}"

    verified_fingerprints+=("${reference_fingerprint}")
done

# If we get here, all keys are verified. Now, let's build and import a trust database.
echo "==> All GPG keys have been cross-verified. Building trust database..."
trust_db_file="${WORK_DIR}/ownertrust.txt"
for fingerprint in "${verified_fingerprints[@]}"; do
    # Assign ultimate trust. The format is "FINGERPRINT:LEVEL:", where 6 is ultimate.
    echo "${fingerprint}:6:" >> "${trust_db_file}"
done

gpg --import-ownertrust < "${trust_db_file}"
echo "==> GPG trust database has been updated for this session."

echo "==> Downloading ISO checksums and signature..."
curl -fSL -O "${BASE_URL}/SHA256SUMS"
curl -fSL -O "${BASE_URL}/SHA256SUMS.gpg"

echo "==> Verifying GPG signature of checksums file..."
gpg --verify SHA256SUMS.gpg SHA256SUMS
echo "==> GPG signature is valid."

echo "==> Downloading Ubuntu Server ISO: ${ISO_FILENAME}..."
# Use --progress-bar to show progress without excessive noise.
curl -fSL --progress-bar -O "${BASE_URL}/${ISO_FILENAME}"

echo "==> Verifying SHA256 checksum of the ISO..."
# Grep the specific ISO's hash from the file and check it.
# The '-' tells sha256sum to read the expected hash from stdin.
grep "${ISO_FILENAME}" SHA256SUMS | sha256sum --check -
echo "==> SHA256 checksum is valid."

# If we've reached here, all checks have passed.
echo "==> Verification successful. Moving ISO to output directory."
mkdir -p "${OUTPUT_DIR}"
mv "${WORK_DIR}/${ISO_FILENAME}" "${OUTPUT_DIR}/"

echo "✅ Success! ${ISO_FILENAME} is ready in ${OUTPUT_DIR}"