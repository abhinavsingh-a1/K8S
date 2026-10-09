#!/usr/bin/env bash
# Step 6 - runs on k8s-cp-1 as the ubuntu user (no sudo).
# Applies ConfigMap, Deployment, PodDisruptionBudget and Service.
#
# Usage: bash deploy-app.sh [manifest-dir]
set -euo pipefail

DIR="${1:-$HOME/k8s}"

echo "==> Applying manifests from ${DIR}"
kubectl apply -f "${DIR}/configmap.yaml"
kubectl apply -f "${DIR}/django-config.yaml"
kubectl apply -f "${DIR}/deployment.yaml"
kubectl apply -f "${DIR}/pdb.yaml"
kubectl apply -f "${DIR}/service.yaml"

echo "==> Waiting for the rollout"
kubectl rollout status deployment/sample-python-app --timeout=300s

echo "==> Pods and the node/zone they landed on"
kubectl get pods -l app=sample-python-app -o wide
echo
kubectl get nodes -L topology.kubernetes.io/zone

echo "==> Service endpoints"
kubectl get endpointslices -l kubernetes.io/service-name=python-django-sample-app

echo "==> Test from this node through the NodePort"
curl -s -o /dev/null -w "HTTP %{http_code}\n" http://localhost:30007/demo/
