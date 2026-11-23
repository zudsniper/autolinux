#!/bin/bash
# Tests for lib/net.sh — static-IP derivation. No root, no network changes.
set -u
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0 FAIL=0
_assert() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "  ✓ $1"; else FAIL=$((FAIL+1)); echo "  ✗ $1 (expected '$3', got '$2')"; fi; }
source "$REPO_DIR/lib/net.sh"

echo "==> subnet math"
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

echo "==> IPv4 validation"
for ok in 192.168.50.20 10.0.0.1 255.255.255.0; do
    if net_valid_ip "$ok"; then _assert "valid $ok" ok ok; else _assert "valid $ok" bad ok; fi
done
for bad in 256.1.1.1 1.2.3 1.2.3.4.5 abc 1.2.3.-4 ""; do
    if net_valid_ip "$bad"; then _assert "invalid '$bad'" accepted rejected; else _assert "invalid '$bad'" rejected rejected; fi
done

echo "==> system_config.sh CLI (dry-run, no root)"
SC="$REPO_DIR/system_config.sh"
out="$(NO_COLOR=1 "$SC" --dry-run 2>&1)"
case "$out" in *"Static IP"*skipped*) _assert "no flags → static IP skipped" ok ok ;; *) _assert "no flags → static IP skipped" "$out" ok ;; esac
case "$out" in *"Wake-on-LAN"*skipped*) _assert "no flags → WoL skipped" ok ok ;; *) _assert "no flags → WoL skipped" missing ok ;; esac
case "$out" in *nmcli*|*netplan\ apply*) _assert "no flags → no network commands" ran none ;; *) _assert "no flags → no network commands" none none ;; esac
"$SC" --static-ip 300.1.1.1 --dry-run >/dev/null 2>&1; _assert "bad --static-ip rejected" "$?" 1
"$SC" --dns 1.1.1.1 --dry-run >/dev/null 2>&1;         _assert "--dns without --static-ip rejected" "$?" 1
"$SC" --static-ip >/dev/null 2>&1;                     _assert "--static-ip needs a value" "$?" 1
"$SC" --bogus >/dev/null 2>&1;                         _assert "unknown flag rejected" "$?" 2

echo "==> no hardcoded 192.168.1.x left in system_config.sh"
if grep -qE '192\.168\.1\.(69|1)\b' "$REPO_DIR/system_config.sh"; then _assert "no hardcoded IP" yes no; else _assert "no hardcoded IP" ok ok; fi

echo "----------------------------------------"
echo "passed: $PASS"; echo "failed: $FAIL"
[ "$FAIL" -eq 0 ]
