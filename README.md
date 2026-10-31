# DevOps Assignment

Terraform for Tasks 1-5. Design decisions and written answers are in [NOTES.md](NOTES.md).

## Layout

```text
.
├── task1-ec2-module/        # 5 EC2 instances from one map variable; S3 backend config (Task 2)
├── task2-backend-bootstrap/ # S3 state bucket + DynamoDB lock table
├── task3-iam/
│   ├── account-a/           # users, group1/group2, roleA, roleB, ci policy attachment
│   └── account-b/           # S3 bucket + roleC (trusts only roleB)
├── task4-ci-policy/         # ci-policy.json (least-privilege CI policy)
├── task5-fix/               # corrected trust + permissions policy
└── NOTES.md                 # explanations and written answers
```

## Apply order

1. `task2-backend-bootstrap`: creates the state bucket and lock table (local state).
2. `task1-ec2-module`: `terraform init` picks up the S3 backend from `backend.tf`.
3. `task3-iam/account-a`, then `task3-iam/account-b` (roleC's trust policy needs roleB to exist).

```bash
cd task2-backend-bootstrap && terraform init && terraform apply   # state bucket + lock table
cd ../task1-ec2-module && terraform init && terraform plan        # remote backend, 5 instances
cd ../task3-iam/account-a && terraform init && terraform apply    # credentials for 000000000000
cd ../account-b && terraform init && terraform apply              # credentials for 111111111111
```

## Placeholders to replace before a real apply

- `task1-ec2-module/terraform.tfvars`: `subnet_id`
- `task2-backend-bootstrap` and `task1-ec2-module/backend.tf`: state bucket name (S3 names are global; both must match)
- `task3-iam/account-b`: `bucket_name`
- `task4-ci-policy/ci-policy.json`: repository, cluster/service, role and bucket names

## Status

Every Terraform directory passes `terraform fmt -check` and `terraform validate`. Nothing has been planned or applied against a real AWS account.
