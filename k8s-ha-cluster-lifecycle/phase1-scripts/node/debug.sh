#!/usr/bin/env bash
# Health overview of the whole cluster. Run on any control plane (no sudo).
# Usage: bash debug.sh
set +e

section() { echo -e "\n=============== $* ==============="; }

section "Nodes (role, zone, IP)"
kubectl get nodes -o wide -L topology.kubernetes.io/zone

section "Control plane components (one set per control plane)"
kubectl -n kube-system get pods -l tier=control-plane -o wide

section "etcd members (should list 3)"
ETCD_POD=$(kubectl -n kube-system get pods -l component=etcd -o jsonpath='{.items[0].metadata.name}')
kubectl -n kube-system exec "${ETCD_POD}" -- etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  member list -w table

section "Pods not Running/Completed"
kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded

section "App pods (node spread)"
kubectl get pods -l app=sample-python-app -o wide

section "Service endpoints"
kubectl get endpointslices -l kubernetes.io/service-name=python-django-sample-app

section "Ingress"
kubectl get ingress
kubectl -n ingress-nginx get pods -o wide

section "PodDisruptionBudget"
kubectl get pdb

section "Last 15 warning events"
kubectl get events -A --field-selector type=Warning --sort-by=.metadata.creationTimestamp | tail -15

section "Local node: kubelet + containerd"
systemctl is-active kubelet containerd
sudo crictl ps 2>/dev/null | head -15
