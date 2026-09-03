#!/bin/bash
# jtech weekly security audit — run via SSM Run Command or cron
set -euo pipefail

PASS=0; FAIL=0; WARN=0

pass() { echo "[PASS] $1"; ((PASS++)); }
fail() { echo "[FAIL] $1"; ((FAIL++)); }
warn() { echo "[WARN] $1"; ((WARN++)); }

echo "=== jtech Security Audit — $(date -u) ==="

# SSH hardening checks
grep -q "^PermitRootLogin no" /etc/ssh/sshd_config \
  && pass "Root SSH login disabled" \
  || fail "Root SSH login NOT disabled"

grep -q "^PasswordAuthentication no" /etc/ssh/sshd_config \
  && pass "Password auth disabled (keys only)" \
  || fail "Password auth is ENABLED — keys only required"

grep -q "^MaxAuthTries 3" /etc/ssh/sshd_config \
  && pass "MaxAuthTries set to 3" \
  || warn "MaxAuthTries not set to 3"

# Service health checks
systemctl is-active --quiet fail2ban \
  && pass "fail2ban is running" \
  || fail "fail2ban is NOT running"

systemctl is-active --quiet amazon-cloudwatch-agent \
  && pass "CloudWatch agent is running" \
  || fail "CloudWatch agent is NOT running"

systemctl is-active --quiet dnf-automatic-install.timer \
  && pass "Auto security updates enabled" \
  || warn "Auto security updates not enabled"

# Check for unowned files (common after manual installs)
UNOWNED=$(find / -xdev \( -nouser -o -nogroup \) 2>/dev/null | wc -l)
[ "$UNOWNED" -eq 0 ] \
  && pass "No unowned files found" \
  || warn "$UNOWNED unowned file(s) found — investigate"

# Check world-writable files outside /tmp
WORLDWRITE=$(find / -xdev -not -path '/tmp/*' -perm -0002 -type f 2>/dev/null | wc -l)
[ "$WORLDWRITE" -eq 0 ] \
  && pass "No world-writable files found" \
  || warn "$WORLDWRITE world-writable file(s) found"

echo ""
echo "=== Audit Summary ==="
echo "PASS: $PASS | FAIL: $FAIL | WARN: $WARN"
[ "$FAIL" -gt 0 ] && echo "ACTION REQUIRED: $FAIL critical check(s) failed" && exit 1
echo "Audit complete: $(date -u)"