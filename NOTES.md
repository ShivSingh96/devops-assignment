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
