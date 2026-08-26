#!/bin/bash
# Jtech EC2 hardening script — runs once on first boot via user_data
# Every step is logged to /var/log/harden.log for audit purposes
set -euo pipefail

LOG_FILE="/var/log/harden.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "============================================"
echo "Jtech Server Hardening — $(date -u)"
echo "Instance: $(curl -s -H 'X-aws-ec2-metadata-token-ttl-seconds: 21600' \
  -X PUT http://169.254.169.254/latest/api/token | \
  xargs -I{} curl -s -H 'X-aws-ec2-metadata-token: {}' \
  http://169.254.169.254/latest/meta-data/instance-id)"
echo "============================================"

# ── 1. SYSTEM UPDATE ────────────────────────────────────────────────
echo "[1/6] Updating all packages..."
dnf update -y
dnf install -y fail2ban cronie audit

# ── 2. SSH HARDENING ─────────────────────────────────────────────────
echo "[2/6] Hardening SSH configuration..."
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.original

# Write a hardened sshd_config — override the entire file
cat > /etc/ssh/sshd_config << 'SSHEOF'
Protocol 2
Port 22
HostKey /etc/ssh/ssh_host_ed25519_key
HostKey /etc/ssh/ssh_host_rsa_key

# Authentication — keys only, no passwords, no root
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
PermitEmptyPasswords no
ChallengeResponseAuthentication no

# Limit exposure
MaxAuthTries 3
MaxSessions 3
LoginGraceTime 30
ClientAliveInterval 300
ClientAliveCountMax 2
X11Forwarding no
AllowTcpForwarding no
Banner /etc/ssh/banner

# Log everything
SyslogFacility AUTH
LogLevel VERBOSE
SSHEOF

# Legal warning banner shown before any login attempt
cat > /etc/ssh/banner << 'BANEOF'
*******************************************************************
  AUTHORISED ACCESS ONLY — Jtech Solutions
  All sessions are monitored, logged, and subject to audit.
  Disconnect immediately if you are not an authorised user.
*******************************************************************
BANEOF

systemctl restart sshd
echo "SSH hardened: root login disabled, password auth disabled"

# ── 3. FAIL2BAN ──────────────────────────────────────────────────────
echo "[3/6] Configuring fail2ban..."
cat > /etc/fail2ban/jail.local << 'F2BEOF'
[DEFAULT]
# Ban IP for 1 hour after 3 failed attempts within 10 minutes
bantime  = 3600
findtime = 600
maxretry = 3
backend  = systemd

[sshd]
enabled  = true
port     = ssh
logpath  = %(sshd_log)s
F2BEOF

systemctl enable --now fail2ban
echo "fail2ban active: 3 failed attempts = 1 hour ban"

# ── 4. KERNEL HARDENING (sysctl) ─────────────────────────────────────
echo "[4/6] Applying kernel security parameters..."
cat > /etc/sysctl.d/99-jtech-hardening.conf << 'SYSCTLEOF'
# Disable IP forwarding — this is not a router
net.ipv4.ip_forward = 0
net.ipv6.conf.all.forwarding = 0

# SYN flood protection
net.ipv4.tcp_syncookies = 1

# Ignore ICMP broadcast requests (smurf attack mitigation)
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Disable source routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0

# Log suspicious packets (martians)
net.ipv4.conf.all.log_martians = 1

# Disable ICMP redirects
net.ipv4.conf.all.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
SYSCTLEOF

sysctl --system
echo "Kernel hardening applied"

# ── 5. AUTOMATIC SECURITY UPDATES ────────────────────────────────────
echo "[5/6] Enabling automatic security updates..."
dnf install -y dnf-automatic

# Configure to download AND apply security updates automatically
sed -i 's/^apply_updates = no/apply_updates = yes/' \
  /etc/dnf/automatic.conf
sed -i 's/^upgrade_type = default/upgrade_type = security/' \
  /etc/dnf/automatic.conf

systemctl enable --now dnf-automatic-install.timer
echo "Automatic security updates enabled"

# ── 6. CLOUDWATCH AGENT ──────────────────────────────────────────────
echo "[6/6] Installing CloudWatch agent..."
dnf install -y amazon-cloudwatch-agent

# Write the agent configuration — sends memory, disk, and logs
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'CWEOF'
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "cwagent"
  },
  "metrics": {
    "namespace": "Jtech/EC2",
    "metrics_collected": {
      "mem": {
        "measurement": ["mem_used_percent"],
        "metrics_collection_interval": 60
      },
      "disk": {
        "measurement": ["disk_used_percent"],
        "resources": ["/"],
        "metrics_collection_interval": 60
      }
    },
    "append_dimensions": {
      "InstanceId": "${aws:InstanceId}",
      "Environment": "prod"
    }
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/harden.log",
            "log_group_name": "/jtech/ec2/harden",
            "log_stream_name": "{instance_id}",
            "retention_in_days": 90
          },
          {
            "file_path": "/var/log/secure",
            "log_group_name": "/jtech/ec2/auth",
            "log_stream_name": "{instance_id}",
            "retention_in_days": 90
          },
          {
            "file_path": "/var/log/fail2ban.log",
            "log_group_name": "/jtech/ec2/fail2ban",
            "log_stream_name": "{instance_id}",
            "retention_in_days": 90
          }
        ]
      }
    }
  }
}
CWEOF

# Start agent with our config
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
  -s

systemctl enable amazon-cloudwatch-agent
echo "CloudWatch agent running — metrics and logs flowing"

# ── 7. SECURITY AUDIT SCRIPT ─────────────────────────────────────────
echo "[7/7] Placing security audit script..."
cat > /home/ssm-user/audit.sh << 'AUDITEOF'
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
AUDITEOF
chown ssm-user:ssm-user /home/ssm-user/audit.sh
chmod +x /home/ssm-user/audit.sh

echo "============================================"
echo "Hardening complete: $(date -u)"
echo "Log: $LOG_FILE"
echo "============================================"