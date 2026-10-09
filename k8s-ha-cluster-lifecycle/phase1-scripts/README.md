# Phase 1: PowerShell + SSH scripts

PowerShell on Windows creates the AWS resources with the AWS CLI and drives the nodes over SSH. The bash scripts in `node/` do the work on the VMs. You can also run them yourself after `ssh`, exactly as in the manual exercise.

```
phase1-scripts/
├── powershell/                 run on Windows
│   ├── config.ps1              ← all settings (region, counts, versions)
│   ├── lib.ps1                 helpers (aws, ssh, scp, state.json)
│   ├── step1-build-push-image.ps1
│   ├── step2-network.ps1       key pair, security groups
│   ├── step3-instances.ps1     6 EC2 instances + NLB
│   ├── step4-prepare-nodes.ps1 containerd/kubeadm on all nodes (parallel)
│   ├── step5-create-cluster.ps1 kubeadm init, join 2 CPs + 3 workers
│   ├── step6-deploy-app.ps1
│   ├── step7-ingress.ps1
│   ├── step8-cleanup.ps1       -Action Stop | Start | Destroy
│   └── status.ps1              debug overview at any time
├── node/                       copied to every VM, run there
│   ├── prepare-node.sh
│   ├── init-first-control-plane.sh
│   ├── join-node.sh
│   ├── deploy-app.sh
│   ├── install-ingress.sh
│   └── debug.sh
├── state.json                  created by the scripts (IDs, IPs, NLB)
└── logs/                       per-node logs from step 4
```

## Prerequisites (Windows)

| Tool | Check | Install |
|---|---|---|
| AWS CLI v2 | `aws --version` → `aws-cli/2.x` | MSI from AWS |
| AWS credentials | `aws sts get-caller-identity` | `aws configure` (access key of an IAM user with EC2 + ELB rights) |
| OpenSSH client | `ssh -V` | Windows Settings → Optional features → OpenSSH Client |
| curl | `curl.exe --version` | Built into Windows 10/11 |
| Docker CLI (Step 1 only) | `docker --version` | Docker Desktop, or minikube's Docker |
| kubectl (optional) | `kubectl version --client` | You already have it from minikube |

Allow the scripts to run in this window:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
cd <path>\k8s-ha-project\phase1-scripts\powershell
```

Use an **Administrator** PowerShell for Step 7 and for `Destroy`, so the hosts file can be updated.

## Run it step by step

| Step | Command | What to check afterwards |
|---|---|---|
| 1 | `.\step1-build-push-image.ps1` | Tag `v2` visible on Docker Hub, repository Public |
| 2 | `.\step2-network.ps1` | 2 security groups; key at `%USERPROFILE%\.ssh\k8s-ha-key.pem` |
| 3 | `.\step3-instances.ps1` | 6 instances in 3 AZs; NLB DNS name printed |
| 4 | `.\step4-prepare-nodes.ps1` | Every node `OK`; on failure read `logs\<node>-prepare.log` |
| 5 | `.\step5-create-cluster.ps1` | 6 nodes `Ready`; API targets `healthy` on the NLB |
| 6 | `.\step6-deploy-app.ps1` | 3 pods on 3 different workers; `HTTP 200` on every worker's `:30007` |
| 7 | `.\step7-ingress.ps1` | `HTTP 200` through the NLB; `http://foo.bar.com/demo/` in the browser |
| 8 | `.\step8-cleanup.ps1 -Action Destroy` | Leftovers check prints nothing |

Every step is safe to rerun. Existing resources are reused, and nodes that already joined are skipped.

### Doing Steps 4-7 by hand over SSH (for practice)

```powershell
$key = "$env:USERPROFILE\.ssh\k8s-ha-key.pem"
Get-Content ..\state.json | ConvertFrom-Json | Select-Object -ExpandProperty Nodes | Format-Table Name, PublicIp, PrivateIp, Az
scp -i $key -r ..\node ..\..\k8s ubuntu@<node-ip>:~/
ssh -i $key ubuntu@<node-ip>
```

On each node:
```bash
sudo bash ~/node/prepare-node.sh k8s-ha-cp-1 v1.35        # use the node's own name
```

On cp-1 only:
```bash
sudo bash ~/node/init-first-control-plane.sh <nlb-dns-name>
cat ~/join-control-plane.sh ~/join-worker.sh
```

On cp-2, then cp-3 (one at a time), then each worker:
```bash
sudo bash ~/node/join-node.sh control-plane <paste join-control-plane line>
sudo bash ~/node/join-node.sh worker <paste join-worker line>
```

Back on cp-1:
```bash
bash ~/node/deploy-app.sh
bash ~/node/install-ingress.sh
bash ~/node/debug.sh
```

## kubectl from Windows

Step 5 saves a kubeconfig whose server is the NLB, so kubectl from your PC goes through the HA endpoint:

```powershell
$env:KUBECONFIG = "<path>\phase1-scripts\kubeconfig"
kubectl get nodes -L topology.kubernetes.io/zone
```

## Test the high availability

**1. Lose a control plane.** kubectl keeps working; etcd keeps quorum.
```powershell
$s = Get-Content ..\state.json | ConvertFrom-Json
$cp2 = ($s.Nodes | Where-Object Name -eq "k8s-ha-cp-2").InstanceId
aws ec2 stop-instances --instance-ids $cp2 --region us-west-2
kubectl get nodes           # cp-2 NotReady after ~40 s, commands still work
.\status.ps1                # NLB shows cp-2 unhealthy; etcd member list still 3, 2 started
aws ec2 start-instances --instance-ids $cp2 --region us-west-2
```
Stopping a **second** control plane makes the API stop answering, because quorum is lost. That's the point of an odd count.

**2. Patch a worker (rolling maintenance).**
```powershell
kubectl drain k8s-ha-worker-1 --ignore-daemonsets --delete-emptydir-data
kubectl get pods -o wide     # the pod moved; never fewer than 2 ready (PDB)
kubectl uncordon k8s-ha-worker-1
```

**3. Lose a zone.** Stop worker-2 (us-west-2b). The page keeps loading; the 3rd pod is recreated in another zone after about 5 minutes (pod eviction timeout).

**4. Rolling update.** Change something, build and push `:v3`, then:
```powershell
kubectl set image deployment/sample-python-app python-app=a1abhinavsingh/python-sample-app-demo:v3
kubectl rollout status deployment/sample-python-app
```
Keep refreshing the browser meanwhile. There are no errors, because `maxUnavailable: 0` and the readiness probe keep ready pods serving.

## Debugging

| Symptom | Where to look | Likely cause |
|---|---|---|
| Step 4 node `FAILED` | `logs\<node>-prepare.log` | apt or network hiccup; rerun step 4 |
| `kubeadm init` stuck at "waiting for the kubelet" | `ssh` to cp-1: `sudo journalctl -u kubelet -n 50` | cgroup driver; check `/etc/containerd/config.toml` |
| init/join timeout talking to `<nlb>:6443` | `.\status.ps1` → API target health | NLB security group missing the 6443 rule (rerun step 2); targets still `initial` |
| `join` says the certificate key expired | | The key lasts 2 hours. Rerun `.\step5-create-cluster.ps1`; it refreshes the key and skips nodes that already joined |
| Pods all on one worker | `kubectl get nodes -L topology.kubernetes.io/zone` | Zone label missing; check `/etc/default/kubelet` on the node |
| NLB `:80` times out | `.\status.ps1` → ingress targets | Your IP changed. Rerun `.\step2-network.ps1` |
| SSH `REMOTE HOST IDENTIFICATION HAS CHANGED` | | `ssh-keygen -R <ip>` |
| Anything else | `bash ~/node/debug.sh` on a control plane | Read the warnings section |

## Stop, start and destroy

```powershell
.\step8-cleanup.ps1 -Action Stop       # pause; disks + NLB still cost a little
.\step8-cleanup.ps1 -Action Start      # new public IPs saved to state.json
.\step8-cleanup.ps1 -Action Destroy    # everything (add -DeleteKey for the key pair)
```
