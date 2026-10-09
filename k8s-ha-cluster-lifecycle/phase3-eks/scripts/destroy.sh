#!/usr/bin/env bash
# Phase 3, Step 8 - remove everything.
# ORDER MATTERS: the NLB was created by Kubernetes, not Terraform. Delete it
# first, or terraform destroy hangs on the VPC (load balancer still attached).
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
INGRESS_VERSION="${INGRESS_VERSION:-controller-v1.13.0}"

echo "==> Deleting the app Ingress and ingress-nginx (removes the NLB)"
kubectl delete ingress ingress-example --ignore-not-found
kubectl delete -f "https://raw.githubusercontent.com/kubernetes/ingress-nginx/${INGRESS_VERSION}/deploy/static/provider/aws/deploy.yaml" --ignore-not-found

echo "==> Waiting 90 s for AWS to delete the load balancer"
sleep 90

echo "==> terraform destroy"
terraform -chdir="${HERE}/../terraform" destroy
echo "Remove the 'foo.bar.com' line from your hosts file."
