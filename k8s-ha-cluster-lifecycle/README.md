# Django on highly available Kubernetes (AWS)

The same Django app as the minikube exercise, deployed to an HA cluster in three ways:

| Phase | Folder | Infrastructure | Configuration | Run from |
|---|---|---|---|---|
| 1 | `phase1-scripts/` | AWS CLI (PowerShell) | bash scripts over SSH | Windows PowerShell |
| 2 | `phase2-terraform-ansible/` | Terraform modules, S3 remote state | Ansible roles, dynamic inventory, Ansible Vault | WSL (Ubuntu) |
| 3 | `phase3-eks/` | Terraform modules in 2 stacks (infra, platform) | Helm via Terraform; secrets via Secrets Manager + External Secrets | PowerShell or WSL |

All three use the **same app** (`app/`) and the **same Kubernetes manifests** (`k8s/`).

## Architecture (Phases 1 and 2)

```
                         your PC (Windows)
                               |
                 http://foo.bar.com/demo/  (port 80)
                 kubectl  (port 6443)
                               |
                 +-------------v--------------+
                 |  Network Load Balancer      |   1 NLB, 3 AZs, cross-zone on
                 |  :6443 -> control planes    |
                 |  :80   -> workers :30080    |
                 +------+---------------+------+
                        |               |
     us-west-2a         |  us-west-2b   |       us-west-2c
   +-----------+   +-----------+   +-----------+
   | cp-1      |   | cp-2      |   | cp-3      |   API server + etcd member
   | etcd      |   | etcd      |   | etcd      |   (quorum 2 of 3)
   +-----------+   +-----------+   +-----------+
   | worker-1  |   | worker-2  |   | worker-3  |   1 app pod + ingress-nginx
   | app pod   |   | app pod   |   | app pod   |   spread by zone
   +-----------+   +-----------+   +-----------+
```

What makes it highly available:

| Failure / event | What keeps the app up |
|---|---|
| One control plane dies | 2 of 3 etcd members keep quorum; the NLB stops sending API traffic to the dead node |
| One worker / one AZ dies | 2 app pods remain; the Deployment recreates the 3rd on a healthy node |
| Node patching (`kubectl drain`) | PodDisruptionBudget `minAvailable: 2` lets only one app pod go at a time |
| App update | Rolling update with `maxUnavailable: 0`; readiness probe gates traffic |
| More load | Add workers (count variable) and raise `replicas` |

Why **3** control planes and not 2: etcd needs a majority. With 2 members the majority is 2, so losing either one stops the cluster. That makes 2 *less* available than 1. Always use an odd number.

## What changed compared with minikube

| File | Change | Why |
|---|---|---|
| `k8s/deployment.yaml` | `replicas: 3`, `topologySpreadConstraints` by zone and node | One pod per zone |
| | readiness and liveness probes on `/demo/` | No traffic to pods that aren't ready; restart hung ones |
| | resource requests/limits, `maxUnavailable: 0` | Scheduling and safe rollouts |
| | image tag `v2` | The page now shows which pod served it |
| `k8s/pdb.yaml` | new | Safe node maintenance |
| `app/devops/demo/views.py` + template | shows the pod name | See load balancing when refreshing |
| `app/devops/devops/settings.py` | `demo` in `INSTALLED_APPS`; env overrides | Fixes from the first review |

**Step 1 is the same for every phase.** Build and push `a1abhinavsingh/python-sample-app-demo:v2`, because the manifests now use `v2`:

```powershell
cd phase1-scripts\powershell
.\step1-build-push-image.ps1
```

## Approximate cost while running (us-west-2, on-demand)

| Phase | Main items | Approx. |
|---|---|---|
| 1 and 2 | 3 × t3.medium, 3 × t3.small, 1 NLB, 6 public IPv4, 120 GiB gp3 | ~$0.25 per hour |
| 3 | EKS control plane, 3 × t3.medium, 1 NAT gateway, 1 NLB | ~$0.35 per hour |

These are rough estimates. Check the AWS Pricing Calculator, and **always run the Step 8 cleanup** when you finish.

## Execution walkthroughs

Step-by-step explanations of how the Phase 2 and Phase 3 projects run: [docs/README.md](docs/README.md)

## Phase guides

- [Phase 1: PowerShell + SSH scripts](phase1-scripts/README.md)
- [Phase 2: Terraform + Ansible](phase2-terraform-ansible/README.md)
- [Phase 3: Terraform + EKS](phase3-eks/README.md)
