#!/usr/bin/env bash
# Step 5 - runs on k8s-cp-2, k8s-cp-3 and every worker.
# Executes the join command produced by init-first-control-plane.sh.
#
# Usage: sudo bash join-node.sh <control-plane|worker> <join command ...>
set -euo pipefail

ROLE="${1:?usage: join-node.sh <control-plane|worker> <join command ...>}"
shift

if [[ $EUID -ne 0 ]]; then
  echo "Run with sudo." >&2
  exit 1
fi

if [[ -f /etc/kubernetes/kubelet.conf ]]; then
  echo "==> [$(hostname)] already part of a cluster - skipping join"
  exit 0
fi

PRIVATE_IP=$(hostname -I | awk '{print $1}')

if [[ "${ROLE}" == "control-plane" ]]; then
  echo "==> [$(hostname)] joining as control plane"
  "$@" --apiserver-advertise-address "${PRIVATE_IP}"
  USER_HOME="/home/${SUDO_USER:-ubuntu}"
  mkdir -p "${USER_HOME}/.kube"
  cp /etc/kubernetes/admin.conf "${USER_HOME}/.kube/config"
  chown -R "${SUDO_USER:-ubuntu}:${SUDO_USER:-ubuntu}" "${USER_HOME}/.kube"
else
  echo "==> [$(hostname)] joining as worker"
  "$@"
fi

echo "==> [$(hostname)] joined"
