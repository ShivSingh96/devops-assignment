# Backend blocks cannot use variables; values must be literals.
# The bucket and table are created by ../task2-backend-bootstrap (apply that first).
terraform {
  backend "s3" {
    bucket         = "shivendra-arrise-assignment-tfstate"
    key            = "task1-ec2-module/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-locks"
    encrypt        = true
  }
}
