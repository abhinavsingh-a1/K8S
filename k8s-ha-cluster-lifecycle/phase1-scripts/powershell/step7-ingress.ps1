# Step 7 - NGINX Ingress controller + the app's Ingress, reachable on
# plain port 80 through the NLB:  http://foo.bar.com/demo/
# Run as Administrator if you want the hosts file updated automatically.
. "$PSScriptRoot\lib.ps1"
$s = Get-State
$first = ($s.Nodes | Where-Object Role -eq "control-plane")[0].Name

Write-Step "Installing ingress-nginx and applying the Ingress"
Invoke-Node $first "bash ~/node/install-ingress.sh $IngressVersion ~/k8s"

Write-Step "Waiting for the NLB to mark the workers healthy on 30080"
for ($i = 1; $i -le 18; $i++) {
    $states = Invoke-Aws elbv2 describe-target-health --target-group-arn $s.IngressTgArn `
        --query "TargetHealthDescriptions[].TargetHealth.State"
    Write-Host "  $states"
    if ($states -notmatch "initial|unhealthy|unused") { break }
    Start-Sleep -Seconds 10
}

Write-Step "Testing through the NLB with a Host header"
& curl.exe -s -o NUL -w "HTTP %{http_code}`n" -H "Host: $AppHost" "http://$($s.NlbDns)/demo/"

Write-Step "Windows hosts file"
$nlbIp = ([System.Net.Dns]::GetHostAddresses($s.NlbDns) | Select-Object -First 1).IPAddressToString
if (Test-Admin) {
    Set-HostsEntry $nlbIp
    Write-Host "hosts: $nlbIp $AppHost"
    & curl.exe -s -o NUL -w "http://$AppHost/demo/ -> HTTP %{http_code}`n" "http://$AppHost/demo/"
    Write-Host "`nOpen http://$AppHost/demo/ in the browser." -ForegroundColor Green
} else {
    Write-Host "Not running as Administrator. Add this line to C:\Windows\System32\drivers\etc\hosts:" -ForegroundColor Yellow
    Write-Host "  $nlbIp $AppHost"
}
Write-Host "Step 7 done. Use .\status.ps1 any time, .\step8-cleanup.ps1 when finished." -ForegroundColor Green
