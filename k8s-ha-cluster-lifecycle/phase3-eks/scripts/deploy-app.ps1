# Phase 3, Steps 5-7 on EKS from Windows PowerShell.
# Needs: aws CLI v2, kubectl, terraform apply already done in ..\terraform
param(
    [string]$IngressVersion = "controller-v1.13.0",
    [string]$AppHost = "foo.bar.com"
)
$ErrorActionPreference = "Stop"
$Here      = $PSScriptRoot
$TfDir     = Join-Path $Here "..\terraform"
$Manifests = Join-Path $Here "..\..\k8s"

function Step([string]$t) { Write-Host "`n==> $t" -ForegroundColor Cyan }
function Run([string]$exe, [string[]]$a) {
    & $exe @a
    if ($LASTEXITCODE -ne 0) { throw "$exe $($a -join ' ') failed" }
}

Step "Step 5 - kubeconfig for the EKS cluster"
$cluster = (& terraform "-chdir=$TfDir" output -raw cluster_name)
$region  = (& terraform "-chdir=$TfDir" output -raw region)
Run aws @("eks", "update-kubeconfig", "--region", $region, "--name", $cluster)
Run kubectl @("get", "nodes", "-o", "wide", "-L", "topology.kubernetes.io/zone")

Step "Step 7a - NGINX Ingress controller (AWS flavour: Service type LoadBalancer = NLB)"
Run kubectl @("apply", "-f", "https://raw.githubusercontent.com/kubernetes/ingress-nginx/$IngressVersion/deploy/static/provider/aws/deploy.yaml")
Run kubectl @("-n", "ingress-nginx", "scale", "deployment", "ingress-nginx-controller", "--replicas=2")
Run kubectl @("-n", "ingress-nginx", "rollout", "status", "deployment/ingress-nginx-controller", "--timeout=300s")

Step "Step 6 - application (same manifests as minikube and kubeadm)"
foreach ($f in "configmap.yaml", "deployment.yaml", "pdb.yaml", "service.yaml") {
    Run kubectl @("apply", "-f", (Join-Path $Manifests $f))
}
Run kubectl @("rollout", "status", "deployment/sample-python-app", "--timeout=300s")
Run kubectl @("get", "pods", "-l", "app=sample-python-app", "-o", "wide")

Step "Step 7b - app Ingress (retries while the admission webhook starts)"
for ($i = 1; $i -le 12; $i++) {
    & kubectl apply -f (Join-Path $Manifests "ingress.yaml")
    if ($LASTEXITCODE -eq 0) { break }
    Start-Sleep -Seconds 10
}

Step "Waiting for the AWS load balancer hostname"
$lb = ""
for ($i = 1; $i -le 30 -and -not $lb; $i++) {
    $lb = (& kubectl -n ingress-nginx get svc ingress-nginx-controller -o "jsonpath={.status.loadBalancer.ingress[0].hostname}")
    if (-not $lb) { Start-Sleep -Seconds 10 }
}
if (-not $lb) { throw "No load balancer hostname yet - check: kubectl -n ingress-nginx describe svc ingress-nginx-controller" }
Write-Host "Load balancer: $lb"

Step "Testing (new NLB DNS can take 2-5 minutes to resolve)"
for ($i = 1; $i -le 30; $i++) {
    $code = (& curl.exe -s -o NUL -w "%{http_code}" -H "Host: $AppHost" "http://$lb/demo/")
    Write-Host "  attempt ${i}: HTTP $code"
    if ($code -eq "200") { break }
    Start-Sleep -Seconds 10
}

$ip = ([System.Net.Dns]::GetHostAddresses($lb) | Select-Object -First 1).IPAddressToString
Write-Host "`nBrowser: add this line to C:\Windows\System32\drivers\etc\hosts (Administrator), then open http://$AppHost/demo/" -ForegroundColor Yellow
Write-Host "  $ip $AppHost"
