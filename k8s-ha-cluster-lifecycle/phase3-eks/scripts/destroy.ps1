# Phase 3, Step 8 - remove everything.
# ORDER MATTERS: the NLB was created by Kubernetes, not Terraform. Delete it
# first, or terraform destroy hangs on the VPC (load balancer still attached).
param([string]$IngressVersion = "controller-v1.13.0")
$ErrorActionPreference = "Continue"
$TfDir = Join-Path $PSScriptRoot "..\terraform"

Write-Host "==> Deleting the app Ingress and the ingress-nginx controller (removes the NLB)" -ForegroundColor Cyan
kubectl delete ingress ingress-example --ignore-not-found
kubectl delete -f "https://raw.githubusercontent.com/kubernetes/ingress-nginx/$IngressVersion/deploy/static/provider/aws/deploy.yaml" --ignore-not-found

Write-Host "==> Waiting 90 s for AWS to delete the load balancer" -ForegroundColor Cyan
Start-Sleep -Seconds 90

Write-Host "==> terraform destroy" -ForegroundColor Cyan
& terraform "-chdir=$TfDir" destroy

Write-Host "Remove the 'foo.bar.com' line from your hosts file." -ForegroundColor Yellow
