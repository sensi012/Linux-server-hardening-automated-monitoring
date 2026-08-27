#!/bin/bash

# terraform state file

echo

# 1. Create the S3 Bucket
aws s3 mb s3://jtech-terraform-state-210450948229 --region us-east-1

# 2. Block all public access to the bucket (security)
aws s3api put-public-access-block \
  --bucket jtech-terraform-state-210450948229 \
  --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" \
  --region us-east-1
  
# Enable bucket versioning to allow rolling back state changes
aws s3api put-bucket-versioning \
  --bucket jtech-terraform-state-210450948229 \
  --versioning-configuration Status=Enabled \
  --region us-east-1
