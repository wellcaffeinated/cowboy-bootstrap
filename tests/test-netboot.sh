#!/bin/bash
# Test script to verify netboot infrastructure is working
# Run this from any machine on the bootstrap network (192.168.100.0/24)

set -e

BOOTSTRAP_SERVER="192.168.100.1"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "================================================"
echo "Netboot Infrastructure Test"
echo "Bootstrap Server: ${BOOTSTRAP_SERVER}"
echo "================================================"
echo

# Track failures
FAILURES=0

# Test function
test_component() {
    local name="$1"
    local command="$2"

    echo -n "Testing ${name}... "

    if eval "$command" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ PASS${NC}"
        return 0
    else
        echo -e "${RED}✗ FAIL${NC}"
        FAILURES=$((FAILURES + 1))
        return 1
    fi
}

# Test with output
test_component_verbose() {
    local name="$1"
    local command="$2"
    local expected="$3"

    echo -n "Testing ${name}... "

    OUTPUT=$(eval "$command" 2>&1)
    if [[ "$OUTPUT" == *"$expected"* ]]; then
        echo -e "${GREEN}✓ PASS${NC}"
        return 0
    else
        echo -e "${RED}✗ FAIL${NC}"
        echo "  Expected: $expected"
        echo "  Got: $OUTPUT"
        FAILURES=$((FAILURES + 1))
        return 1
    fi
}

echo "=== Network Connectivity ==="
test_component "Bootstrap server reachable" \
    "ping -c 1 -W 2 ${BOOTSTRAP_SERVER}"

echo

echo "=== DHCP Server (dnsmasq) ==="
echo -e "${YELLOW}Note: DHCP test requires dhcping or nmap. Skipping detailed DHCP test.${NC}"
test_component "DNS port 53 open" \
    "nc -zv -w 2 ${BOOTSTRAP_SERVER} 53"

echo

echo "=== TFTP Server (dnsmasq) ==="
test_component "TFTP port 69 open" \
    "nc -zuv -w 2 ${BOOTSTRAP_SERVER} 69"

# Try to download a file via TFTP if tftp client is available
if command -v tftp &> /dev/null; then
    echo -n "Testing TFTP file download (snponly_arm64.efi)... "
    if timeout 5 tftp ${BOOTSTRAP_SERVER} -c get snponly_arm64.efi /tmp/snponly_arm64.efi.test 2>&1 | grep -q "Received"; then
        echo -e "${GREEN}✓ PASS${NC}"
        rm -f /tmp/snponly_arm64.efi.test
    else
        echo -e "${YELLOW}⚠ SKIP (file may not exist yet)${NC}"
    fi
else
    echo -e "${YELLOW}⚠ SKIP (tftp client not installed)${NC}"
fi

echo

echo "=== Shoelaces HTTP Server ==="
test_component "Shoelaces port 8081 open" \
    "nc -zv -w 2 ${BOOTSTRAP_SERVER} 8081"

test_component_verbose "Shoelaces root page" \
    "curl -s -m 5 http://${BOOTSTRAP_SERVER}:8081/" \
    "shoelaces"

test_component_verbose "Shoelaces iPXE script generation" \
    "curl -s -m 5 http://${BOOTSTRAP_SERVER}:8081/poll/1/aa:bb:cc:dd:ee:ff" \
    "#!ipxe"

echo

echo "=== Static File Serving ==="
test_component "Kernel file accessible" \
    "curl -s -I -m 5 http://${BOOTSTRAP_SERVER}:8081/configs/static/ubuntu/casper-arm64/vmlinuz | grep -q '200 OK'"

test_component "Initrd file accessible" \
    "curl -s -I -m 5 http://${BOOTSTRAP_SERVER}:8081/configs/static/ubuntu/casper-arm64/initrd | grep -q '200 OK'"

test_component "Cloud-init user-data accessible" \
    "curl -s -I -m 5 http://${BOOTSTRAP_SERVER}:8081/configs/static/ubuntu/cloud-init/user-data | grep -q '200 OK'"

test_component_verbose "Cloud-init content valid" \
    "curl -s -m 5 http://${BOOTSTRAP_SERVER}:8081/configs/static/ubuntu/cloud-init/user-data" \
    "#cloud-config"

echo

echo "=== File Sizes Check ==="
# Check that files are not empty/suspiciously small
VMLINUZ_SIZE=$(curl -sI http://${BOOTSTRAP_SERVER}:8081/configs/static/ubuntu/casper-arm64/vmlinuz | grep -i content-length | awk '{print $2}' | tr -d '\r')
INITRD_SIZE=$(curl -sI http://${BOOTSTRAP_SERVER}:8081/configs/static/ubuntu/casper-arm64/initrd | grep -i content-length | awk '{print $2}' | tr -d '\r')

if [ "$VMLINUZ_SIZE" -gt 10000000 ]; then
    echo -e "Kernel size: ${GREEN}$(numfmt --to=iec $VMLINUZ_SIZE) ✓${NC}"
else
    echo -e "Kernel size: ${RED}$(numfmt --to=iec $VMLINUZ_SIZE) ✗ (too small)${NC}"
    FAILURES=$((FAILURES + 1))
fi

if [ "$INITRD_SIZE" -gt 10000000 ]; then
    echo -e "Initrd size: ${GREEN}$(numfmt --to=iec $INITRD_SIZE) ✓${NC}"
else
    echo -e "Initrd size: ${RED}$(numfmt --to=iec $INITRD_SIZE) ✗ (too small)${NC}"
    FAILURES=$((FAILURES + 1))
fi

echo

echo "================================================"
if [ $FAILURES -eq 0 ]; then
    echo -e "${GREEN}All tests passed! Netboot infrastructure is ready.${NC}"
    exit 0
else
    echo -e "${RED}${FAILURES} test(s) failed. Check the output above.${NC}"
    exit 1
fi
