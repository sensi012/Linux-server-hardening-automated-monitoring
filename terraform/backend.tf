terraform {
  backend "s3" {
    bucket       = "jtech-terraform-state"
    key          = "jtech/server-monitoring/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}
