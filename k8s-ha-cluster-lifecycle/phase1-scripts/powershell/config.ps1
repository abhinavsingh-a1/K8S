# Settings for all Phase 1 scripts. Edit these, nothing else.

$Region          = "us-west-2"
$Project         = "k8s-ha"                 # prefix for every AWS resource name / tag

# SSH key pair (created by step2 if it doesn't exist in AWS)
$KeyName         = "k8s-ha-key"
$KeyPath         = "$env:USERPROFILE\.ssh\k8s-ha-key.pem"

# Cluster size. 3 control planes = etcd survives 1 failure (quorum 2 of 3).
$ControlPlaneCount = 3
$WorkerCount       = 3
$ControlPlaneType  = "t3.medium"            # 2 vCPU / 4 GiB
$WorkerType        = "t3.small"             # 2 vCPU / 2 GiB
$RootVolumeGiB     = 20

# Software versions
$K8sMinor          = "v1.35"                # package repo pkgs.k8s.io/core:/stable:/v1.35
$PodCidr           = "10.244.0.0/16"        # required by Flannel
$FlannelVersion    = "latest"               # or e.g. "v0.27.4"
$IngressVersion    = "controller-v1.13.0"   # ingress-nginx git tag

# Application image (Docker Hub, public)
$Image             = "a1abhinavsingh/python-sample-app-demo:v2"
$AppHost           = "foo.bar.com"

# Paths (relative to this folder)
$Root        = Split-Path -Parent $PSScriptRoot          # phase1-scripts
$RepoRoot    = Split-Path -Parent $Root                  # k8s-ha-project
$StateFile   = Join-Path $Root "state.json"
$LogDir      = Join-Path $Root "logs"
$NodeScripts = Join-Path $Root "node"
$Manifests   = Join-Path $RepoRoot "k8s"
$AppDir      = Join-Path $RepoRoot "app"
