# EC2 must assume this role to use SSM and CloudWatch
resource "aws_iam_role" "ec2" {
  name        = "${var.project_name}-ec2-instance-role"
  description = "Role for Jtech EC2 instances - SSM + CloudWatch"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

# AmazonSSMManagedInstanceCore: enables Session Manager shell access
# and Patch Manager for automated patching — no SSH required
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# CloudWatchAgentServerPolicy: allows agent to send metrics and logs
# to CloudWatch — memory, disk, and log file shipping
resource "aws_iam_role_policy_attachment" "cloudwatch" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Instance profile: the bridge between an IAM role and an EC2 instance
# Every EC2 instance needs a profile wrapper around its role
resource "aws_iam_instance_profile" "ec2" {
  name = "${var.project_name}-ec2-profile"
  role = aws_iam_role.ec2.name
}
