# Jtech server monitoring — on-call runbook

## Access the instance (no SSH key needed)
```bash
aws ssm start-session --target INSTANCE_ID --region us-east-1
```
Instance ID: get from `terraform output instance_id`
Dashboard: get URL from `terraform output cloudwatch_dashboard_url`

---

## Alarm: CPU high (> 80% for 10 minutes)
**Likely causes:** runaway process, traffic spike, scheduled job

**Response:**
```bash
# Connect via SSM
aws ssm start-session --target INSTANCE_ID --region us-east-1

# Find top CPU consumers
top -b -n 1 | head -20

# Check recent cron jobs
sudo grep CRON /var/log/cron | tail -20

# If a runaway process: get its PID from top, then:
sudo kill -15 PID   # graceful termination first
sudo kill -9 PID    # force kill only if -15 doesn't work
```

---

## Alarm: Memory high (> 85% for 10 minutes)
**Likely causes:** memory leak, too many processes, insufficient instance size

**Response:**
```bash
# Find top memory consumers
ps aux --sort=-%mem | head -15

# Check for zombie processes
ps aux | grep Z

# Check swap usage
free -h

# If instance genuinely needs more memory, change instance_type
# in terraform.tfvars and run terraform apply — zero manual steps
```

---

## Alarm: Disk high (> 90%)
**Likely causes:** log accumulation, large upload, runaway log file

**Response:**
```bash
# Find what's consuming disk
df -h /
du -sh /var/* | sort -rh | head -10
du -sh /tmp/* | sort -rh | head -10

# Find large log files
find /var/log -size +100M -type f

# Safe cleanup — remove rotated logs older than 7 days
sudo find /var/log -name "*.gz" -mtime +7 -delete
```

---

## Alarm: Status check failed
**Likely causes:** hardware failure, kernel panic, corrupted filesystem

**Response:**
1. Attempt SSM session — if it connects, the OS is alive
2. Check system logs in CloudWatch: `/jtech/ec2/auth`
3. If SSM fails: stop and start the instance via AWS console
   (stop+start migrates to new hardware, reboot does not)
4. If repeated: take AMI snapshot, terminate, launch new instance

---

## Security: Failed SSH attempts spike
**Monitoring:** CloudWatch Logs Insights — `/jtech/ec2/auth`
```
fields @timestamp, @message
| filter @message like /Failed password|Invalid user/
| stats count() as attempts by bin(1h)
| sort @timestamp desc
```

**fail2ban status:**
```bash
sudo fail2ban-client status sshd     # see banned IPs
sudo fail2ban-client set sshd unbanip IP   # manual unban
sudo fail2ban-client status          # overall status
```