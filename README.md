# Jtech Server Monitoring — EC2 Hardening & CloudWatch Observability

[![Terraform](https://img.shields.io/github/actions/workflow/status/sensi012/Linux-server-hardening-automated-monitoring/terraform.yml?label=terraform&logo=terraform&logoColor=white)](https://github.com/sensi012/Linux-server-hardening-automated-monitoring/actions/workflows/terraform.yml)
[![IaC: Terraform](https://img.shields.io/badge/IaC-Terraform_1.15-7B42BC?logo=terraform)](https://www.terraform.io/)
[![Cloud: AWS](https://img.shields.io/badge/Cloud-AWS-FF9900?logo=amazon-aws&logoColor=white)](https://aws.amazon.com/)
[![Access: SSM](https://img.shields.io/badge/Access-SSM_Session_Manager-1D9E75)](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html)

> **Scenario:** Jtech Solutions ran EC2 instances with port 22 open to the internet, password authentication enabled, no memory or disk monitoring, and zero alerting. One engineer's leaked SSH key away from a breach. This project replaces that setup with hardened, fully observed infrastructure — zero open inbound ports, automated fail2ban, IMDSv2 enforced, and four production alarms watching CPU, memory, disk, and instance health.

---

## What this project demonstrates

| Skill area | Implementation |
|---|---|
| Infrastructure as Code | All AWS resources provisioned with Terraform — EC2, IAM, SNS, CloudWatch |
| OS hardening | SSH lockdown, fail2ban, kernel sysctl parameters, automatic security patching |
| Observability | CloudWatch agent for memory and disk metrics absent from AWS default monitoring |
| Alerting | Four production alarms with SNS email notification and alarm-clear notifications |
| Secure access | SSM Session Manager — zero open ports, IAM-controlled, full session audit trail |
| Security defaults | IMDSv2 enforced, encrypted EBS, least-privilege IAM, no hardcoded AMI IDs |
| Operations | On-call runbook for all four alarm scenarios |

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│  Developer / on-call engineer access                                 │
│                                                                      │
│  aws ssm start-session --target i-xxxxxxxxx                          │
│        │                                                             │
│        ▼                                                             │
│  ┌─────────────┐   IAM auth     ┌──────────────────┐               │
│  │  AWS CLI +  │ ─────────────► │  Systems Manager  │               │
│  │  SSM Plugin │ ◄── shell ──── │  (HTTPS port 443) │               │
│  └─────────────┘                └──────────────────┘               │
│                                          │                           │
│                              ┌───────────▼──────────┐               │
│                              │   EC2 instance        │               │
│                              │   Amazon Linux 2023   │               │
│                              │   ┌────────────────┐  │               │
│                              │   │ SSM agent      │  │               │
│                              │   │ CW agent       │  │               │
│                              │   │ fail2ban       │  │               │
│                              │   │ auditd         │  │               │
│                              │   └────────────────┘  │               │
│                              │   No inbound ports    │               │
│                              └───────────┬──────────┘               │
│                                          │ HTTPS outbound            │
│                                          │ (port 443 only)           │
└──────────────────────────────────────────┼───────────────────────────┘
                                           │
              ┌────────────────────────────▼──────────────────────────┐
              │  CloudWatch                                            │
              │                                                        │
              │  Metrics received (every 60 seconds):                  │
              │  ┌─────────────────┐  ┌─────────────────┐            │
              │  │ CPUUtilization  │  │ mem_used_percent │            │
              │  │ (AWS/EC2)       │  │ (Jtech/EC2)  │            │
              │  └─────────────────┘  └─────────────────┘            │
              │  ┌─────────────────┐  ┌─────────────────┐            │
              │  │ disk_used_%     │  │ StatusCheck-    │            │
              │  │ (Jtech/EC2)  │  │ Failed (AWS/EC2)│            │
              │  └─────────────────┘  └─────────────────┘            │
              │                                                        │
              │  Logs received:                                        │
              │  /jtech/ec2/auth · /jtech/ec2/fail2ban          │
              │  /jtech/ec2/harden                                  │
              │                           │ threshold breach           │
              │                           ▼                            │
              │                    ┌─────────────┐                    │
              │                    │  CloudWatch  │                    │
              │                    │   Alarms (4) │                    │
              │                    └──────┬──────┘                    │
              └───────────────────────────┼───────────────────────────┘
                                          │ alarm/ok
                                          ▼
                                   ┌─────────────┐
                                   │  SNS Topic  │
                                   │  → Email    │
                                   └─────────────┘
```

---

## The monitoring gap AWS doesn't advertise

AWS EC2 basic monitoring sends five metric categories to CloudWatch automatically. None of them include memory utilisation or disk space — both are collected from inside the OS and require the CloudWatch agent.

| Metric | Available by default | Source |
|---|---|---|
| CPU utilisation | Yes | Hypervisor (`AWS/EC2`) |
| Network in / out | Yes | Hypervisor (`AWS/EC2`) |
| Disk read / write (IOPS) | Yes | Hypervisor (`AWS/EC2`) |
| Status check | Yes | Hypervisor (`AWS/EC2`) |
| **Memory used %** | **No** | **CloudWatch agent (`Jtech/EC2`)** |
| **Disk space used %** | **No** | **CloudWatch agent (`Jtech/EC2`)** |

A server can fail silently — out of memory, disk full — while appearing completely healthy in the AWS console. This project installs and configures the CloudWatch agent to close that gap.

---

## Stack

| Layer | Service / Tool | Purpose |
|---|---|---|
| Compute | AWS EC2 (Amazon Linux 2023) | Application server — t2.micro, free tier eligible |
| IaC | Terraform 1.15 | All infrastructure declared as code, remote state |
| Access | AWS SSM Session Manager | Shell access — zero open ports, IAM-controlled |
| Monitoring | AWS CloudWatch + agent | Metrics, logs, alarms, dashboard |
| Alerting | AWS SNS | Email notification on alarm state changes |
| Patching | SSM Patch Manager + dnf-automatic | Automated OS security updates |
| Hardening | fail2ban, sshd_config, sysctl | OS-level security controls |
| State backend | S3 + Lockfile | Inside an S3 backend configuration enables native state file locking. It replaces the old requirement for an external DynamoDB table by using S3 object logic to prevent simultaneous state changes. |

---

## Security implementations

### IMDSv2 — preventing SSRF credential theft

The Instance Metadata Service (IMDS) at `169.254.169.254` exposes the instance's IAM credentials to any code running on the server. IMDSv1 had a critical flaw: any web application vulnerable to SSRF could be tricked into fetching this URL and returning the credentials to an attacker.

IMDSv2 requires a session token obtained via a PUT request before metadata is accessible. SSRF vulnerabilities typically use GET requests and cannot perform the PUT pre-flight. Setting `http_tokens = "required"` in Terraform enforces this at the hypervisor level — no application-level code change can revert it.

```hcl
metadata_options {
  http_endpoint               = "enabled"
  http_tokens                 = "required"   # IMDSv2 enforced
  http_put_response_hop_limit = 1
}
```

### SSM Session Manager — eliminating SSH entirely

| Attack surface | SSH | SSM Session Manager |
|---|---|---|
| Open inbound port | Port 22 exposed | None — outbound 443 only |
| Authentication | Private key file | IAM identity |
| Access revocation | Delete key (if you know where it is) | Remove IAM permission |
| Session recording | Not available | CloudWatch Logs — full audit trail |
| Private subnet access | Requires bastion host | Native — no bastion needed |

The security group for this project has zero inbound rules. No port 22, no custom ports. Every shell session goes through Systems Manager over HTTPS.

### fail2ban configuration

Three failed SSH authentication attempts within a 10-minute window results in a one-hour IP ban. The ban list and all authentication events are shipped to CloudWatch Logs at `/jtech/ec2/fail2ban` and `/jtech/ec2/auth` for security audit purposes.

```
bantime  = 3600    # 1-hour ban
findtime = 600     # within a 10-minute window
maxretry = 3       # 3 attempts maximum
```

### Kernel hardening (sysctl)

Applied via `/etc/sysctl.d/99-jtech-hardening.conf` on first boot:

- `net.ipv4.tcp_syncookies = 1` — SYN flood protection
- `net.ipv4.ip_forward = 0` — not a router
- `net.ipv4.conf.all.accept_redirects = 0` — ICMP redirect attacks
- `net.ipv4.icmp_echo_ignore_broadcasts = 1` — smurf attack mitigation
- `net.ipv4.conf.all.log_martians = 1` — log spoofed packets

---

## Architecture decisions

| Decision | Choice | Rationale |
|---|---|---|
| Shell access | SSM Session Manager | Zero open ports, IAM-controlled access, full session audit trail. SSH keys cannot be centrally revoked; IAM permissions can be revoked instantly and applied to an entire team. |
| IMDSv2 | `http_tokens = required` | Closes the SSRF → credential theft attack vector at the hypervisor level. Cannot be overridden by application code or misconfiguration. |
| Memory/disk monitoring | CloudWatch agent | AWS does not expose these metrics from the hypervisor. The agent runs inside the OS and publishes to a custom namespace (`Jtech/EC2`), enabling alarms on the metrics that matter most for application health. |
| Custom namespace | `Jtech/EC2` | Separates agent metrics from AWS-native metrics. Enables filtering by project in CloudWatch and avoids namespace collisions in a multi-account environment. |
| `evaluation_periods` | 2 for CPU/memory, 1 for disk | CPU and memory spikes are transient; two consecutive breaches confirm a real problem. Disk at 90% is already a problem — one measurement is enough to act. |
| `ok_actions` | Enabled on CPU and memory | Receiving a recovery notification after an alarm clears is as important as the initial alert. Without it, on-call engineers spend time investigating whether an incident has resolved. |
| AMI selection | Data source, not hardcode | `data "aws_ami"` always fetches the latest Amazon Linux 2023 AMI. Hardcoded AMI IDs go stale within weeks and miss security patches. |
| Automatic patching | `dnf-automatic` (security only) | Applies OS security updates automatically without requiring a pipeline run. Scoped to `upgrade_type = security` to avoid unvetted feature updates. |

Full decision log: [`docs/architecture.md`](docs/architecture.md)

---

## Project structure

```
jtech-server-monitoring/
├── .github/
│   └── workflows/
│       └── terraform.yml       # plan on PR, apply on merge to main
├── scripts/
│   ├── harden.sh               # first-boot hardening via user_data
│   └── audit.sh                # weekly security audit script
├── terraform/
│   ├── providers.tf            # AWS provider, version constraints
│   ├── backend.tf              # remote state — shared S3 bucket, unique key
│   ├── variables.tf
│   ├── terraform.tfvars        # your values (no secrets)
│   ├── data.tf                 # AMI lookup (always latest AL2023)
│   ├── ec2.tf                  # instance, security group (no inbound rules)
│   ├── iam.tf                  # instance profile: SSM + CloudWatch policies
│   ├── sns.tf                  # alerts topic + email subscription
│   ├── cloudwatch.tf           # alarms (x4), log groups (x3), dashboard
│   └── outputs.tf              # instance ID, SSM command, dashboard URL
├── docs/
│   ├── architecture.md         # Architecture Decision Records (ADRs)
│   └── runbook.md              # on-call response for each alarm
└── README.md
```

---

## Prerequisites

- AWS CLI configured (`aws sts get-caller-identity` returns your ARN)
- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.15.0
- [AWS Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html) for the AWS CLI (required for `aws ssm start-session`)
- Terraform state backend from Project 1 already bootstrapped (S3 bucket + DynamoDB table)

---

## Getting started

### Step 1 — Find your default VPC ID

```bash
aws ec2 describe-vpcs \
  --filters "Name=isDefault,Values=true" \
  --query "Vpcs[0].VpcId" \
  --output text
# Output: vpc-xxxxxxxxxxxxxxxxx
```

### Step 2 — Configure variables

Edit `terraform/terraform.tfvars`:

```hcl
project_name  = "jtech"
environment   = "prod"
aws_region    = "us-east-1"
instance_type = "t2.micro"
alert_email   = "your@email.com"
vpc_id        = "vpc-xxxxxxxxxxxxxxxxx"
```

### Step 3 — Provision infrastructure

```bash
cd terraform/

terraform init
terraform fmt -recursive
terraform validate
terraform plan -out=tfplan

# Review: you should see ~14 resources to add
terraform apply tfplan
```

### Step 4 — Confirm SNS subscription

Check the inbox for `alert_email`. AWS sends a subscription confirmation immediately after apply. Click the link — without confirming, alarms will never deliver.

### Step 5 — Connect without SSH

```bash
# Get the connection command directly from Terraform
terraform output ssm_connect_command

# Or manually:
aws ssm start-session \
  --target $(terraform output -raw instance_id) \
  --region us-east-1
```

### Step 6 — Verify hardening completed

From inside the SSM session:

```bash
# Confirm the hardening script ran to completion
sudo tail -20 /var/log/harden.log

# Confirm all security services are active
sudo systemctl status fail2ban amazon-cloudwatch-agent

# Confirm kernel hardening applied
sudo sysctl net.ipv4.tcp_syncookies net.ipv4.ip_forward

# Run the security audit manually
sudo bash /home/ssm-user/audit.sh
```

---

## Alarms reference

| Alarm | Metric | Namespace | Threshold | Periods |
|---|---|---|---|---|
| CPU high | `CPUUtilization` | `AWS/EC2` | > 80% | 2 × 5 min |
| Memory high | `mem_used_percent` | `Jtech/EC2` | > 85% | 2 × 5 min |
| Disk high | `disk_used_percent` | `Jtech/EC2` | > 90% | 1 × 5 min |
| Status check | `StatusCheckFailed` | `AWS/EC2` | > 0 | 2 × 1 min |

All alarms publish to the SNS topic. CPU and memory also send an `ok_actions` notification when the alarm clears — on-call engineers know the incident has resolved without checking the console.

---

## CloudWatch Logs

Three log groups ship from the instance, each with 90-day retention:

| Log group | Source file | What it captures |
|---|---|---|
| `/jtech/ec2/harden` | `/var/log/harden.log` | First-boot hardening script output — full audit trail of what ran |
| `/jtech/ec2/auth` | `/var/log/secure` | All authentication events — successful and failed logins |
| `/jtech/ec2/fail2ban` | `/var/log/fail2ban.log` | Banned IPs and ban expirations |

### Useful Logs Insights queries

```sql
-- Failed authentication attempts in the last hour
SOURCE '/jtech/ec2/auth'
| fields @timestamp, @message
| filter @message like /Failed|Invalid user|refused/
| sort @timestamp desc
| limit 100

-- IPs banned by fail2ban today
SOURCE '/jtech/ec2/fail2ban'
| fields @timestamp, @message
| filter @message like /Ban/
| sort @timestamp desc

-- Hardening script step completion
SOURCE '/jtech/ec2/harden'
| fields @timestamp, @message
| filter @message like /\[/
| sort @timestamp asc
```

---

## Key production concepts applied

**The hardening script runs as the first instruction the OS executes.** Using `user_data` with `filebase64()` in Terraform means the script runs before any developer connects, before any application is deployed. The instance is never in an unhardened state after launch.

**`set -euo pipefail` on every bash script.** If any step in `harden.sh` fails — a package doesn't install, a systemctl command errors — the script stops immediately rather than continuing and leaving the instance partially configured. Silent partial failure is more dangerous than an obvious complete failure.

**Disk alarm fires faster than CPU and memory alarms.** `evaluation_periods = 1` for the disk alarm versus `evaluation_periods = 2` for CPU and memory is intentional. A CPU spike that lasts 5 minutes is often a temporary load — two consecutive readings rule out transient noise. A disk at 90% is already a problem. The application is likely failing write operations at this point. One reading is enough.

**Custom namespace separates agent metrics from AWS metrics.** Publishing to `Jtech/EC2` instead of `CWAgent` (the agent's default) means metrics are clearly scoped to this project. In a multi-account or multi-team environment, namespacing by project prevents metric collisions and makes cost attribution straightforward.

**The runbook is written before it is needed.** `docs/runbook.md` documents the response for every alarm before any alarm has ever fired. Writing it forces clear thinking about what each alert means and what the first three actions are. Under incident pressure at 2am is not the time to figure this out.

---

## Lessons learned

1. **AWS does not report memory or disk usage without an agent — full stop.**
   CPU, network, and status checks come from the hypervisor. Memory and disk live inside the OS. Until the CloudWatch agent is installed and configured, you have no visibility into the two metrics that cause the majority of silent application failures.

2. **`user_data` runs once and never again on a running instance.**
   Updating `harden.sh` and running `terraform apply` does not re-run the script on an existing instance. To apply changes: either use `terraform apply -replace=aws_instance.app` to terminate and recreate (clean, reproducible) or run the updated script via an SSM Run Command document. Both approaches are valid — the first is more consistent with IaC principles.

3. **SSM agent registration takes 2–3 minutes after launch.**
   The SSM agent starts on boot and registers itself with the Systems Manager API over HTTPS. Attempting `aws ssm start-session` in the first two minutes after `terraform apply` completes returns a "target not connected" error. Wait, then retry — it is not a configuration problem.

4. **IMDSv2 and the CloudWatch agent require different token handling.**
   The `harden.sh` script uses a two-step curl to fetch the instance ID: first a PUT to get a session token, then a GET using that token. This is the correct IMDSv2 pattern. The CloudWatch agent handles IMDSv2 natively as of version 1.247350.0 (the version shipped with Amazon Linux 2023). No additional configuration is needed for the agent.

5. **`ok_actions` is as important as `alarm_actions`.**
   Without `ok_actions`, an on-call engineer who receives an alarm at 3am and resolves the issue has no automated confirmation that the metric returned to normal. They either watch the console or go back to sleep hoping it resolved. `ok_actions` sends a second notification when the alarm clears — complete the loop.

---

## Extending this project

Documented in `docs/architecture.md` as candidate ADRs:

- **SSM Run Command for audit.sh** — schedule `audit.sh` weekly via Systems Manager Run Command documents rather than cron, so execution and output are visible in the Systems Manager console and CloudWatch Logs
- **Patch compliance reporting** — enable SSM Patch Manager with a patch baseline and compliance report, replacing the `dnf-automatic` approach with a centrally managed, auditable patching workflow
- **CloudWatch anomaly detection** — replace fixed thresholds with ML-based anomaly detection for CPU and memory, reducing false alarms for workloads with variable baseline behaviour
- **Multi-instance monitoring** — extend `cloudwatch.tf` to use metric math across an auto-scaling group rather than a single instance ID
- **GuardDuty integration** — enable Amazon GuardDuty for network-level threat detection (DNS exfiltration, cryptocurrency mining, EC2 credential abuse) at the account level

---

## On-call runbook

Quick reference — full procedures in [`docs/runbook.md`](docs/runbook.md).

```bash
# Connect (no SSH key required)
aws ssm start-session --target $(terraform output -raw instance_id) --region us-east-1

# CPU high: find top consumers
top -b -n 1 | head -20

# Memory high: find top consumers
ps aux --sort=-%mem | head -15

# Disk high: find largest directories
du -sh /var/* | sort -rh | head -10

# Status check failed: attempt SSM first, then stop/start in console
```

---

## Resume bullet

```
Hardened AWS EC2 infrastructure using Terraform IaC: eliminated SSH
entirely via SSM Session Manager (zero open inbound ports), enforced
IMDSv2 preventing SSRF credential theft, automated fail2ban, and deployed
CloudWatch agent to surface memory and disk metrics absent from AWS default
monitoring — backed by four production alarms, SNS alerting pipeline,
CloudWatch log shipping, and a team on-call runbook.
```

---

*Infrastructure managed by Terraform · Access via SSM Session Manager · Zero open inbound ports · Monitored with CloudWatch*
