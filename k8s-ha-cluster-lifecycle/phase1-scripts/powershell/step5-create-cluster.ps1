# Step 5 - create the HA cluster:
#   1. kubeadm init on the first control plane (endpoint = NLB DNS)
#   2. join the other control planes ONE AT A TIME (etcd adds members serially)
#   3. join the workers
#   4. copy a kubeconfig to Windows so kubectl works from PowerShell
. "$PSScriptRoot\lib.ps1"
$s = Get-State

$cps     = @($s.Nodes | Where-Object Role -eq "control-plane")
$workers = @($s.Nodes | Where-Object Role -eq "worker")
$first   = $cps[0].Name

Write-Step "kubeadm init on $first (2-4 min)"
Invoke-Node $first "sudo bash ~/node/init-first-control-plane.sh $($s.NlbDns) $PodCidr $FlannelVersion"

$joinCp     = Get-NodeOutput $first "cat ~/join-control-plane.sh"
$joinWorker = Get-NodeOutput $first "cat ~/join-worker.sh"

foreach ($cp in $cps | Select-Object -Skip 1) {
    Write-Step "Joining control plane $($cp.Name)"
    Invoke-Node $cp.Name "sudo bash ~/node/join-node.sh control-plane $joinCp"
}

foreach ($w in $workers) {
    Write-Step "Joining worker $($w.Name)"
    Invoke-Node $w.Name "sudo bash ~/node/join-node.sh worker $joinWorker"
}

Write-Step "Labelling workers and waiting until every node is Ready"
foreach ($w in $workers) {
    Invoke-Node $first "kubectl label node $($w.Name) node-role.kubernetes.io/worker= --overwrite"
}
Invoke-Node $first "kubectl wait --for=condition=Ready nodes --all --timeout=300s"
Invoke-Node $first "kubectl get nodes -o wide -L topology.kubernetes.io/zone"

Write-Step "Copying kubeconfig to Windows"
$kubeconfig = Join-Path $Root "kubeconfig"
& scp @SshOptions "ubuntu@$($cps[0].PublicIp):~/.kube/config" $kubeconfig
if ($LASTEXITCODE -ne 0) { throw "Could not copy kubeconfig" }
Write-Host "kubectl from this PowerShell window (API goes through the NLB on port 6443):"
Write-Host "  `$env:KUBECONFIG = '$kubeconfig'" -ForegroundColor Yellow
Write-Host "  kubectl get nodes"

Write-Step "API target health on the NLB (all control planes should be healthy)"
Invoke-Aws elbv2 describe-target-health --target-group-arn $s.ApiTgArn `
    --query "TargetHealthDescriptions[].[Target.Id,TargetHealth.State]" | Write-Host

Write-Host "`nStep 5 done. Next: .\step6-deploy-app.ps1" -ForegroundColor Green
