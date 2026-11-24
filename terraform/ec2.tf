resource "aws_instance" "app" {
  ami           = data.aws_ami.al2023.id
  instance_type = var.instance_type

  subnet_id              = data.aws_subnets.default.ids[0]
  vpc_security_group_ids = [aws_security_group.ec2.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2.name

  # IMDSv2: prevents SSRF attacks from stealing instance credentials
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # enforces IMDSv2 — not optional
    http_put_response_hop_limit = 1
  }

  # Detailed monitoring: 1-minute intervals vs default 5-minute
  # Costs ~$2/month but gives much faster alarm response times
  monitoring = true

  # Hardening script runs automatically on first boot
  user_data_base64 = filebase64("${path.module}/../scripts/harden.sh")


  root_block_device {
    volume_type           = "gp3"
    volume_size           = 30
    encrypted             = true # encrypt data at rest
    delete_on_termination = true
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-app-server"
  }
}

# Security group: NO inbound rules — SSM doesn't need open ports
resource "aws_security_group" "ec2" {
  name        = "${var.project_name}-ec2-sg"
  description = "Jtech EC2 outbound only, SSM access via IAM"
  vpc_id      = var.vpc_id

  # HTTPS outbound: SSM agent, CloudWatch agent, package updates
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS for SSM, CloudWatch, AWS APIs"
  }

  # HTTP outbound: yum package downloads
  egress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP for package repositories"
  }
}
# No aws_security_group_rule for inbound — intentional.
# Port 22 is NOT open. SSM handles all shell access through IAM.
