terraform {
  required_version = ">= 1.3.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  type    = string
  default = "us-east-1"
}

# Must match the bucket/table names in task1-ec2-module/backend.tf
variable "state_bucket_name" {
  type    = string
  default = "shivendra-arrise-assignment-tfstate" # S3 names are global; change if taken
}

variable "lock_table_name" {
  type    = string
  default = "terraform-state-locks"
}

resource "aws_s3_bucket" "state" {
  bucket = var.state_bucket_name

  # state is the source of truth for everything else; make the bucket hard to delete
  lifecycle {
    prevent_destroy = true
  }
}

# Versioning lets you roll back a corrupted or overwritten state file
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# State holds secrets in plaintext (e.g. the TLS private keys from Task 1)
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# The S3 backend requires a string hash key named exactly "LockID"
resource "aws_dynamodb_table" "locks" {
  name         = var.lock_table_name
  billing_mode = "PAY_PER_REQUEST" # lock traffic is tiny; no capacity to manage
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

output "state_bucket" {
  value = aws_s3_bucket.state.id
}

output "lock_table" {
  value = aws_dynamodb_table.locks.name
}

