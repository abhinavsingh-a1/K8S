# Debug overview: AWS side (instances, NLB targets) + cluster side (debug.sh).
. "$PSScriptRoot\lib.ps1"
$s = Get-State

Write-Step "Instances"
$ids = @($s.Nodes | ForEach-Object { $_.InstanceId })
Invoke-Aws ec2 describe-instances --instance-ids @ids `
    --query "Reservations[].Instances[].[Tags[?Key=='Name']|[0].Value,State.Name,Placement.AvailabilityZone,PrivateIpAddress,PublicIpAddress]" | Write-Host

Write-Step "NLB target health"
Write-Host "API (6443 -> control planes):"
Invoke-Aws elbv2 describe-target-health --target-group-arn $s.ApiTgArn `
    --query "TargetHealthDescriptions[].[Target.Id,TargetHealth.State,TargetHealth.Reason]" | Write-Host
Write-Host "Ingress (80 -> workers:30080):"
Invoke-Aws elbv2 describe-target-health --target-group-arn $s.IngressTgArn `
    --query "TargetHealthDescriptions[].[Target.Id,TargetHealth.State,TargetHealth.Reason]" | Write-Host

Write-Step "Cluster (debug.sh on the first reachable control plane)"
foreach ($cp in $s.Nodes | Where-Object Role -eq "control-plane") {
    try { Invoke-Node $cp.Name "bash ~/node/debug.sh"; break }
    catch { Write-Host "$($cp.Name) unreachable, trying the next control plane..." -ForegroundColor Yellow }
}

Write-Step "End-to-end"
& curl.exe -s -o NUL -w "NLB  http://$($s.NlbDns)/demo/ (Host: $AppHost) -> HTTP %{http_code}`n" -H "Host: $AppHost" "http://$($s.NlbDns)/demo/"
