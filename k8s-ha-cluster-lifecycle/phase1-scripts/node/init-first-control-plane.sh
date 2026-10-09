#!/usr/bin/env bash
# Step 5 - runs on the FIRST control plane only (k8s-cp-1).
# Creates the HA cluster behind the load balancer endpoint, installs
# Flannel, and writes the join commands for the other nodes.
#
# Usage: sudo bash init-first-control-plane.sh <api-endpoint-dns> [pod-cidr] [flannel-version]
set -euo pipefail

ENDPOINT="${1:?usage: init-first-control-plane.sh <api-endpoint-dns> [pod-cidr] [flannel-version]}"
POD_CIDR="${2:-10.244.0.0/16}"
FLANNEL_VERSION="${3:-latest}"
USER_HOME="/home/${SUDO_USER:-ubuntu}"
OWNER="${SUDO_USER:-ubuntu}"

if [[ $EUID -ne 0 ]]; then
  echo "Run with sudo." >&2
  exit 1
fi

log() { echo -e "\n==> [$(hostname)] $*"; }

PRIVATE_IP=$(hostname -I | awk '{print $1}')

if [[ -f /etc/kubernetes/admin.conf ]]; then
  log "Cluster already initialised on this node - skipping kubeadm init"
else
  log "Waiting until the load balancer endpoint resolves: ${ENDPOINT}"
  until getent hosts "${ENDPOINT}" > /dev/null; do sleep 5; done

  log "kubeadm init (control-plane endpoint ${ENDPOINT}:6443)"
  # --control-plane-endpoint : all nodes talk to the API through the NLB,
  #                            so any control plane can fail.
  # --upload-certs           : stores the CA/etcd certs encrypted in the
  #                            cluster so other control planes can join.
  kubeadm init \
    --control-plane-endpoint "${ENDPOINT}:6443" \
    --apiserver-advertise-address "${PRIVATE_IP}" \
    --apiserver-cert-extra-sans "${ENDPOINT}" \
    --pod-network-cidr "${POD_CIDR}" \
    --upload-certs
fi

log "kubeconfig for ${OWNER}"
mkdir -p "${USER_HOME}/.kube"
cp /etc/kubernetes/admin.conf "${USER_HOME}/.kube/config"
chown -R "${OWNER}:${OWNER}" "${USER_HOME}/.kube"
export KUBECONFIG=/etc/kubernetes/admin.conf

log "Installing Flannel (pod network ${POD_CIDR})"
if [[ "${FLANNEL_VERSION}" == "latest" ]]; then
  FLANNEL_URL="https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml"
else
  FLANNEL_URL="https://github.com/flannel-io/flannel/releases/download/${FLANNEL_VERSION}/kube-flannel.yml"
fi
kubectl apply -f "${FLANNEL_URL}"
kubectl -n kube-flannel rollout status daemonset/kube-flannel-ds --timeout=180s

log "Writing join commands"
JOIN_CMD=$(kubeadm token create --ttl 4h --print-join-command)
# The certificate key expires after 2 hours; rerun this script to refresh it.
CERT_KEY=$(kubeadm init phase upload-certs --upload-certs 2>/dev/null | tail -1)

echo "${JOIN_CMD}" > "${USER_HOME}/join-worker.sh"
echo "${JOIN_CMD} --control-plane --certificate-key ${CERT_KEY}" > "${USER_HOME}/join-control-plane.sh"
chmod 600 "${USER_HOME}"/join-*.sh
chown "${OWNER}:${OWNER}" "${USER_HOME}"/join-*.sh

kubectl get nodes -o wide
log "First control plane ready. Join files: ${USER_HOME}/join-control-plane.sh, ${USER_HOME}/join-worker.sh"
