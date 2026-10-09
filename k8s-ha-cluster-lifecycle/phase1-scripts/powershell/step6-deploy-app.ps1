# Step 6 - deploy ConfigMap, Deployment (3 replicas spread over zones),
# PodDisruptionBudget and NodePort Service, then test every worker.
. "$PSScriptRoot\lib.ps1"
$s = Get-State
$first = ($s.Nodes | Where-Object Role -eq "control-plane")[0].Name

Write-Step "Copying the latest manifests to $first"
Copy-ToNode $first @($Manifests)
Invoke-Node $first "sed -i 's/\r$//' ~/k8s/*.yaml"

Write-Step "Deploying the app"
Invoke-Node $first "bash ~/node/deploy-app.sh ~/k8s"

Write-Step "Testing NodePort 30007 on every worker from Windows"
foreach ($w in $s.Nodes | Where-Object Role -eq "worker") {
    $url = "http://$($w.PublicIp):30007/demo/"
    try {
        $r = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 10
        Write-Host ("  {0,-20} {1}  HTTP {2}" -f $w.Name, $url, $r.StatusCode) -ForegroundColor Green
    } catch {
        Write-Host ("  {0,-20} {1}  FAILED: {2}" -f $w.Name, $url, $_.Exception.Message) -ForegroundColor Red
    }
}

Write-Host "`nOpen one in the browser and refresh: the 'Served by pod' name changes." -ForegroundColor Yellow
Write-Host "Step 6 done. Next: .\step7-ingress.ps1" -ForegroundColor Green
