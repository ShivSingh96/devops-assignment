# Name of the single bucket roleC may use (same value as task3-iam/account-b)
variable "bucket_name" {
  type    = string
  default = "shivendra-arrise-assignment-data"
}

data "aws_iam_policy_document" "roleC_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::000000000000:role/roleB"] # role, not user
    }
  }
}

resource "aws_iam_role" "roleC" {
  name               = "roleC"
  assume_role_policy = data.aws_iam_policy_document.roleC_trust.json
}

resource "aws_iam_role_policy" "roleC_s3" {
  name = "roleC-s3-access"
  role = aws_iam_role.roleC.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "s3:*" # task asks for full access, but only to one bucket
      Resource = [
        "arn:aws:s3:::${var.bucket_name}",   # bucket-level actions
        "arn:aws:s3:::${var.bucket_name}/*", # object-level actions
      ]
    }]
  })
}
