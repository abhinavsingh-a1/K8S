# Phase 3 Terraform (EKS): Execution from Start to End

Oct 9, 2026 · @Abhinav

Phase 3 runs Terraform three times: a one-time bootstrap, stack `10-infra` (network + EKS), then stack `20-platform` (secrets + cluster add-ons), which reads stack 10's outputs from S3. Then a kubectl step deploys the app. The sections below follow that order.

## The big picture

&#91;embedded content: bootstrap, two stacks, four modules, two state files\]

Each stack has its own state file and its own lock. Destroy runs in exactly the reverse order: deploy objects, then 20-platform, then 10-infra.

## Why two stacks, and what each one reads

A **stack** is one root module with its own state file. Phase 3 splits the work in two, for three reasons:

1. **The Helm provider needs a cluster that already exists.** Its connection settings (endpoint, CA certificate) are cluster outputs. In a single stack, the first `plan` has no cluster to connect to. With two stacks, `20-platform` reads finished values from `10-infra`.
2. **Blast radius.** A mistake while bumping a Helm chart can only touch `20-platform`'s state, not the VPC or the EKS cluster.
3. **Speed and ownership.** `10-infra` takes about 15-20 minutes and rarely changes. `20-platform` takes minutes and changes often. In a company, different teams often own them.

| File | Stack | Purpose |
| --- | --- | --- |
| `bootstrap/main.tf` | bootstrap | State bucket; outputs `backend_hcl_infra`, `backend_hcl_platform`, `state_bucket` |
| `live/dev/10-infra/versions.tf` | 10-infra | `aws ~> 5.95` (the EKS module v20 requires < 6.0), `http`, an empty `backend "s3" {}`, default tags incl. `Stack = 10-infra` |
| `live/dev/10-infra/backend.hcl` | 10-infra | key `dev/10-infra.tfstate` (written by `run bootstrap`) |
| `live/dev/10-infra/main.tf` | 10-infra | Calls `modules/network` and `modules/eks-cluster` |
| `live/dev/10-infra/terraform.tfvars` | 10-infra | Region, CIDR, Kubernetes version, node size and count |
| `live/dev/10-infra/outputs.tf` | 10-infra | The **contract** for stack 20: region, cluster name, endpoint, CA data, allowed CIDRs |
| `live/dev/20-platform/versions.tf` | 20-platform | `aws`, `helm ~> 2.17`, `random`; the AWS and Helm providers are configured **from stack 10's outputs** |
| `live/dev/20-platform/main.tf` | 20-platform | `terraform_remote_state`, then calls `modules/app-secrets` and `modules/platform-addons` |
| `live/dev/20-platform/terraform.tfvars` | 20-platform | `state_bucket` (written by `run bootstrap`, git-ignored) |
| `modules/network`, `modules/eks-cluster` | (library) | Company wrappers around the community modules `terraform-aws-modules/vpc` and `/eks` |
| `modules/app-secrets`, `modules/platform-addons` | (library) | Our own modules |
| `k8s-overlay/*.yaml` | (not Terraform) | ClusterSecretStore and ExternalSecret, applied by `run deploy` |

## Stage 0: bootstrap

Command: `.\run.ps1 bootstrap` (or `./scripts/run.sh bootstrap`).

This works exactly like Phase 2: a separate root module with local state creates `k8s-ha-eks-tfstate-<account>-us-west-2`, with versioning, AES-256 encryption, a public access block and an HTTPS-only policy. The difference is in the outputs. There are two backend snippets, one per stack, with different `key` values, so the stacks never share a state file:

```hcl
# 10-infra/backend.hcl                    # 20-platform/backend.hcl
key = "dev/10-infra.tfstate"             key = "dev/20-platform.tfstate"
```

The script also writes `20-platform/terraform.tfvars` with `state_bucket = "..."`, because stack 20 needs the bucket name twice: once for its own backend, and once to read stack 10's state. The PowerShell version writes these files as UTF-8 **without BOM**, because Terraform can't parse a file that starts with a byte-order mark.

## Stack 10-infra: network and cluster

Command: `.\run.ps1 infra` runs `init`, `validate`, `plan -out=tfplan`, asks `yes`, then runs `apply tfplan`.

### init

As in Phase 2, `init` connects the S3 backend (key `dev/10-infra.tfstate`). The difference is that two module calls point to the **Terraform Registry**:

- `terraform-aws-modules/vpc/aws ~> 5.21`, called inside `modules/network`.
- `terraform-aws-modules/eks/aws ~> 20.37`, called inside `modules/eks-cluster`. It brings its own submodules: `kms`, `eks-managed-node-group`, `_user_data`.

`init` downloads them into `.terraform/modules/`. It also installs the providers those modules declare (`tls`, `time`, `cloudinit`, `null`), even though our root never mentions them, and records everything in `.terraform.lock.hcl`. The `~>` constraints allow patch and minor updates of the community modules, but never a breaking major version (v21 renamed many inputs).

### plan

1. Lock `dev/10-infra.tfstate.tflock`, load `terraform.tfvars`, refresh the state.
2. Read the data sources:
   - `data.http.my_ip` gives `api_allowed_cidrs = ["<your-ip>/32"]`.
   - `data.aws_availability_zones` gives the first 3 AZs.
   - Inside the EKS module: caller identity, partition, IAM policy documents.
3. Expand the module calls into about 80 resources, build the graph, and save `tfplan`.

### apply: the order inside the modules

| Order | Module | Resources | Time |
| --- | --- | --- | --- |
| 1 | network | VPC; then IGW, 3 private /20 subnets, 3 public /24 subnets, 1 Elastic IP | seconds |
| 2 | network | **NAT gateway** in the first public subnet (needs EIP + IGW); route tables; `0.0.0.0/0` routes (public to IGW, private to NAT); associations | 1-2 min |
| 3 | eks-cluster (parallel with 1-2) | Cluster IAM role + policy attachments; **KMS key** for Secrets encryption; CloudWatch log group (7-day retention); cluster and node security groups + rules | seconds |
| 4 | eks-cluster | **`aws_eks_cluster`**: AWS builds the HA control plane in the 3 private subnets. API endpoint public (your IP only) + private | **8-12 min** |
| 5 | eks-cluster | OIDC provider; **access entry** + admin policy for the identity running Terraform (`authentication_mode = API`) | seconds |
| 6 | eks-cluster | Add-ons with `before_compute = true`: **vpc-cni** (pods get VPC IPs) and **eks-pod-identity-agent** | 1-2 min |
| 7 | eks-cluster | Node group IAM role (worker, CNI, ECR-read policies); launch template (encrypted 30 GiB gp3, IMDSv2); **`aws_eks_node_group`**: an Auto Scaling group spreads 3 t3.medium nodes over the 3 private subnets, and they join on their own | 3-5 min |
| 8 | eks-cluster | The remaining add-ons, **coredns** and **kube-proxy**, which need nodes to run on | 1-2 min |
| 9 | root | Outputs: region, cluster name, endpoint, CA data, CIDRs, `configure_kubectl` command | instant |

Why `before_compute` matters: if the nodes joined before the VPC CNI existed, they would stay `NotReady` with no pod network. The module orders add-ons around the node group for exactly that reason.

When apply ends, `aws eks update-kubeconfig ...` followed by `kubectl get nodes -L topology.kubernetes.io/zone` shows 3 Ready nodes, one per zone. On EKS, AWS sets the zone labels; on kubeadm, Ansible had to.

## Stack 20-platform: secrets and add-ons

Command: `.\run.ps1 platform`, the same init, plan, `yes`, apply cycle. Expect 3-5 minutes.

### init and plan: reading stack 10 first

1. `init` connects to `dev/20-platform.tfstate` and installs `aws`, `helm ~> 2.17` and `random`. Helm 3.x changed the provider block syntax, so it's pinned below 3.
2. At plan time, Terraform first reads **`data.terraform_remote_state.infra`**, which is stack 10's state file in S3. Only its **outputs** are visible, which is why `10-infra/outputs.tf` is a contract: renaming an output there breaks stack 20.
3. With those values, the providers are configured:
   - **AWS**: the region comes from stack 10.
   - **Helm**: `host` = the cluster endpoint, `cluster_ca_certificate` = the decoded CA data, and an **`exec`** block that runs `aws eks get-token --cluster-name ...` whenever Helm needs to call the API. The token is short-lived and comes from your AWS identity, so no kubeconfig and no stored credentials are involved.
4. `data.aws_caller_identity` gives the account ID for the IAM policy ARN. Then the diff is computed, about 10 resources.

### apply: order

| Order | Module | Resource | What it means |
| --- | --- | --- | --- |
| 1 | app-secrets | `random_password` (50 characters) | Generated locally. Stored in state (encrypted S3), never printed |
| 2 | app-secrets | `aws_secretsmanager_secret` `k8s-ha-eks/dev/django` + version `{"DJANGO_SECRET_KEY": "..."}` | **Source of truth** for the app secret |
| 2 | app-secrets | IAM role `k8s-ha-eks-dev-external-secrets`, trusted by `pods.eks.amazonaws.com` + inline policy: `GetSecretValue` / `DescribeSecret` on `k8s-ha-eks/dev/*` only | Least privilege |
| 3 | app-secrets | **`aws_eks_pod_identity_association`**: namespace `external-secrets`, service account `external-secrets`, mapped to that role | Pods using this SA get temporary AWS credentials from the Pod Identity agent |
| 4 | platform-addons (`depends_on` app-secrets) | `helm_release.ingress_nginx` (chart 4.13.3): 2 replicas spread by zone, Service type **LoadBalancer** with the NLB annotations, `loadBalancerSourceRanges` = your IP | Helm waits until the pods are Ready |
| 4 | platform-addons | `helm_release.external_secrets` (chart 2.12.0): installs the CRDs, 2 replicas, leader election, SA name `external-secrets` | Same wait |

Why the `depends_on`: Pod Identity injects credentials **when a pod starts**. If the ESO pods started before the association existed, they would run without AWS access until restarted.

**Outside Terraform:** when Helm creates the `ingress-nginx-controller` Service of type LoadBalancer, the AWS cloud controller in EKS creates an **NLB** in the public subnets (found through the `kubernetes.io/role/elb` tag set by the network module). Terraform never sees that NLB. It's owned by the Kubernetes Service, which matters for destroy.

## After Terraform: deploy and the runtime secret flow

Command: `.\run.ps1 deploy`. It reads two values from `terraform output` of stack 20 (`region`, `app_secret_name`) and then works only with kubectl:

1. `aws eks update-kubeconfig` writes a kubeconfig entry that also uses `aws eks get-token`.
2. It applies `k8s-overlay/cluster-secret-store.yaml` with `__REGION__` replaced. The **ClusterSecretStore** `aws-secrets-manager` says: "Secrets Manager in us-west-2", with **no credentials**. ESO falls back to its pod's AWS identity, which comes from Pod Identity.
3. It applies `external-secret.yaml` with `__SECRET_NAME__` replaced. The **ExternalSecret** `django-secrets` says: "take every JSON key of `k8s-ha-eks/dev/django` and write it into the Kubernetes Secret `django-secrets`; re-check every hour".
4. It waits for both to be `Ready`. By then ESO has called `GetSecretValue` and created the Secret. EKS encrypts that Secret in etcd with the KMS key from stack 10.
5. It applies the shared manifests (`configmap`, `django-config`, `deployment`, `pdb`, `service`) and runs `rollout restart`, so the pods read `DJANGO_SECRET_KEY` through `envFrom`.
6. It applies `ingress.yaml`, waits for the NLB hostname, and curls `/demo/` with `Host: foo.bar.com`.

The secret's full path at runtime: Terraform `random_password` → Secrets Manager → (IAM role via Pod Identity) → ESO → Kubernetes Secret (KMS-encrypted in etcd) → pod environment variable → Django `settings.SECRET_KEY`. No long-lived AWS key exists anywhere in it.

## Later runs

| Change | Stack | What plan or apply does |
| --- | --- | --- |
| `node_desired_size = 4` | 10-infra | The node group's scaling config changes in place, and the ASG adds a node in the AZ with the fewest |
| `kubernetes_version = "1.35"` | 10-infra | 1. The cluster upgrades in place (about 10 min). 2. The node group gets a new AMI version and **replaces nodes one at a time** (`max_unavailable = 1`). The PDB keeps 2 app pods ready during that. Upgrade one minor version per step |
| Add-on update (`most_recent = true`) | 10-infra | Plan shows the new add-on version, and apply updates it |
| Your IP changed | 10-infra, then 20-platform | Stack 10 updates the API allow-list. Stack 20 reads the new value through remote state and updates `loadBalancerSourceRanges` |
| `ingress_nginx_chart_version` bump | 20-platform | `helm upgrade` of that release only. Pin, test in dev, then promote |
| Rotate the Django key | outside Terraform | `aws secretsmanager put-secret-value ...`, then ESO syncs within 1 hour (or force-sync), then `rollout restart`. The next stack 20 plan shows drift on the secret version; decide who owns the value (see the Phase 3 README) |
| Edit a module | both, as affected | Every stack that calls it shows the change on its next plan. Review both before applying |

Run the stacks in dependency order: 10, then 20. Stack 20 only sees stack 10's **applied** outputs, so a change planned in 10 but not applied is invisible to 20.

## Destroy: reverse order, and why

Command: `.\run.ps1 destroy`. The order is the reverse of creation, one level at a time:

1. **App objects (kubectl).** It deletes the Ingress, the ExternalSecret (which also deletes the Secret `django-secrets` it owns) and the ClusterSecretStore. If the cluster is already gone, this step is skipped.
2. **Stack 20-platform (`terraform destroy`).**
   - The Helm releases are uninstalled. Uninstalling ingress-nginx deletes its LoadBalancer Service, and the Service's finalizer makes the AWS controller **delete the NLB**.
   - Then the Pod Identity association, the IAM role and the Secrets Manager secret are deleted. `recovery_window_in_days = 0` deletes the secret immediately, so a rebuild can reuse the name.
   - The script then waits 90 seconds for AWS to remove the NLB and its network interfaces.
3. **Stack 10-infra (`terraform destroy`).** The node group goes first (instances terminate), then the add-ons, access entries, the cluster (several minutes), the IAM roles, the KMS key (scheduled for deletion; AWS enforces a 7-30 day waiting period), the log group, and finally the NAT gateway, Elastic IP, subnets and VPC.

If you destroyed stack 10 first, two things would break:

- The NLB, which Terraform doesn't know about, would still hold network interfaces in the public subnets, so the VPC deletion would hang about 20 minutes and then fail.
- Stack 20 could no longer reach the cluster to uninstall anything.

The state bucket stays. Remove it last, if ever: `terraform -chdir=terraform/bootstrap destroy`.

## Troubleshooting by stage

| Stage | Error | Cause and fix |
| --- | --- | --- |
| init | `Failed to query available provider packages ... aws ... < 6.0.0` | Someone raised the AWS provider to 6.x. The EKS module v20 needs `~> 5.95`. Keep the pin |
| init (PowerShell) | `Missing newline after argument` in `backend.hcl` | An old script version wrote a one-line file. Rerun `.\run.ps1 bootstrap` |
| 10 plan | `unsupported Kubernetes version` | The version isn't offered in this region. Check `aws eks describe-cluster-versions` |
| 10 apply | `ResourceInUseException: Cluster already exists` | A leftover from an earlier run. Delete it in the console, or import it |
| 10 apply | Node group `CREATE_FAILED`, `NodeCreationFailure` | The nodes couldn't join: usually no NAT route, or the VPC CNI is missing. Check the EKS console's Health issues for the node group |
| 20 plan | `Unable to find remote state` / outputs empty | Stack 10 isn't applied, or the wrong `state_bucket` / key |
| 20 plan | `Kubernetes cluster unreachable` | `aws` CLI not in PATH (the Helm `exec` needs it), your IP isn't allowed, or another IAM identity without an access entry |
| 20 apply | `context deadline exceeded` on a helm\_release | The pods didn't become Ready in 10 minutes. Check `kubectl -n <ns> get pods` and `describe` |
| deploy | ClusterSecretStore not Ready / `AccessDenied` | Check `aws eks list-pod-identity-associations --cluster-name k8s-ha-eks-dev`. The ESO pods must have been (re)started after the association |
| deploy | ExternalSecret `SecretSyncedError` | The secret name is wrong, or the IAM policy path doesn't match |
| destroy 10 | `DependencyViolation` on a subnet or VPC | A leftover NLB or ENI. Delete it in EC2 → Load Balancers, then rerun destroy |
| any | `Error acquiring the state lock` | Another run holds the lock. Wait, or `terraform force-unlock <ID>` in that stack's folder |
