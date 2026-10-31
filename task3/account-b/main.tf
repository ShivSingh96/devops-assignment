terraform {
  required_version = ">= 1.3.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Run with credentials for Account B (111111111111)
provider "aws" {
  region = var.region
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "account_a_id" {
  type    = string
  default = "000000000000"
}

# The single bucket roleC may use. S3 names are global; change if taken.
variable "bucket_name" {
  type    = string
  default = "shivendra-arrise-assignment-data"
}

resource "aws_s3_bucket" "data" {
  bucket = var.bucket_name
}

# Trust ONLY the roleB role in Account A (a role ARN, not the account root, not a user).
# Apply account-a first: IAM rejects a trust principal ARN that does not exist yet.
data "aws_iam_policy_document" "role_c_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.account_a_id}:role/roleB"]
    }
  }
}

resource "aws_iam_role" "role_c" {
  name               = "roleC"
  assume_role_policy = data.aws_iam_policy_document.role_c_trust.json
}

# Full S3 access, but only to this bucket. The bucket and its objects are separate resources.
data "aws_iam_policy_document" "role_c_s3" {
  statement {
    effect  = "Allow"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.data.arn,
      "${aws_s3_bucket.data.arn}/*",
    ]
  }
}

resource "aws_iam_role_policy" "role_c_s3" {
  name   = "roleC-s3-bucket-access"
  role   = aws_iam_role.role_c.id
  policy = data.aws_iam_policy_document.role_c_s3.json
}

output "role_c_arn" {
  value = aws_iam_role.role_c.arn
}
