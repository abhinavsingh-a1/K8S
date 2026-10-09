#!/usr/bin/env bash
# Step 7 - runs on k8s-cp-1 as the ubuntu user (no sudo).
# Installs the NGINX Ingress controller (bare-metal flavour = NodePort),
# fixes its HTTP NodePort to 30080 (the NLB forwards port 80 there),
# runs 2 controller replicas, then applies the app's Ingress.
#
# Usage: bash install-ingress.sh [controller-version] [manifest-dir]
set -euo pipefail

VERSION="${1:-controller-v1.13.0}"
DIR="${2:-$HOME/k8s}"
URL="https://raw.githubusercontent.com/kubernetes/ingress-nginx/${VERSION}/deploy/static/provider/baremetal/deploy.yaml"

echo "==> Installing ingress-nginx ${VERSION}"
kubectl apply -f "${URL}"

echo "==> Fixing the HTTP NodePort to 30080"
kubectl -n ingress-nginx patch svc ingress-nginx-controller --type=json \
  -p='[{"op":"replace","path":"/spec/ports/0/nodePort","value":30080}]'

echo "==> Running 2 controller replicas (survives one node failure)"
kubectl -n ingress-nginx scale deployment ingress-nginx-controller --replicas=2
kubectl -n ingress-nginx rollout status deployment/ingress-nginx-controller --timeout=300s

echo "==> Applying the Ingress (retries while the admission webhook starts)"
for i in $(seq 1 12); do
  if kubectl apply -f "${DIR}/ingress.yaml"; then break; fi
  echo "   webhook not ready yet, retry ${i}/12 in 10s"
  sleep 10
done

kubectl get pods -n ingress-nginx -o wide
kubectl get svc -n ingress-nginx ingress-nginx-controller
kubectl get ingress

echo "==> Test from this node"
curl -s -o /dev/null -w "HTTP %{http_code}\n" -H "Host: foo.bar.com" http://localhost:30080/demo/
