# Phase 2 Terraform: Execution from Start to End

Oct 9, 2026 · @Abhinav

Terraform runs in five commands. `apply` builds the 5 modules in the order their references force, then writes a small hand-off file for Ansible. Everything below follows that path from the first `bootstrap` to the last `destroy`.

## The big picture

&#91;embedded content: Terraform commands and the order apply builds the modules\]

Each level starts only when everything it references exists: instances need subnets, security groups and the key pair, and the NLB's attachments need the instance IDs. The diagram shows whole modules; Stage 3 shows the individual resources, some of which overlap across levels. `destroy` walks the same graph from the bottom up.

## The files Terraform reads

Terraform runs in one folder at a time, the **root module**. For dev that folder is `terraform/live/dev`. It reads every `*.tf` file in that folder as one configuration, so the file names exist only for people; Terraform ignores the order of files and blocks. Files in `modules/` are read only because `live/dev/main.tf` calls them.

| File | Read when | Purpose |
| --- | --- | --- |
| `bootstrap/main.tf` | Once, by its own `init` / `apply` | Creates the S3 bucket that will hold all other state |
| `live/dev/backend.hcl` | `terraform init` | Bucket, key, region, encryption and locking for the S3 backend. Written by `run.sh bootstrap`, git-ignored |
| `live/dev/versions.tf` | Every command | Terraform version, provider versions, empty `backend "s3" {}`, AWS provider with default tags |
| `live/dev/variables.tf` | plan / apply | Declares every input with type, default and validation (for example: control planes must be odd) |
| `live/dev/terraform.tfvars` | plan / apply, loaded automatically | The dev values. Committed; contains no secrets |
| `live/dev/main.tf` | plan / apply | Calls the 5 modules and connects their outputs to each other's inputs |
| `live/dev/ansible_handoff.tf` | plan / apply | Writes `group_vars/all/terraform.yml` for Ansible |
| `live/dev/outputs.tf` | After apply, `terraform output` | Values people and scripts need: NLB DNS, node IPs, secret name |
| `modules/<name>/*.tf` | When the root calls the module | `variables.tf` = inputs, `main.tf` = resources, `outputs.tf` = what the caller may use |
| `.terraform.lock.hcl` | Created by `init`, then read every time | Exact provider versions and checksums. Commit it so the whole team uses identical providers |

## Stage 0: bootstrap (once per AWS account)

Command: `./scripts/run.sh bootstrap`, which runs `terraform init` and `terraform apply` in `terraform/bootstrap`.

The real environment keeps its state in S3, but that bucket must exist before any `init` can use it. So bootstrap is a tiny, separate root module with **local** state (a `terraform.tfstate` file in `bootstrap/`). This is the classic chicken-and-egg step that every company does once.

1. `data.aws_caller_identity` reads your AWS account ID.
2. `aws_s3_bucket.state` creates `k8s-ha-tfstate-<account-id>-us-west-2`. Bucket names are global, and the account ID makes the name unique.
3. These four settings are created in parallel, because each depends only on the bucket:
   - **versioning**: every state write is a new object version, so you can roll back.
   - **AES-256 encryption at rest**: the state contains secrets, such as the generated SSH private key.
   - **public access block**.
   - **a bucket policy that denies non-HTTPS access**: this one waits for the public access block (`depends_on`).
4. The output `backend_hcl_dev` prints the backend settings. `run.sh` writes them to `live/dev/backend.hcl`:

```hcl
bucket       = "k8s-ha-tfstate-123456789012-us-west-2"
key          = "dev/terraform.tfstate"   # one key per environment
region       = "us-west-2"
encrypt      = true
use_lockfile = true                      # S3-native locking, Terraform >= 1.10
```

Keep `bootstrap/terraform.tfstate` safe. If you lose it, the bucket still works; you would only need `terraform import` to manage the bucket itself again.

## Stage 1: terraform init

Command (inside `run.sh plan`): `terraform -chdir=live/dev init -backend-config=backend.hcl`

`init` prepares the folder. It creates no AWS resources, and it does these four things in order:

1. **Backend.** It merges the empty `backend "s3" {}` from `versions.tf` with `backend.hcl`. This "partial configuration" keeps account-specific values out of the code, and lets the same code serve dev and prod with different files. It connects to the bucket and checks that the key `dev/terraform.tfstate` is readable (the key is empty on the first run).
2. **Modules.** Every `module` block with `source = "../../modules/..."` is recorded in `.terraform/modules/modules.json`. Local modules are referenced in place, not copied, so an edit to a module is picked up immediately.
3. **Providers.** It reads `required_providers` from the root (`aws ~> 5.80`, `tls`, `local`, `http`) and from each module. Then it picks the newest versions that satisfy every constraint, downloads them into `.terraform/providers/`, and records the exact versions and checksums in `.terraform.lock.hcl`.
4. **Lock file.** On later runs, `init` installs exactly the versions in `.terraform.lock.hcl` and ignores newer releases. To move to a newer provider on purpose, run `terraform init -upgrade`, then commit the changed lock file.

Modules don't configure providers themselves; they only declare which ones they need (`modules/ssh-key` needs `tls`). The root's `provider "aws"` block, with region `us-west-2` and default tags, is passed down to every module automatically. That's why every resource gets the `Project`, `Environment`, `ManagedBy` and `Owner` tags without any module mentioning them.

## Stage 2: validate and plan

Commands (also inside `run.sh plan`): `terraform fmt -check -recursive`, `terraform validate`, `terraform plan -out=tfplan`

`fmt` and `validate` don't need AWS. `fmt` checks layout. `validate` checks syntax, types, and that every reference points to something that exists, for example that `module.network.vpc_id` is a real output.

`plan` then works through seven steps:

1. **Lock the state.** Terraform writes `dev/terraform.tfstate.tflock` next to the state in S3. A second person running plan or apply at the same moment gets `Error acquiring the state lock` instead of corrupting the state.
2. **Load variable values.** Lowest priority first: the `default` in `variables.tf`, then `TF_VAR_*` environment variables, then `terraform.tfvars`, then `*.auto.tfvars`, then `-var` / `-var-file` on the command line; the last one wins. Validation rules run now, so `control_plane_count = 2` fails here with "Use an odd number of control planes".
3. **Read the current state** from S3, and **refresh** it: for every resource already in state, ask AWS what it looks like now. This is how manual changes made in the console (drift) are detected.
4. **Read data sources.** A data source is a lookup, not a resource:
   - `data.http.my_ip` calls checkip.amazonaws.com. `local.admin_cidrs` becomes `["<your-ip>/32"]` because `admin_cidrs` is empty in tfvars.
   - `data.aws_availability_zones` (in `modules/network`) returns the AZs; the first 3 are used.
   - `data.aws_ssm_parameter.ubuntu` (in `modules/k8s-nodes`) returns the current Ubuntu 24.04 AMI ID from Canonical's public parameter.
5. **Build the dependency graph.** Every reference such as `vpc_id = module.network.vpc_id` is an edge: the security groups must wait for the VPC. Terraform never uses file order; the graph alone decides the order.
6. **Compare** the desired configuration with state and print a symbol per resource: `+` create, `~` update in place, `-/+` replace, `-` destroy. The first run shows about 45 resources to add. Values not known until AWS creates them, like instance IPs, are shown as `(known after apply)`.
7. **Save the plan** to `tfplan` and release the lock.

A saved plan matters in a team: you review exactly that file, and `apply tfplan` executes exactly it. If anything changed in between, apply refuses ("Saved plan is stale") instead of doing something nobody reviewed.

## Stage 3: apply, in the order resources are created

Command: `run.sh apply` runs `terraform apply tfplan`. Expect 4-6 minutes.

Apply locks the state again, then walks the graph. A resource starts **as soon as everything it references is finished**, with up to 10 operations at a time (`-parallelism=10`). There are no fixed "waves", but the dependencies produce this order on a first run:

| Wave | Resources that start | Waiting for | Typical time |
| --- | --- | --- | --- |
| 1 | `aws_vpc`, `tls_private_key` (ED25519, created locally), `aws_secretsmanager_secret` | nothing | seconds |
| 2 | Internet gateway, 3 subnets (one per AZ), security groups `nodes` and `nlb`, `aws_key_pair`, secret version (the private key) | VPC; key; secret | seconds |
| 3 | Route table; all security group rules (the `for_each` rules get one copy per admin CIDR); target groups `api` and `ingress` | IGW; SGs; VPC | seconds |
| 4 | Route table associations; **3 control-plane + 3 worker instances**; **NLB** | subnets + SG + key pair; subnets + NLB SG | instances \~30 s, NLB 2-3 min |
| 5 | Target group attachments (3 to `api`, 3 to `ingress`); listeners `:6443` and `:80` | instance IDs + TGs; NLB + TGs | seconds |
| 6 | `local_file.ansible_group_vars` | NLB DNS name, secret name, VPC CIDR | instant |

What happens to each instance as it's created:

- **Subnet**: `subnet_ids[count.index % 3]`. Node 1 goes to AZ a, node 2 to b, node 3 to c.
- **Tags**: `Name` (k8s-ha-dev-cp-1 …), `Role` (control-plane / worker), and `Bootstrap = "true"` on cp-1 only. Plus the provider's default tags `Project=k8s-ha`, `Environment=dev`. These tags are how Ansible finds and groups the hosts later.
- **Disk and metadata**: an encrypted 20 GiB gp3 root disk, and IMDSv2 required.

If one resource fails, for example `InstanceLimitExceeded`, Terraform stops starting new work and lets running operations finish. It saves everything that succeeded to state and prints the error. Fix the cause and run plan and apply again: only the missing parts are created.

At the end, apply writes the new state to S3 (a new object version), releases the lock, and prints the outputs.

## Inside each module

A module is a function: inputs (`variables.tf`), body (`main.tf`), return values (`outputs.tf`). The caller sees only the outputs. `k8s-nodes` is called twice, once per role, which is the point of modules: one tested definition, many uses.

| Module | Called as | Inputs from the caller | Creates | Outputs used by |
| --- | --- | --- | --- | --- |
| `network` | `module.network` | name, vpc\_cidr, az\_count = 3 | VPC, IGW, 3 public subnets, route table + 3 associations | `vpc_id`, `vpc_cidr`, `public_subnet_ids` → security\_groups, k8s-nodes, nlb |
| `ssh-key` | `module.ssh_key` | name, secret path `k8s-ha/dev` | ED25519 key, EC2 key pair, Secrets Manager secret + version | `key_name` → k8s-nodes; `secret_name` → hand-off file, outputs |
| `security-groups` | `module.security_groups` | vpc\_id, vpc\_cidr, admin\_cidrs, app\_client\_cidrs, ingress port | SGs `nodes` and `nlb` + 10 rules | `nodes_sg_id` → k8s-nodes; `nlb_sg_id` → nlb |
| `k8s-nodes` | `module.control_planes` | role `control-plane`, count 3, t3.medium | 3 instances (+ Bootstrap tag on #1) | `instance_ids` → nlb listener `api`; `nodes` → outputs |
| `k8s-nodes` | `module.workers` | role `worker`, count 3, t3.small | 3 instances | `instance_ids` → nlb listener `ingress` |
| `nlb` | `module.nlb` | vpc, subnets, SG, a `listeners` map | NLB, one target group + listener per map entry, one attachment per target | `dns_name` → hand-off file, outputs |

The `nlb` module is driven by data. Its `listeners` map has two entries: `api`, port 6443 to the control planes, and `ingress`, port 80 to workers on 30080. A third listener would need only another map entry, with no change to the module. Every target group sets `preserve_client_ip = false`, so a control plane that calls the NLB and lands on itself (hairpin) still works. kubeadm needs exactly that during join.

## Stage 4: outputs and the hand-off to Ansible

Terraform passes three things to Ansible, and none of them is a file of IP addresses:

1. **Tags on the instances.** Ansible's `aws_ec2` inventory reads them live from AWS, so the inventory always matches reality, even after an instance is replaced.
2. **`ansible/inventories/dev/group_vars/all/terraform.yml`**, written by `local_file.ansible_group_vars` from the template `templates/terraform_vars.yml.tftpl`. It holds only non-secret values: `aws_region`, `project`, `env_name`, `api_endpoint` (the NLB DNS name), `ingress_node_port`, `ssh_key_secret_name`, `vpc_cidr`. It's git-ignored, because it's regenerated on every apply.
3. **The SSH private key, in Secrets Manager.** `run.sh fetch-key` reads `terraform output -raw ssh_key_secret_name`, calls `aws secretsmanager get-secret-value`, and writes `~/.ssh/k8s-ha-dev.pem` with mode 600. IAM decides who may fetch it, and the key is never in Git or the project folder.

Useful output commands:

```bash
terraform -chdir=terraform/live/dev output                      # all outputs
terraform -chdir=terraform/live/dev output -raw nlb_dns         # one value, no quotes (for scripts)
terraform -chdir=terraform/live/dev output -json control_planes # structured
terraform -chdir=terraform/live/dev state list                  # every resource address in state
terraform -chdir=terraform/live/dev state show 'module.control_planes.aws_instance.this[0]'
```

## Later runs: changes, scaling and drift

Every later `plan` repeats Stage 2 against the existing state, so Terraform changes only the difference.

| You change | What plan shows | Why |
| --- | --- | --- |
| Nothing (but Canonical released a new AMI) | No changes | `lifecycle { ignore_changes = [ami] }` stops a new image from replacing running Kubernetes nodes |
| `worker_count = 4` | +1 instance (`module.workers.aws_instance.this[3]`, AZ a again), +1 target group attachment | `count` grows; the existing 3 workers are untouched |
| Your home IP changed | The SSH / NodePort / port 80 rules are replaced | `data.http.my_ip` returns a new value, and the `for_each` rule keys change |
| `worker_instance_type = "t3.medium"` | The 3 workers are updated in place (stop, resize, start) | The instance type can change without replacing the instance, but each worker restarts. Drain first in production |
| Someone edited a security group in the console | Plan shows Terraform reverting it | Refresh found drift; Terraform restores the code's version. Code is the source of truth |
| A rename inside a module | Destroy + create | The resource address changed. Add a `moved {}` block so Terraform knows it's the same object |

After adding a worker, run Ansible (`./scripts/run.sh configure`). The dynamic inventory finds the new instance by its tags, and the roles prepare and join only that node.

## Stage 5: destroy

Command: `./scripts/run.sh destroy` runs `terraform destroy`, then deletes `~/.ssh/k8s-ha-dev.pem` and the fetched kubeconfig.

Destroy walks the same graph **backwards**: anything that depends on something else goes first.

1. `local_file` (the hand-off file is deleted), the listeners, the target group attachments.
2. The target groups and the NLB, and in parallel all 6 instances (terminating takes about 1 minute).
3. Security group rules, the security groups, the key pair, the Secrets Manager secret (`recovery_window_in_days = 0`, so it's deleted at once and the name can be reused immediately).
4. Route table associations, the route table, subnets, the internet gateway, and finally the VPC.

The state file stays in S3, now empty, and every older version is kept by bucket versioning. The bootstrap bucket isn't touched. Remove it only when you're completely done: `terraform -chdir=terraform/bootstrap destroy`.

The Ansible vault password and `vault.yml` are also kept, so the next build reuses the same secrets.

## Troubleshooting by stage

| Stage | Error | Cause and fix |
| --- | --- | --- |
| bootstrap | `BucketAlreadyExists` | The name is taken. It's global; add a suffix in `bootstrap/main.tf` |
| init | `No backend.hcl` / `Missing required argument "bucket"` | Run `./scripts/run.sh bootstrap` first |
| init | `Inconsistent dependency lock file` | A provider constraint changed. Run `terraform init -upgrade` and commit `.terraform.lock.hcl` |
| plan | `Error acquiring the state lock` | Someone else, or a crashed run, holds the lock. Wait, or `terraform force-unlock <LOCK_ID>` if you're sure nothing is running |
| plan | `Invalid value for variable` | A validation rule, for example an even `control_plane_count` |
| plan | `UnauthorizedOperation` / `AccessDenied` | Your IAM user lacks EC2, ELB, Secrets Manager or SSM rights. Check with `aws sts get-caller-identity` |
| apply | `Saved plan is stale` | State changed after the plan. Run `run.sh plan` again |
| apply | `VcpuLimitExceeded` | Account vCPU quota. Request an increase or use smaller types |
| apply | `InvalidKeyPair.Duplicate` | A key pair with that name exists from an older build. Delete it in the EC2 console |
| destroy | Security group `DependencyViolation` | An ENI is still attached (the NLB is deleting). Wait 1 minute and run destroy again |
| any | Plan wants to replace everything | Wrong `backend.hcl` key, or the wrong folder. Terraform is looking at another (or empty) state |
