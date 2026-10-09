# Phase 3 driver (Windows PowerShell). Same commands as scripts/run.sh:
#   .\run.ps1 bootstrap | infra | platform | deploy | test | status | destroy
param([Parameter(Mandatory = $true)]
      [ValidateSet("bootstrap", "infra", "platform", "deploy", "test", "status", "destroy")]
      [string]$Command)

$ErrorActionPreference = "Stop"
$Root     = Split-Path -Parent $PSScriptRoot
$Tf       = Join-Path $Root "terraform"
$Infra    = Join-Path $Tf "live\dev\10-infra"
$Platform = Join-Path $Tf "live\dev\20-platform"
$Shared   = Join-Path $Root "..\k8s"
$Overlay  = Join-Path $Root "k8s-overlay"
$AppHost  = "foo.bar.com"

function Step([string]$t) { Write-Host "`n==> $t" -ForegroundColor Cyan }
function Run([string]$exe, [string[]]$a) {
    & $exe @a
    if ($LASTEXITCODE -ne 0) { throw "$exe $($a -join ' ') failed" }
}
function Out([string]$dir, [string]$name) { (& terraform "-chdir=$dir" output -raw $name) }
# UTF-8 WITHOUT BOM: Terraform cannot parse files that start with a BOM
function Write-NoBom([string]$path, [string]$text) {
    [System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding($false)))
}
function Init-Stack([string]$dir) {
    if (-not (Test-Path (Join-Path $dir "backend.hcl"))) { throw "No backend.hcl in $dir - run: .\run.ps1 bootstrap" }
    Run terraform @("-chdir=$dir", "init", "-backend-config=backend.hcl", "-input=false")
}
function Plan-Apply([string]$dir) {
    Init-Stack $dir
    Run terraform @("-chdir=$dir", "validate")
    Run terraform @("-chdir=$dir", "plan", "-out=tfplan")
    if ((Read-Host "Apply this plan? (yes/no)") -ne "yes") { throw "Cancelled" }
    Run terraform @("-chdir=$dir", "apply", "tfplan")
    Remove-Item (Join-Path $dir "tfplan") -ErrorAction SilentlyContinue
}
function Kubeconfig {
    Init-Stack $Infra | Out-Null
    Run aws @("eks", "update-kubeconfig", "--region", (Out $Infra "region"), "--name", (Out $Infra "cluster_name"))
}
function Apply-Stdin([string]$yaml) {
    $yaml | kubectl apply -f -
    if ($LASTEXITCODE -ne 0) { throw "kubectl apply failed" }
}
function Test-App {
    Step "Load balancer hostname"
    $lb = ""
    for ($i = 1; $i -le 30 -and -not $lb; $i++) {
        $lb = (& kubectl -n ingress-nginx get svc ingress-nginx-controller -o "jsonpath={.status.loadBalancer.ingress[0].hostname}")
        if (-not $lb) { Start-Sleep 10 }
    }
    if (-not $lb) { throw "No load balancer yet: kubectl -n ingress-nginx describe svc ingress-nginx-controller" }
    Write-Host $lb
    Step "Testing http://$lb/demo/ (new NLB DNS can take 2-5 min)"
    for ($i = 1; $i -le 30; $i++) {
        $code = (& curl.exe -s -o NUL -w "%{http_code}" -H "Host: $AppHost" "http://$lb/demo/")
        Write-Host "  attempt ${i}: HTTP $code"
        if ($code -eq "200") { break }
        Start-Sleep 10
    }
    try {
        $ip = ([System.Net.Dns]::GetHostAddresses($lb) | Select-Object -First 1).IPAddressToString
        Write-Host "Browser: add '$ip $AppHost' to C:\Windows\System32\drivers\etc\hosts (Administrator), open http://$AppHost/demo/" -ForegroundColor Yellow
    } catch { Write-Host "DNS not resolvable yet - rerun: .\run.ps1 test" }
}

switch ($Command) {
    "bootstrap" {
        Step "State bucket (bootstrap stack, local state)"
        $b = Join-Path $Tf "bootstrap"
        Run terraform @("-chdir=$b", "init")
        Run terraform @("-chdir=$b", "apply")
        # terraform prints several lines -> PowerShell array; join with newlines
        Write-NoBom (Join-Path $Infra "backend.hcl")    (((Out $b "backend_hcl_infra") -join "`n") + "`n")
        Write-NoBom (Join-Path $Platform "backend.hcl") (((Out $b "backend_hcl_platform") -join "`n") + "`n")
        Write-NoBom (Join-Path $Platform "terraform.tfvars") ("state_bucket = `"" + (Out $b "state_bucket") + "`"`n")
        Write-Host "Wrote backend.hcl for both stacks and 20-platform\terraform.tfvars"
    }
    "infra"    { Step "Stack 10-infra";    Plan-Apply $Infra }
    "platform" { Step "Stack 20-platform"; Plan-Apply $Platform }
    "deploy" {
        Init-Stack $Platform | Out-Null
        $region = Out $Platform "region"
        $secret = Out $Platform "app_secret_name"

        Step "Step 5 - kubeconfig"
        Kubeconfig
        Run kubectl @("get", "nodes", "-o", "wide", "-L", "topology.kubernetes.io/zone")

        Step "Step 6a - secret sync: Secrets Manager -> ESO -> Secret django-secrets"
        Apply-Stdin ((Get-Content (Join-Path $Overlay "cluster-secret-store.yaml") -Raw) -replace "__REGION__", $region)
        Apply-Stdin ((Get-Content (Join-Path $Overlay "external-secret.yaml") -Raw) -replace "__SECRET_NAME__", $secret)
        Run kubectl @("wait", "--for=condition=Ready", "clustersecretstore/aws-secrets-manager", "--timeout=120s")
        Run kubectl @("wait", "--for=condition=Ready", "externalsecret/django-secrets", "--timeout=120s")

        Step "Step 6b - application (shared manifests)"
        foreach ($f in "configmap.yaml", "django-config.yaml", "deployment.yaml", "pdb.yaml", "service.yaml") {
            Run kubectl @("apply", "-f", (Join-Path $Shared $f))
        }
        Run kubectl @("rollout", "restart", "deployment/sample-python-app")
        Run kubectl @("rollout", "status", "deployment/sample-python-app", "--timeout=300s")
        Run kubectl @("get", "pods", "-l", "app=sample-python-app", "-o", "wide")

        Step "Step 7 - Ingress (controller installed by Terraform)"
        Run kubectl @("apply", "-f", (Join-Path $Shared "ingress.yaml"))
        Test-App
    }
    "test" { Kubeconfig | Out-Null; Test-App }
    "status" {
        Kubeconfig | Out-Null
        Step "Nodes";       kubectl get nodes -o wide -L topology.kubernetes.io/zone
        Step "Not running"; kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded
        Step "App";         kubectl get pods -l app=sample-python-app -o wide
        Step "Secret sync"; kubectl get clustersecretstore,externalsecret
        Step "Ingress";     kubectl get ingress; kubectl -n ingress-nginx get pods,svc -o wide
    }
    "destroy" {
        $ErrorActionPreference = "Continue"
        Step "1/3 app objects"
        try {
            Kubeconfig | Out-Null
            kubectl delete -f (Join-Path $Shared "ingress.yaml") --ignore-not-found
            kubectl delete externalsecret django-secrets --ignore-not-found
            kubectl delete clustersecretstore aws-secrets-manager --ignore-not-found
        } catch { Write-Host "Cluster not reachable - skipping app cleanup" -ForegroundColor Yellow }

        Step "2/3 stack 20-platform (removes the NLB, secret, IAM role)"
        Init-Stack $Platform | Out-Null
        & terraform "-chdir=$Platform" destroy
        Write-Host "Waiting 90 s for AWS to delete the load balancer..."
        Start-Sleep 90

        Step "3/3 stack 10-infra (EKS, nodes, VPC)"
        Init-Stack $Infra | Out-Null
        & terraform "-chdir=$Infra" destroy
        Write-Host "Kept: the state bucket. Remove '$AppHost' from your hosts file." -ForegroundColor Yellow
    }
}
