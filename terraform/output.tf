output "instance_id" {
  description = "EC2 instance ID — use this for SSM sessions"
  value       = aws_instance.app.id
}

output "ssm_connect_command" {
  description = "Run this to open a shell — no SSH key required"
  value       = "aws ssm start-session --target ${aws_instance.app.id} --region ${var.aws_region}"
}

output "cloudwatch_dashboard_url" {
  description = "Direct link to server health dashboard"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${var.project_name}-server-health"
}

output "sns_topic_arn" {
  description = "SNS topic ARN — confirm subscription via email after apply"
  value       = aws_sns_topic.alerts.arn
}
