#!/bin/bash
# Tests for lib/net.sh — static-IP derivation. No root, no network changes.
set -u
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0 FAIL=0
_assert() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "  ✓ $1"; else FAIL=$((FAIL+1)); echo "  ✗ $1 (expected '$3', got '$2')"; fi; }
source "$REPO_DIR/lib/net.sh"

echo "==> host number inside the router's subnet"
_assert "/24 on 192.168.50.x"      "$(net_host_in_subnet 192.168.50.185 24 69)" "192.168.50.69"
_assert "/24 on 10.0.0.x"          "$(net_host_in_subnet 10.0.0.23 24 69)"     "10.0.0.69"
_assert "/16 keeps network base"   "$(net_host_in_subnet 172.16.9.4 16 69)"    "172.16.0.69"
_assert "/23 uses the lower half"  "$(net_host_in_subnet 192.168.51.7 23 69)"  "192.168.50.69"
_assert "/26 host too big fails"   "$(net_host_in_subnet 192.168.1.130 26 69 || echo fail)" "fail"
_assert "broadcast rejected"       "$(net_host_in_subnet 192.168.1.5 24 255 || echo fail)"  "fail"
_assert "network address rejected" "$(net_host_in_subnet 192.168.1.5 24 0 || echo fail)"    "fail"

echo "==> default route selection"
routes='default via 192.168.50.1 dev wlo1 proto dhcp src 192.168.50.245 metric 600
default via 192.168.50.1 dev enp42s0 proto dhcp src 192.168.50.185 metric 100'
_assert "lowest metric wins" "$(echo "$routes" | net_pick_default_route)" "enp42s0 192.168.50.1"
_assert "no metric = 0"      "$(printf 'default via 10.1.1.1 dev eth0\ndefault via 10.2.2.1 dev wl0 metric 50\n' | net_pick_default_route)" "eth0 10.1.1.1"

echo "==> no hardcoded 192.168.1.x left in system_config.sh"
if grep -qE '192\.168\.1\.(69|1)\b' "$REPO_DIR/system_config.sh"; then _assert "no hardcoded IP" yes no; else _assert "no hardcoded IP" ok ok; fi

echo "----------------------------------------"
echo "passed: $PASS"; echo "failed: $FAIL"
[ "$FAIL" -eq 0 ]
