resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-server-alerts"
}

# Email subscriber — must confirm the subscription via email link
# Terraform creates the subscription; AWS sends a confirmation email
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# Allow CloudWatch to publish to this topic
resource "aws_sns_topic_policy" "alerts" {
  arn    = aws_sns_topic.alerts.arn
  policy = data.aws_iam_policy_document.sns_cloudwatch.json
}

data "aws_iam_policy_document" "sns_cloudwatch" {
  statement {
    effect  = "Allow"
    actions = ["SNS:Publish"]
    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }
    resources = [aws_sns_topic.alerts.arn]
  }
}
