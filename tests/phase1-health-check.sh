#!/bin/bash
# Phase 1 Health Check Script
# Tests all Phase 1 bootstrap components

set -uo pipefail

# Set Vault address (HTTP not HTTPS since tls_disable=1)
export VAULT_ADDR='http://127.0.0.1:8200'

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

FAILED_TESTS=0
PASSED_TESTS=0

# Helper functions
pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((PASSED_TESTS++))
}

fail() {
    echo -e "${RED}✗${NC} $1"
    ((FAILED_TESTS++))
}

warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

section() {
    echo ""
    echo "============================================"
    echo "$1"
    echo "============================================"
}

# Check if running as root or with sudo access
if [ "$EUID" -ne 0 ]; then
    warn "Not running as root. Some checks may require sudo."
fi

# ============================================
# SERVICE STATUS CHECKS
# ============================================
section "1. Service Status"

# Check if services are actually running (process-based, more reliable than systemctl)
for service in consul vault nomad; do
    if pgrep -x "$service" >/dev/null; then
        pass "$service is running"
    else
        # Double-check with systemctl
        if systemctl is-active --quiet $service 2>/dev/null; then
            warn "$service systemctl says active, but process not found"
        else
            fail "$service is NOT running"
        fi
    fi
done

# ============================================
# CONSUL CHECKS
# ============================================
section "2. Consul Checks"

# Consul members
if consul members &>/dev/null; then
    MEMBER_COUNT=$(consul members | grep -c alive)
    if [ "$MEMBER_COUNT" -ge 1 ]; then
        pass "Consul has $MEMBER_COUNT alive member(s)"
    else
        fail "Consul has no alive members"
    fi
else
    fail "Unable to query consul members"
fi

# Consul services
if consul catalog services &>/dev/null; then
    SERVICES=$(consul catalog services)

    if echo "$SERVICES" | grep -q "consul"; then
        pass "Consul service registered"
    else
        fail "Consul service not registered"
    fi

    if echo "$SERVICES" | grep -q "vault"; then
        pass "Vault service registered in Consul"
    else
        fail "Vault service not registered in Consul"
    fi
else
    fail "Unable to query consul catalog"
fi

# Consul Connect enabled
if consul connect ca get-config &>/dev/null; then
    pass "Consul Connect CA configured"
else
    fail "Consul Connect CA not configured"
fi

# Consul UI accessible
if curl -sf http://localhost:8500/ui/ >/dev/null; then
    pass "Consul UI accessible on port 8500"
else
    fail "Consul UI not accessible"
fi

# Consul gRPC port (for Connect)
if netstat -tuln 2>/dev/null | grep -q ":8502" || ss -tuln 2>/dev/null | grep -q ":8502"; then
    pass "Consul gRPC port 8502 listening (for Connect)"
else
    fail "Consul gRPC port 8502 not listening"
fi

# ============================================
# VAULT CHECKS
# ============================================
section "3. Vault Checks"

# Vault status - vault status returns non-zero when sealed/uninitialized, so ignore exit code
VAULT_STATUS=$(vault status -format=json 2>/dev/null || true)

if [ -n "$VAULT_STATUS" ] && echo "$VAULT_STATUS" | grep -q "initialized"; then
    pass "Vault is responding"

    if echo "$VAULT_STATUS" | grep -q '"initialized":false'; then
        warn "Vault is not yet initialized (expected on first run)"
    elif echo "$VAULT_STATUS" | grep -q '"sealed":true'; then
        warn "Vault is sealed (expected before unsealing)"
    elif echo "$VAULT_STATUS" | grep -q '"sealed":false'; then
        pass "Vault is unsealed and operational"
    fi
else
    fail "Vault is not responding"
fi

# Vault HTTP API - check if we get any response (even error codes are OK)
if curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8200/v1/sys/health | grep -qE "^(200|429|472|473|501|503)$"; then
    pass "Vault HTTP API accessible on localhost"
else
    fail "Vault HTTP API not accessible"
fi

# Vault Connect sidecar
if consul catalog service vault 2>/dev/null | grep -q "sidecar-proxy"; then
    pass "Vault Connect sidecar proxy registered"
else
    warn "Vault Connect sidecar proxy not found (may not be started yet)"
fi

# ============================================
# NOMAD CHECKS
# ============================================
section "4. Nomad Checks"

# Nomad server members
if nomad server members &>/dev/null; then
    SERVER_COUNT=$(nomad server members | grep -c alive)
    if [ "$SERVER_COUNT" -ge 1 ]; then
        pass "Nomad has $SERVER_COUNT alive server(s)"
    else
        fail "Nomad has no alive servers"
    fi
else
    fail "Unable to query nomad server members"
fi

# Nomad nodes
if nomad node status &>/dev/null; then
    NODE_COUNT=$(nomad node status | grep -c ready)
    if [ "$NODE_COUNT" -ge 1 ]; then
        pass "Nomad has $NODE_COUNT ready node(s)"
    else
        fail "Nomad has no ready nodes"
    fi
else
    fail "Unable to query nomad nodes"
fi

# Nomad UI accessible
if curl -sf http://localhost:4646/ui/ >/dev/null; then
    pass "Nomad UI accessible on port 4646"
else
    fail "Nomad UI not accessible"
fi

# Nomad-Vault integration
if journalctl -u nomad -n 50 --no-pager 2>/dev/null | grep -qi "vault"; then
    if journalctl -u nomad -n 50 --no-pager 2>/dev/null | grep -qi "vault.*error"; then
        warn "Nomad logs show Vault errors (check: journalctl -u nomad)"
    else
        pass "Nomad-Vault integration configured (check logs for details)"
    fi
else
    warn "No Vault mentions in recent Nomad logs"
fi

# ============================================
# NETWORK CHECKS
# ============================================
section "5. Network Configuration"

# Bootstrap LAN interface - auto-detect by IP address
BOOTSTRAP_IF=$(ip -4 addr show | grep -B2 "192.168.100.1" | head -1 | awk '{print $2}' | tr -d ':')
if [ -n "$BOOTSTRAP_IF" ]; then
    pass "Bootstrap LAN configured on $BOOTSTRAP_IF with 192.168.100.1"
else
    # Try reading from netplan config
    if [ -f /etc/netplan/90-bootstrap-lan.yaml ]; then
        CONFIGURED_IF=$(grep -A1 "ethernets:" /etc/netplan/90-bootstrap-lan.yaml | tail -1 | tr -d ' :')
        if [ -n "$CONFIGURED_IF" ]; then
            warn "Bootstrap LAN configured for $CONFIGURED_IF but not applied (run: sudo netplan apply)"
        else
            fail "Bootstrap LAN not configured"
        fi
    else
        fail "Bootstrap LAN not configured (netplan file missing)"
    fi
fi

# IP forwarding
IP_FORWARD=$(sysctl -n net.ipv4.ip_forward 2>/dev/null)
if [ "$IP_FORWARD" = "1" ]; then
    pass "IP forwarding enabled"
else
    fail "IP forwarding disabled"
fi

# UFW status
if command -v ufw &>/dev/null; then
    if ufw status | grep -q "Status: active"; then
        pass "UFW is active"

        # Check SSH allowed
        if ufw status | grep -q "22/tcp.*ALLOW"; then
            pass "SSH allowed through UFW"
        else
            fail "SSH NOT allowed through UFW (CRITICAL!)"
        fi

        # Check bootstrap LAN allowed
        if ufw status | grep -q "192.168.100.0/24.*ALLOW"; then
            pass "Bootstrap LAN traffic allowed"
        else
            warn "Bootstrap LAN traffic rule not found"
        fi
    else
        warn "UFW is installed but not active"
    fi
else
    warn "UFW not installed"
fi

# NAT rule
if iptables -t nat -L -n 2>/dev/null | grep -q "MASQUERADE"; then
    pass "NAT MASQUERADE rule present"
else
    fail "NAT MASQUERADE rule not found"
fi

# ============================================
# INTEGRATION CHECKS
# ============================================
section "6. Integration Tests"

# Docker available
if docker ps &>/dev/null; then
    pass "Docker is accessible"
else
    fail "Docker is not accessible"
fi

# Consul KV test (for Vault storage)
TEST_KEY="test/bootstrap-check-$$"
if consul kv put "$TEST_KEY" "test-value" &>/dev/null; then
    if consul kv get "$TEST_KEY" &>/dev/null; then
        pass "Consul KV storage working (Vault backend)"
        consul kv delete "$TEST_KEY" &>/dev/null
    else
        fail "Consul KV read failed"
    fi
else
    fail "Consul KV write failed"
fi

# ============================================
# SUMMARY
# ============================================
section "Test Summary"

TOTAL_TESTS=$((PASSED_TESTS + FAILED_TESTS))
echo "Passed: $PASSED_TESTS / $TOTAL_TESTS"
echo "Failed: $FAILED_TESTS / $TOTAL_TESTS"

if [ $FAILED_TESTS -eq 0 ]; then
    echo -e "\n${GREEN}All critical tests passed!${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Initialize Vault: vault operator init"
    echo "  2. Unseal Vault: vault operator unseal (3 times)"
    echo "  3. View UIs:"
    echo "     - Consul: http://$(hostname -I | awk '{print $1}'):8500"
    echo "     - Vault:  http://$(hostname -I | awk '{print $1}'):8200"
    echo "     - Nomad:  http://$(hostname -I | awk '{print $1}'):4646"
    exit 0
else
    echo -e "\n${RED}Some tests failed. Review output above.${NC}"
    exit 1
fi
