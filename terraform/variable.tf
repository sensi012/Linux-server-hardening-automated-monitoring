variable "project_name" {
  description = "Project name for resource naming and tags"
  type        = string
  default     = "jtech"
}

variable "environment" {
  type    = string
  default = "prod"
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "instance_type" {
  description = "EC2 instance type — t2.micro is free tier eligible"
  type        = string
  default     = "t2.micro"
}

variable "alert_email" {
  description = "Email address to receive CloudWatch alarm notifications"
  type        = string
}



variable "tags" {
  type = map(string)
  default = {
    Name        = "jtech-server-monitoring"
    Environment = "prod"
  }
}
