terraform {
  required_version = ">= 1.15.0"
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = var.tags
  }
}
