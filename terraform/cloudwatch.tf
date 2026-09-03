# ── LOG GROUPS ────────────────────────────────────────────────────────
resource "aws_cloudwatch_log_group" "harden" {
  name              = "/jtech/ec2/harden"
  retention_in_days = 90
}

resource "aws_cloudwatch_log_group" "auth" {
  name              = "/jtech/ec2/auth"
  retention_in_days = 90
}

resource "aws_cloudwatch_log_group" "fail2ban" {
  name              = "/jtech/ec2/fail2ban"
  retention_in_days = 90
}

# ── ALARMS ────────────────────────────────────────────────────────────
# Alarm 1: CPU — standard metric, available without CloudWatch agent
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${var.project_name}-cpu-high"
  alarm_description   = "CPU > 80% for 10 minutes — possible runaway process"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn] # notify when alarm clears
  dimensions          = { InstanceId = aws_instance.app.id }
}

# Alarm 2: Memory — custom metric from CloudWatch agent (Jtech/EC2 namespace)
resource "aws_cloudwatch_metric_alarm" "memory_high" {
  alarm_name          = "${var.project_name}-memory-high"
  alarm_description   = "Memory > 85% for 10 minutes — risk of OOM kills"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "mem_used_percent"
  namespace           = "Jtech/EC2" # custom namespace from harden.sh agent config
  period              = 300
  statistic           = "Average"
  threshold           = 85
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  dimensions          = { InstanceId = aws_instance.app.id }
}

# Alarm 3: Disk — custom metric. Acts fast: 1 period, not 2
# Disks fill to 100% fast — you want immediate alerting at 90%
resource "aws_cloudwatch_metric_alarm" "disk_high" {
  alarm_name          = "${var.project_name}-disk-high"
  alarm_description   = "Disk usage > 90% — server will crash when disk is full"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "disk_used_percent"
  namespace           = "Jtech/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 90
  alarm_actions       = [aws_sns_topic.alerts.arn]
  dimensions          = { InstanceId = aws_instance.app.id }
}

# Alarm 4: Status check — catches hardware failures and kernel panics
# Threshold = 0 means any failure triggers the alarm immediately
resource "aws_cloudwatch_metric_alarm" "status_check" {
  alarm_name          = "${var.project_name}-status-check-failed"
  alarm_description   = "EC2 instance status check failed — hardware or OS issue"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "StatusCheckFailed"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  alarm_actions       = [aws_sns_topic.alerts.arn]
  dimensions          = { InstanceId = aws_instance.app.id }
}

# ── DASHBOARD ─────────────────────────────────────────────────────────
resource "aws_cloudwatch_dashboard" "server" {
  dashboard_name = "${var.project_name}-server-health"
  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 12, height = 6
        properties = {
          title       = "CPU Utilisation"
          view        = "timeSeries"
          period      = 300
          region      = var.aws_region
          metrics     = [["AWS/EC2", "CPUUtilization", "InstanceId", aws_instance.app.id]]
          annotations = { horizontal = [{ value = 80, label = "Alarm threshold", color = "#ff0000" }] }
        }
      },
      {
        type = "metric", x = 12, y = 0, width = 12, height = 6
        properties = {
          title       = "Memory Used %"
          view        = "timeSeries"
          period      = 300
          region      = var.aws_region
          metrics     = [["Jtech/EC2", "mem_used_percent", "InstanceId", aws_instance.app.id]]
          annotations = { horizontal = [{ value = 85, label = "Alarm threshold", color = "#ff0000" }] }
        }
      },
      {
        type = "metric", x = 0, y = 6, width = 12, height = 6
        properties = {
          title       = "Disk Used %"
          view        = "timeSeries"
          period      = 300
          region      = var.aws_region
          metrics     = [["Jtech/EC2", "disk_used_percent", "InstanceId", aws_instance.app.id]]
          annotations = { horizontal = [{ value = 90, label = "Alarm threshold", color = "#ff0000" }] }
        }
      },
      {
        type = "log", x = 12, y = 6, width = 12, height = 6
        properties = {
          title  = "Recent auth failures (from /var/log/secure)"
          query  = "SOURCE '/jtech/ec2/auth' | fields @timestamp, @message | filter @message like /Failed|Invalid|refused/ | sort @timestamp desc | limit 50"
          region = var.aws_region
          view   = "table"
        }
      }
    ]
  })
}