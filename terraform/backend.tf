terraform {
  backend "s3" {
    bucket       = "jtech-terraform-state-210450948229"
    key          = "jtech/server-monitoring/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}
