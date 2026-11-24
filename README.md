# Jtech Server Monitoring — EC2 Hardening & CloudWatch Observability

[![Terraform](https://img.shields.io/github/actions/workflow/status/sensi012/Linux-server-hardening-automated-monitoring/terraform.yml?label=terraform&logo=terraform&logoColor=white)](https://github.com/sensi012/Linux-server-hardening-automated-monitoring/actions/workflows/terraform.yml)
[![IaC: Terraform](https://img.shields.io/badge/IaC-Terraform_1.15-7B42BC?logo=terraform)](https://www.terraform.io/)
[![Cloud: AWS](https://img.shields.io/badge/Cloud-AWS-FF9900?logo=amazon-aws&logoColor=white)](https://aws.amazon.com/)
[![Access: SSM](https://img.shields.io/badge/Access-SSM_Session_Manager-1D9E75)](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html)

Hardened Amazon Linux 2023 EC2 infrastructure provisioned with Terraform. Eliminates inbound SSH in favor of AWS SSM Session Manager, enforces IMDSv2 and encrypted EBS storage, runs first-boot OS hardening (`fail2ban`, `sysctl`, `dnf-automatic`), and ships metrics and auth logs to CloudWatch with five SNS-backed alarms.

---

## Architecture

```
aws ssm start-session --target <instance-id>
        │
        ▼ (IAM auth, HTTPS 443)
AWS Systems Manager ──► EC2 (Amazon Linux 2023, zero inbound rules)
                        ├── SSM agent
                        ├── CloudWatch agent (mem, disk, logs)
                        ├── fail2ban + sshd hardening
                        └── dnf-automatic (security updates)
                                │
                                ▼ (HTTPS 443 outbound)
                           CloudWatch
                        ├── Metrics: CPU, StatusCheck (AWS/EC2)
                        │            Memory, Disk, SSHAuthFailures (Jtech/EC2)
                        ├── Logs:    /jtech/ec2/harden, /jtech/ec2/auth, /jtech/ec2/fail2ban
                        └── Alarms (5) ──► SNS Topic ──► Email
```

---

## Stack

| Layer | Service / Tool | Purpose |
|---|---|---|
| Compute | AWS EC2 (Amazon Linux 2023) | Application server (`gp3` encrypted root volume, IMDSv2 required) |
| IaC | Terraform | Infrastructure as Code with S3 remote state (`use_lockfile = true`) |
| Access | AWS SSM Session Manager | Shell access with zero open inbound ports |
| Monitoring | CloudWatch + CW Agent | CPU, memory, disk, status checks, log shipping, and dashboard |
| Alerting | AWS SNS | Email notifications on alarm and recovery |
| Hardening | `harden.sh`, `fail2ban`, `sysctl`, `dnf-automatic` | Automated first-boot OS hardening and security patching |

---

## Project structure

```
.
├── .github/workflows/terraform.yml   # CI/CD: plan on PR, apply on merge
├── scripts/
│   ├── harden.sh                     # First-boot hardening via EC2 user_data
│   └── audit.sh                      # Manual security audit script
├── terraform/
│   ├── backend.tf                    # S3 remote state with native lockfile
│   ├── cloudwatch.tf                 # Log groups (x3), metric filter, alarms (x5), dashboard
│   ├── data.tf                       # Latest Amazon Linux 2023 AMI + default subnet lookup
│   ├── ec2.tf                        # EC2 instance + outbound-only security group
│   ├── iam.tf                        # Instance role/profile (SSM + CloudWatch)
│   ├── oidc.tf                       # GitHub Actions OIDC role
│   ├── output.tf                     # Instance ID, SSM command, dashboard URL, SNS ARN
│   ├── provider.tf                   # AWS provider configuration
│   ├── sns.tf                        # Alert topic, email subscription, topic policy
│   ├── terraform.tfvars              # Environment variable values
│   ├── variable.tf                   # Input variable declarations
│   └── vpc.tf                        # VPC configuration
├── backend-bucket.sh                 # Bootstraps the S3 state bucket
├── doc.md                            # On-call runbook
├── follow-through.md                 # Quick walkthrough tied to the problem context
└── README.md
```

---

## Prerequisites

- AWS CLI configured (`aws sts get-caller-identity`)
- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.15.0
- [AWS Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html)
- S3 state bucket bootstrapped (see `backend-bucket.sh` and `terraform/backend.tf`)

---

## Getting started

### 1. Configure variables

Update `terraform/terraform.tfvars`:

```hcl
project_name  = "jtech"
environment   = "prod"
aws_region    = "us-east-1"
instance_type = "t2.micro"
alert_email   = "your@email.com"
vpc_id        = "vpc-xxxxxxxxxxxxxxxxx"
```

### 2. Provision infrastructure

```bash
cd terraform
terraform init
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
```

### 3. Confirm SNS subscription

Open the confirmation email sent by AWS to `alert_email` and click **Confirm subscription**. Alarms will not deliver emails until confirmed.

### 4. Connect via SSM (no SSH)

```bash
terraform output ssm_connect_command
```

> Wait 2–3 minutes after launch for the SSM agent to register before starting a session.

### 5. Verify hardening

Inside the SSM session:

```bash
sudo tail -20 /var/log/harden.log
sudo systemctl status fail2ban amazon-cloudwatch-agent
sudo sysctl net.ipv4.tcp_syncookies net.ipv4.ip_forward
```

To run a full compliance check, copy/run `scripts/audit.sh` on the instance.

---

## Alarms & logs reference

### CloudWatch Alarms

| Alarm | Metric | Namespace | Threshold | Evaluation |
|---|---|---|---|---|
| CPU high | `CPUUtilization` | `AWS/EC2` | `> 80%` | 2 × 5 min (`ok_actions` enabled) |
| Memory high | `mem_used_percent` | `Jtech/EC2` | `> 85%` | 2 × 5 min (`ok_actions` enabled) |
| Disk high | `disk_used_percent` | `Jtech/EC2` | `> 90%` | 1 × 5 min |
| Status check failed | `StatusCheckFailed` | `AWS/EC2` | `> 0` | 2 × 1 min |
| SSH / auth failures | `SSHAuthFailures` | `Jtech/EC2` | `>= 5` | 1 × 5 min (from `/jtech/ec2/auth`) |

### CloudWatch Log Groups (90-day retention)

| Log group | Source file | Contents |
|---|---|---|
| `/jtech/ec2/harden` | `/var/log/harden.log` | First-boot hardening output |
| `/jtech/ec2/auth` | `/var/log/secure` | SSH and system authentication events |
| `/jtech/ec2/fail2ban` | `/var/log/fail2ban.log` | IP bans and unbans |

---

## Documentation

- **On-call runbook:** [`doc.md`](doc.md)
- **Step-by-step walkthrough:** [`follow-through.md`](follow-through.md)
