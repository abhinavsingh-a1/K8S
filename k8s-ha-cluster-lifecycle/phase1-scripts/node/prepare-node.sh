#!/usr/bin/env bash
# Step 4 - runs on EVERY node (control planes and workers).
# Installs containerd, kubelet, kubeadm, kubectl, crictl and labels the
# node with its availability zone so pods can be spread across zones.
#
# Usage: sudo bash prepare-node.sh <hostname> [k8s-minor-version]
# Example: sudo bash prepare-node.sh k8s-cp-1 v1.35
set -euo pipefail

NEW_HOSTNAME="${1:?usage: prepare-node.sh <hostname> [k8s-minor-version]}"
K8S_MINOR="${2:-v1.35}"

if [[ $EUID -ne 0 ]]; then
  echo "Run with sudo." >&2
  exit 1
fi

log() { echo -e "\n==> [$(hostname)] $*"; }

log "Setting hostname to ${NEW_HOSTNAME}"
hostnamectl set-hostname "${NEW_HOSTNAME}"

log "Disabling swap"
swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab

log "Loading kernel modules and network settings"
cat > /etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

cat > /etc/sysctl.d/k8s.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system > /dev/null

log "Installing containerd"
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y -q containerd apt-transport-https ca-certificates curl gpg

mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd

cat > /etc/crictl.yaml <<EOF
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
EOF

log "Installing kubelet, kubeadm, kubectl, cri-tools (${K8S_MINOR})"
mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL "https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/Release.key" \
  | gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/ /" \
  > /etc/apt/sources.list.d/kubernetes.list
apt-get update -q
apt-mark unhold kubelet kubeadm kubectl cri-tools > /dev/null 2>&1 || true
apt-get install -y -q kubelet kubeadm kubectl cri-tools
apt-mark hold kubelet kubeadm kubectl cri-tools

log "Reading AWS instance metadata (IMDSv2)"
TOKEN=$(curl -sS -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
md() { curl -sS -H "X-aws-ec2-metadata-token: ${TOKEN}" "http://169.254.169.254/latest/meta-data/$1"; }
AZ=$(md placement/availability-zone)
REGION=$(md placement/region)
TYPE=$(md instance-type)
PRIVATE_IP=$(md local-ipv4)
echo "zone=${AZ} region=${REGION} type=${TYPE} ip=${PRIVATE_IP}"

# kubeadm has no cloud provider here, so nothing sets zone labels for us.
# kubelet is allowed to set these well-known labels on its own node.
cat > /etc/default/kubelet <<EOF
KUBELET_EXTRA_ARGS="--node-ip=${PRIVATE_IP} --node-labels=topology.kubernetes.io/zone=${AZ},topology.kubernetes.io/region=${REGION},node.kubernetes.io/instance-type=${TYPE}"
EOF

systemctl enable kubelet

log "Verification"
echo "containerd:     $(systemctl is-active containerd)"
echo "SystemdCgroup:  $(grep -c 'SystemdCgroup = true' /etc/containerd/config.toml) line(s) = true"
echo "ip_forward:     $(sysctl -n net.ipv4.ip_forward)"
echo "kubeadm:        $(kubeadm version -o short)"
echo "crictl:         $(crictl --version)"
crictl info > /dev/null && echo "crictl info:    OK"
echo
echo "kubelet will restart in a loop until kubeadm init/join runs. That is expected."
log "Node prepared."
