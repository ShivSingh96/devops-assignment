# Notes

## Task 1: Multi-Instance EC2

### Design

- A single `instances` map variable drives all 5 instances via `for_each`; the map key is the instance name.
- One key pair per instance is generated with `tls_private_key` + `aws_key_pair`. Private keys are exposed only through a `sensitive` output and are never written to disk.
- `at least one io1/io2` and `iops required for io1/io2` are enforced with variable validations.

### Protected instance: `db`

`db` is the only instance with `prevent_destroy = true`. It is the stateful one (io2 volume, database role); losing it means losing data, whereas the other four are stateless and can be rebuilt from the AMI.

Because `prevent_destroy` must be a literal (it cannot reference `each.value`), the single input map is split into `protected_instances` and `normal_instances`, and two `aws_instance` blocks consume them. A validation requires exactly one `protected = true` entry.

Caveat: `prevent_destroy` only blocks plans that would destroy the resource. It does not stop someone deleting the resource block from the code (the plan then errors, which is the intended guard) or deleting the instance in the console.

## Task 2: Remote State and Locking

### Setup

- `task2-backend-bootstrap/` creates the S3 bucket (versioned, encrypted, public access blocked) and the DynamoDB table (`LockID` string hash key, on-demand billing). It uses local state because the backend can't store its own state before it exists.
- `task1-ec2-module/backend.tf` points the module at them. Backend blocks can't use variables, so the names are literals and must match the bootstrap defaults.
- Apply order: bootstrap first, then `terraform init` in the module (it offers to migrate any local state to S3).

### What happens today (local state) if two people run `apply` at once

Local state is a `terraform.tfstate` file on each person's machine, so each person has their own copy. Terraform's local lock file only guards that one machine, so nothing stops the two applies.

- **Separate copies (most likely):** both plans are computed from stale or empty state, so both create the same resources. Result: duplicate instances and key pairs, or errors on name collisions, and two diverging state files that each describe only part of reality.
- **Shared copy (git, shared drive):** both read the same state, both write back, and the last writer wins. The first writer's resources are recorded nowhere, so they become orphans that Terraform no longer manages. A concurrent write can also corrupt the file.

### How the S3 + DynamoDB backend prevents it

- State lives in one place, so everyone plans against the same truth.
- Before any operation that writes state, Terraform puts an item with key `LockID` into DynamoDB using a conditional write (it succeeds only if the item doesn't exist already).
- The second person's conditional write fails, so their `apply` stops with `Error acquiring the state lock`, showing who holds the lock, the operation, and when it started. They can retry, or use `-lock-timeout=5m` to wait.
- The lock is released when the first run finishes. If a run crashes, `terraform force-unlock <ID>` clears a stale lock.
- S3 versioning and encryption additionally allow rolling back state and protect the secrets it contains.

## Task 3: Multi-Account IAM and Cross-Account Access

### Layout

- `task3-iam/account-a/`: users `engine`, `ci` (group1, no console password, no access keys created), users `alice.admin`, `bob.dev` (group2, console login profile), `roleA`, `roleB`.
- `task3-iam/account-b/`: the S3 bucket and `roleC`.
- Apply `account-a` first, then `account-b` (IAM rejects a trust principal ARN that does not exist yet).
- Access chain: `engine`/`ci` assume `roleB` (Account A), then `roleB` assumes `roleC` (Account B). `group2` users assume `roleA`.
- Every hop needs both sides: a trust policy on the target role and an `sts:AssumeRole` allow on the caller. Groups can't be trust principals, so the trust policies list user/role ARNs and the groups carry the identity-side allow.
- `roleA` is `Allow NotAction iam:*` plus an explicit `Deny iam:*`, so it cannot be widened to IAM by another policy later.
- `group1` is CLI-only simply because no login profile is created for its users. `group2` users get a generated password (kept in state) with `password_reset_required = true`.

### Q1: Would I give `engine` and `ci` IAM users with access keys in production?

No. Long-lived access keys are the most common cause of credential leaks: they don't expire, get copied into laptops, CI variables and logs, and rotation is manual.

- **`ci`:** use OIDC federation (e.g. GitHub Actions to an IAM role). The pipeline gets short-lived credentials per run, with no stored secret, and the role's trust policy can be pinned to a specific repo and branch.
- **`engine`** (a service or automation): if it runs on AWS, use an instance profile, ECS task role, or IRSA, which supply temporary credentials automatically. If it runs elsewhere, use IAM Roles Anywhere.
- **Humans:** IAM Identity Center (SSO) with short sessions and MFA, not IAM users.

Where an IAM user with keys is unavoidable: scope it tightly, rotate on a schedule, alert on use, and never create the keys in Terraform (they'd land in state). This assignment asks for the users, so they exist, but no keys are created.

### Q2: Why does it matter whether `roleC` trusts Account A's root or `roleB`'s ARN?

Trusting `arn:aws:iam::000000000000:root` means "any principal in Account A that has been granted `sts:AssumeRole` on roleC". Account A's admins control that, so anyone in Account A with a permissive policy (or `AdministratorAccess`) could assume `roleC` and get full access to the bucket. Account B has delegated its security boundary to everything Account A ever does.

Trusting `roleB`'s ARN limits it to that one role:

- Even Account A admins and other roles can't assume `roleC` unless they first assume `roleB`.
- Access is auditable through one identifiable path.
- Least privilege holds on both sides: `roleB` can only call `AssumeRole` on `roleC`, and `roleC` only accepts `roleB`.

Note that the ARN is resolved to the role's unique ID when the trust policy is saved. If `roleB` is deleted and recreated with the same name, the old trust entry stops matching, so apply order and role replacement matter.

## Task 4: Least-Privilege Policy for `ci`

File: `task4-ci-policy/ci-policy.json`. The names (`app` repo, `main-cluster/app-service`, `build-artifacts` bucket, `app-task-role`, `app-task-execution-role`, account `000000000000`) are placeholders to swap for real values.

### What each statement is for

| Statement | Why it exists |
|---|---|
| `EcrLogin` | `docker login` to ECR needs `GetAuthorizationToken`. It can't be scoped to a repo, so `Resource: "*"` is the only valid value. |
| `EcrPushToOneRepo` | The five calls a `docker push` makes (layer check, upload init, upload part, complete, put manifest), on one repository only. |
| `EcsTaskDefinitionApis` | Registering a task definition and reading the current one. These APIs don't support resource-level permissions, so `*` is required. |
| `EcsDeployToOneService` | `UpdateService` points the service at the new revision; `DescribeServices` lets the pipeline wait for stability. Scoped to one service ARN. |
| `PassOnlyTheTaskRolesToEcs` | Registering a task definition that names roles requires `iam:PassRole`. Limited to the two named roles and to `ecs-tasks.amazonaws.com`. |
| `ReadArtifactsBucket*` | `ListBucket` on the bucket ARN, `GetObject` on `bucket/*`. No write actions. |

### What I deliberately left out, and why

- **`ecr:BatchGetImage` / `GetDownloadUrlForLayer`:** these are pull permissions. A push doesn't need them. Add only if the pipeline pulls from the repo (e.g. layer caching).
- **`ecr:CreateRepository`, `DeleteRepository`, `BatchDeleteImage`:** the repo is created ahead of time by infrastructure code. A CI user that can create or delete repos can destroy the image history.
- **`ecs:CreateService`, `DeleteService`, `RunTask`, `StopTask`:** CI deploys a new revision to an existing service; it does not create services or run arbitrary tasks.
- **`ecs:DeregisterTaskDefinition`:** old revisions are harmless; deleting them isn't a deploy step.
- **`iam:PassRole` on `*`:** this is the classic privilege-escalation path (pass an admin role to a task you control). So it's pinned to two roles and to the ECS service principal.
- **Any other `iam:*`, `sts:*`, `kms:*`:** not part of the three jobs.
- **`s3:PutObject`, `DeleteObject`, and `s3:*`:** the bucket is read-only for this user, as specified. Build artifacts are produced elsewhere.
- **`s3:GetBucketLocation`, `ListAllMyBuckets`:** not needed for reading known keys; add if a tool complains.
- **Managed policies** (`PowerUserAccess`, `AmazonECS_FullAccess`, `AmazonEC2ContainerRegistryPowerUser`): they grant far more than these three jobs.
- **Region/IP/MFA conditions:** useful hardening, but they'd make the policy depend on pipeline details I don't have. The ARNs already pin the region.

### Limitations

- `ecs:RegisterTaskDefinition` on `*` means CI can register any task definition. The `PassRole` restriction is what stops it using powerful roles in one.
- This is static analysis only. I haven't run it through IAM Access Analyzer or a deploy, so a pipeline might surface a missing action (CloudTrail `AccessDenied` events show which).
