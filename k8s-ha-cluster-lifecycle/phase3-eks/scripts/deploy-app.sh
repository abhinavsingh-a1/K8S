#!/usr/bin/env bash
# Phase 3, Steps 5-7 on EKS from Linux/WSL.
# Needs: aws CLI v2, kubectl, terraform apply already done in ../terraform
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TF="${HERE}/../terraform"
MANIFESTS="${HERE}/../../k8s"
INGRESS_VERSION="${INGRESS_VERSION:-controller-v1.13.0}"
APP_HOST="foo.bar.com"

step() { echo -e "\n\033[36m==> $*\033[0m"; }

step "Step 5 - kubeconfig for the EKS cluster"
aws eks update-kubeconfig \
  --region "$(terraform -chdir="${TF}" output -raw region)" \
  --name "$(terraform -chdir="${TF}" output -raw cluster_name)"
kubectl get nodes -o wide -L topology.kubernetes.io/zone

step "Step 7a - NGINX Ingress controller (Service type LoadBalancer = NLB)"
kubectl apply -f "https://raw.githubusercontent.com/kubernetes/ingress-nginx/${INGRESS_VERSION}/deploy/static/provider/aws/deploy.yaml"
kubectl -n ingress-nginx scale deployment ingress-nginx-controller --replicas=2
kubectl -n ingress-nginx rollout status deployment/ingress-nginx-controller --timeout=300s

step "Step 6 - application"
for f in configmap.yaml deployment.yaml pdb.yaml service.yaml; do
  kubectl apply -f "${MANIFESTS}/${f}"
done
kubectl rollout status deployment/sample-python-app --timeout=300s
kubectl get pods -l app=sample-python-app -o wide

step "Step 7b - app Ingress"
for i in $(seq 1 12); do
  kubectl apply -f "${MANIFESTS}/ingress.yaml" && break
  echo "  webhook not ready, retry ${i}/12"; sleep 10
done

step "Waiting for the load balancer hostname"
LB=""
for i in $(seq 1 30); do
  LB=$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
  [[ -n "${LB}" ]] && break
  sleep 10
done
echo "Load balancer: ${LB}"

step "Testing (new NLB DNS can take 2-5 minutes)"
for i in $(seq 1 30); do
  code=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: ${APP_HOST}" "http://${LB}/demo/" || true)
  echo "  attempt ${i}: HTTP ${code}"
  [[ "${code}" == "200" ]] && break
  sleep 10
done

echo
echo "Browser: put '$(getent hosts "${LB}" | awk 'NR==1{print $1}') ${APP_HOST}' in your hosts file, open http://${APP_HOST}/demo/"
