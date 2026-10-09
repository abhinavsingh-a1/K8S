# Step 4 - copy scripts + manifests to every node and install containerd,
# kubelet, kubeadm, kubectl, crictl. All 6 nodes run in parallel.
. "$PSScriptRoot\lib.ps1"
$s = Get-State
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

Write-Step "Copying node scripts and manifests"
foreach ($n in $s.Nodes) {
    Copy-ToNode $n.Name @($NodeScripts, $Manifests)
    # Remove Windows line endings in case an editor added them
    Invoke-Node $n.Name "sed -i 's/\r$//' ~/node/*.sh ~/k8s/*.yaml && chmod +x ~/node/*.sh"
    Write-Host "  $($n.Name): copied"
}

Write-Step "Preparing all nodes in parallel (3-5 min). Logs: $LogDir"
$jobs = foreach ($n in $s.Nodes) {
    $log = Join-Path $LogDir "$($n.Name)-prepare.log"
    Start-Job -Name $n.Name -ArgumentList $KeyPath, $n.PublicIp, $n.Name, $K8sMinor, $log -ScriptBlock {
        param($Key, $Ip, $Name, $K8s, $Log)
        & ssh -i $Key -o StrictHostKeyChecking=accept-new -o ServerAliveInterval=30 "ubuntu@$Ip" `
            "sudo bash ~/node/prepare-node.sh $Name $K8s" *> $Log
        return $LASTEXITCODE
    }
}
$jobs | Wait-Job | Out-Null

$failed = @()
foreach ($j in $jobs) {
    $code = Receive-Job $j
    if ($code -eq 0) {
        Write-Host ("  {0,-20} OK" -f $j.Name) -ForegroundColor Green
    } else {
        Write-Host ("  {0,-20} FAILED (exit {1})" -f $j.Name, $code) -ForegroundColor Red
        $failed += $j.Name
    }
}
$jobs | Remove-Job

if ($failed.Count -gt 0) {
    throw "Preparation failed on: $($failed -join ', '). Read the logs in $LogDir, fix, and rerun this step."
}

Write-Step "Verify on one node"
Invoke-Node $s.Nodes[0].Name "kubeadm version -o short; cat /etc/default/kubelet; sudo crictl info > /dev/null && echo crictl OK"
Write-Host "`nStep 4 done. Next: .\step5-create-cluster.ps1" -ForegroundColor Green
