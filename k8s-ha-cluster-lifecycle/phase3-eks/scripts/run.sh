#!/usr/bin/env bash
# Phase 3 driver (Linux / WSL). PowerShell twin: scripts/run.ps1
#
#   ./scripts/run.sh bootstrap   one-time: S3 state bucket + backend files
#   ./scripts/run.sh infra       stack 10-infra: plan + apply (VPC, EKS, nodes)  ~15-20 min
#   ./scripts/run.sh platform    stack 20-platform: plan + apply (secrets, ESO, ingress-nginx)
#   ./scripts/run.sh deploy      kubeconfig + secret sync + app + ingress, then test
#   ./scripts/run.sh test        curl the app through the load balancer
#   ./scripts/run.sh status      cluster / secret / ingress overview
#   ./scripts/run.sh destroy     app -> 20-platform -> 10-infra (this order!)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TF="${ROOT}/terraform"
INFRA="${TF}/live/dev/10-infra"
PLATFORM="${TF}/live/dev/20-platform"
SHARED="${ROOT}/../k8s"
OVERLAY="${ROOT}/k8s-overlay"
APP_HOST="foo.bar.com"

step() { echo -e "\n\033[36m==> $*\033[0m"; }
die()  { echo -e "\033[31mERROR: $*\033[0m" >&2; exit 1; }
out()  { terraform -chdir="$1" output -raw "$2"; }

init_stack() {
  [[ -f "$1/backend.hcl" ]] || die "No backend.hcl in $1 - run: ./scripts/run.sh bootstrap"
  terraform -chdir="$1" init -backend-config=backend.hcl -input=false > /dev/null
}

plan_apply() {
  init_stack "$1"
  terraform -chdir="$1" validate
  terraform -chdir="$1" plan -out=tfplan
  read -r -p "Apply this plan? (yes/no) " ok
  [[ "${ok}" == "yes" ]] || die "Cancelled"
  terraform -chdir="$1" apply tfplan
  rm -f "$1/tfplan"
}

bootstrap() {
  step "State bucket (bootstrap stack, local state)"
  terraform -chdir="${TF}/bootstrap" init
  terraform -chdir="${TF}/bootstrap" apply
  out "${TF}/bootstrap" backend_hcl_infra    > "${INFRA}/backend.hcl"
  out "${TF}/bootstrap" backend_hcl_platform > "${PLATFORM}/backend.hcl"
  echo "state_bucket = \"$(out "${TF}/bootstrap" state_bucket)\"" > "${PLATFORM}/terraform.tfvars"
  echo "Wrote backend.hcl for both stacks and 20-platform/terraform.tfvars"
}

infra()    { step "Stack 10-infra";    plan_apply "${INFRA}"; }
platform() { step "Stack 20-platform"; plan_apply "${PLATFORM}"; }

kubeconfig() {
  init_stack "${INFRA}"
  aws eks update-kubeconfig --region "$(out "${INFRA}" region)" --name "$(out "${INFRA}" cluster_name)"
}

deploy() {
  init_stack "${PLATFORM}"
  local region secret
  region="$(out "${PLATFORM}" region)"
  secret="$(out "${PLATFORM}" app_secret_name)"

  step "Step 5 - kubeconfig"
  kubeconfig
  kubectl get nodes -o wide -L topology.kubernetes.io/zone

  step "Step 6a - secret sync: Secrets Manager -> ESO -> Secret django-secrets"
  sed "s#__REGION__#${region}#" "${OVERLAY}/cluster-secret-store.yaml" | kubectl apply -f -
  sed "s#__SECRET_NAME__#${secret}#" "${OVERLAY}/external-secret.yaml" | kubectl apply -f -
  kubectl wait --for=condition=Ready clustersecretstore/aws-secrets-manager --timeout=120s
  kubectl wait --for=condition=Ready externalsecret/django-secrets --timeout=120s
  kubectl get secret django-secrets -o jsonpath='{.data}' | grep -q DJANGO_SECRET_KEY \
    && echo "django-secrets contains DJANGO_SECRET_KEY (value not shown)"

  step "Step 6b - application (shared manifests)"
  for f in configmap.yaml django-config.yaml deployment.yaml pdb.yaml service.yaml; do
    kubectl apply -f "${SHARED}/${f}"
  done
  kubectl rollout restart deployment/sample-python-app   # pick up the synced secret
  kubectl rollout status deployment/sample-python-app --timeout=300s
  kubectl get pods -l app=sample-python-app -o wide

  step "Step 7 - Ingress (controller installed by Terraform)"
  kubectl apply -f "${SHARED}/ingress.yaml"
  test_app
}

test_app() {
  local lb code
  step "Load balancer hostname"
  for i in $(seq 1 30); do
    lb=$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
    [[ -n "${lb}" ]] && break; sleep 10
  done
  [[ -n "${lb}" ]] || die "No load balancer yet: kubectl -n ingress-nginx describe svc ingress-nginx-controller"
  echo "${lb}"
  step "Testing http://${lb}/demo/ (new NLB DNS can take 2-5 min)"
  for i in $(seq 1 30); do
    code=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: ${APP_HOST}" "http://${lb}/demo/" || true)
    echo "  attempt ${i}: HTTP ${code}"
    [[ "${code}" == "200" ]] && break; sleep 10
  done
  echo "Browser: hosts line '$(getent hosts "${lb}" | awk 'NR==1{print $1}') ${APP_HOST}', then http://${APP_HOST}/demo/"
}

status() {
  kubeconfig > /dev/null
  step "Nodes";            kubectl get nodes -o wide -L topology.kubernetes.io/zone
  step "Not running";      kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded
  step "App";              kubectl get pods -l app=sample-python-app -o wide
  step "Secret sync";      kubectl get clustersecretstore,externalsecret
  step "Ingress";          kubectl get ingress; kubectl -n ingress-nginx get pods,svc -o wide
  step "Helm releases";    helm list -A 2>/dev/null || echo "(helm CLI not installed - optional)"
  step "Warnings";         kubectl get events -A --field-selector type=Warning --sort-by=.metadata.creationTimestamp | tail -15
}

destroy() {
  step "1/3 app objects (ExternalSecret owns django-secrets)"
  # Subshell: if the cluster is already gone, carry on with the stacks.
  ( kubeconfig > /dev/null \
    && kubectl delete -f "${SHARED}/ingress.yaml" --ignore-not-found \
    && kubectl delete externalsecret django-secrets --ignore-not-found \
    && kubectl delete clustersecretstore aws-secrets-manager --ignore-not-found ) \
    || echo "Cluster not reachable - skipping app cleanup"

  step "2/3 stack 20-platform (helm uninstall removes the NLB, deletes the secret + IAM role)"
  init_stack "${PLATFORM}"
  terraform -chdir="${PLATFORM}" destroy
  echo "Waiting 90 s for AWS to delete the load balancer and its network interfaces..."
  sleep 90

  step "3/3 stack 10-infra (EKS, nodes, VPC)"
  init_stack "${INFRA}"
  terraform -chdir="${INFRA}" destroy
  echo "Kept: the state bucket (terraform/bootstrap). Remove '${APP_HOST}' from your hosts file."
}

case "${1:-}" in
  bootstrap) bootstrap ;;
  infra)     infra ;;
  platform)  platform ;;
  deploy)    deploy ;;
  test)      kubeconfig > /dev/null; test_app ;;
  status)    status ;;
  destroy)   destroy ;;
  *) grep -E '^#   ' "$0" | sed 's/^#   //'; exit 1 ;;
esac
