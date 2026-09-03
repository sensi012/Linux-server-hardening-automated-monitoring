# data sources query AWS at plan time — no hardcoded AMI IDs
# Hardcoding AMI IDs means missing security patches; this always pulls latest
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Get the default subnet in the first AZ — used for instance placement
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
}