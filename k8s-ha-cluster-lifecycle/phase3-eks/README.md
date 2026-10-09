# Phase 3: Terraform modules + Amazon EKS (enterprise layout)

AWS runs the HA control plane (API servers and etcd across 3 AZs). Terraform builds everything around it in **two layered stacks** from reusable **modules**. Secrets live in **AWS Secrets Manager** and reach the cluster through **External Secrets Operator** with **EKS Pod Identity**, so no AWS keys are stored in the cluster.

Detailed walkthrough (execution order from start to end): `../docs/README.md`

```
phase3-eks/
├── terraform/
│   ├── bootstrap/                  one-time: S3 state bucket
│   ├── modules/
│   │   ├── network/                wraps terraform-aws-modules/vpc (3 AZs, private nodes, NAT)
│   │   ├── eks-cluster/            wraps terraform-aws-modules/eks (KMS, logs, access entries, add-ons, node group)
│   │   ├── app-secrets/            Secrets Manager secret + IAM role + Pod Identity association
│   │   └── platform-addons/        Helm: ingress-nginx (NLB), External Secrets Operator
│   └── live/dev/
│       ├── 10-infra/               stack 1: network + EKS        (state dev/10-infra.tfstate)
│       └── 20-platform/            stack 2: secrets + add-ons    (state dev/20-platform.tfstate)
├── k8s-overlay/                    EKS-only manifests: ClusterSecretStore, ExternalSecret
└── scripts/run.sh | run.ps1        bootstrap | infra | platform | deploy | test | status | destroy
```

## How Steps 1-8 map onto EKS

| Step | Where |
|---|---|
| 1 Image | Docker Hub `:v2` (Phase 1 step 1 script) |
| 2 Network | `10-infra` → module `network` |
| 3 Cluster + nodes | `10-infra` → module `eks-cluster` (control plane run by AWS; 3 managed nodes, one per AZ) |
| 4 Node setup | Nothing to do: the EKS AL2023 AMI ships containerd and kubelet |
| 5 Access | `aws eks update-kubeconfig` (access entry for the identity that ran Terraform) |
| 6 App + secrets | `20-platform` (secret, IAM, ESO), then `run deploy` (ExternalSecret + shared manifests) |
| 7 Ingress | `20-platform` → module `platform-addons` installs ingress-nginx; `run deploy` applies the Ingress |
| 8 Cleanup | `run destroy`: app objects → `20-platform` → `10-infra` |

## Prerequisites

Terraform ≥ 1.10, AWS CLI v2 (credentials with admin-level rights for learning), kubectl. Helm CLI is optional; Terraform uses its own Helm provider.

Check that the Kubernetes version in `live/dev/10-infra/terraform.tfvars` is in **standard** support:
```powershell
aws eks describe-cluster-versions --region us-west-2 --query "clusterVersions[].[clusterVersion,versionStatus]" --output table
```

## Run it (PowerShell; in WSL use `./scripts/run.sh <command>`)

```powershell
cd phase3-eks\scripts
.\run.ps1 bootstrap    # state bucket + backend.hcl files
.\run.ps1 infra        # plan -> type yes -> apply   (~15-20 min)
.\run.ps1 platform     # plan -> type yes -> apply   (~3-5 min)
.\run.ps1 deploy       # kubeconfig, secret sync, app, ingress, test
.\run.ps1 status
.\run.ps1 destroy      # always in this order
```

## Secrets: rotate the Django key

```powershell
$id = "k8s-ha-eks/dev/django"
aws secretsmanager put-secret-value --secret-id $id --secret-string '{\"DJANGO_SECRET_KEY\":\"<new value>\"}'
kubectl annotate externalsecret django-secrets force-sync=$(Get-Date -UFormat %s) --overwrite   # sync now instead of within 1 h
kubectl rollout restart deployment/sample-python-app
```

Terraform created the first value with `random_password`. After a manual rotation, Terraform sees the drift on the next `plan`. In a company you either let Terraform own the value, or add `lifecycle { ignore_changes = [secret_string] }` and let a rotation process own it.

## Debugging

| Symptom | Check |
|---|---|
| `20-platform` plan: `Unable to find remote state` | Run `infra` first; `terraform.tfvars` in 20-platform must name the state bucket |
| Helm release times out | `kubectl -n ingress-nginx get pods`, `kubectl -n external-secrets get pods` |
| `ClusterSecretStore` not Ready | `kubectl describe clustersecretstore aws-secrets-manager`; `aws eks list-pod-identity-associations --cluster-name k8s-ha-eks-dev` |
| `ExternalSecret` `SecretSyncedError` | `kubectl describe externalsecret django-secrets` (AccessDenied = IAM policy path; ResourceNotFound = secret name) |
| kubectl `Unauthorized` | You're not the IAM identity that created the cluster. Add an access entry (`admin_access_entries`) |
| kubectl timeout | Your IP changed. Re-apply `10-infra` |
| Destroy of `10-infra` hangs on the VPC | A load balancer is left over. Delete it in the EC2 console, then retry |
