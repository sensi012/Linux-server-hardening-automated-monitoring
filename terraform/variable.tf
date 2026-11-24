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

variable "vpc_id" {
  description = "VPC ID to deploy into. Use default VPC for now (Project 4 builds custom VPC)."
  type        = string
}

variable "tags" {
  description = "Default tags to apply to all AWS resources"
  type        = map(string)
  default     = {}
}