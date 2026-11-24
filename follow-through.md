# Follow-Through Guide: Linux Server Hardening & Automated Monitoring

## Problem Context

> *A startup has an EC2 fleet with no visibility into CPU spikes or failed SSH attempts — the security team is nervous.*

This repository addresses that by deploying a hardened Amazon Linux 2023 EC2 instance with automated CloudWatch metrics, log shipping, and SNS email alerting, while removing inbound SSH exposure via AWS SSM Session Manager.

---

## How the Code Maps to the Problem

| Problem | Implementation |
|---|---|
| **No visibility into CPU spikes** | 1-minute detailed monitoring, `CPUUtilization` alarm (`> 80%` for 2 × 5 min), and dashboard widget |
| **No visibility into failed SSH attempts** | CloudWatch agent ships `/var/log/secure` → `/jtech/ec2/auth` and `/var/log/fail2ban.log` → `/jtech/ec2/fail2ban`; Logs Insights dashboard widget + `SSHAuthFailures` metric filter & alarm (`>= 5` in 5 min) |
| **Security team nervous about SSH & host posture** | Zero inbound security group rules, SSM Session Manager access, IMDSv2 enforced (`http_tokens = "required"`), encrypted `gp3` root volume, and first-boot `harden.sh` (`fail2ban`, `sysctl`, `dnf-automatic`) |
| **Silent resource exhaustion** | Memory (`> 85%`), Disk (`> 90%`), and `StatusCheckFailed` alarms wired to SNS email alerts |

---

## Step-by-Step Follow-Through

### 1. Deploy the Infrastructure

```powershell
cd terraform
terraform init
terraform plan
terraform apply
```

Note the outputs (`instance_id`, `ssm_connect_command`, `cloudwatch_dashboard_url`, `sns_topic_arn`) from [`terraform/output.tf`](terraform/output.tf).

### 2. Confirm the SNS Email Subscription

1. Check the inbox for `alert_email` (set in `terraform/terraform.tfvars`).
2. Click **Confirm subscription** in the AWS Notifications email so alarm emails are delivered.

### 3. Connect Without SSH (SSM Session Manager)

Wait 2–3 minutes for the SSM agent to register, then run the `ssm_connect_command` output:

```powershell
aws ssm start-session --target <instance_id> --region <aws_region>
```

### 4. Verify Hardening & Monitoring on the Instance

```bash
sudo cat /var/log/harden.log
sudo systemctl status fail2ban amazon-cloudwatch-agent
```

Optionally run [`scripts/audit.sh`](scripts/audit.sh) on the instance to verify all hardening controls.

### 5. Open the CloudWatch Dashboard

Use `cloudwatch_dashboard_url` from Terraform outputs to monitor:
- **CPU Utilisation** (80% threshold)
- **Memory Used %** (`Jtech/EC2`, 85% threshold)
- **Disk Used %** (`Jtech/EC2`, 90% threshold)
- **Recent auth failures** (Logs Insights query on `/jtech/ec2/auth`)

For alarm response procedures, see the on-call runbook in [`doc.md`](doc.md).
