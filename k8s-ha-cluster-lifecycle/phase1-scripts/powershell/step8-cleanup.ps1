# Step 8 - pause or remove everything.
#   .\step8-cleanup.ps1 -Action Stop                 stop all instances (disks kept)
#   .\step8-cleanup.ps1 -Action Start                start them again, refresh public IPs
#   .\step8-cleanup.ps1 -Action Destroy              delete NLB, instances, SGs
#   .\step8-cleanup.ps1 -Action Destroy -DeleteKey   ...and the key pair
param(
    [Parameter(Mandatory = $true)][ValidateSet("Stop", "Start", "Destroy")][string]$Action,
    [switch]$DeleteKey
)
. "$PSScriptRoot\lib.ps1"
$s = Get-State
$ids = @($s.Nodes | ForEach-Object { $_.InstanceId })

switch ($Action) {
    "Stop" {
        Write-Step "Stopping $($ids.Count) instances"
        Invoke-Aws ec2 stop-instances --instance-ids @ids | Out-Null
        Invoke-Aws ec2 wait instance-stopped --instance-ids @ids | Out-Null
        Write-Host "Stopped. The NLB keeps running (~`$0.6/day); use Destroy to remove it." -ForegroundColor Green
    }
    "Start" {
        Write-Step "Starting control planes first, then workers"
        $cp = @($s.Nodes | Where-Object Role -eq "control-plane" | ForEach-Object { $_.InstanceId })
        $wk = @($s.Nodes | Where-Object Role -eq "worker" | ForEach-Object { $_.InstanceId })
        Invoke-Aws ec2 start-instances --instance-ids @cp | Out-Null
        Invoke-Aws ec2 wait instance-running --instance-ids @cp | Out-Null
        Invoke-Aws ec2 start-instances --instance-ids @wk | Out-Null
        Invoke-Aws ec2 wait instance-running --instance-ids @ids | Out-Null

        Write-Step "Refreshing public IPs (they change on every start; private IPs don't)"
        foreach ($n in $s.Nodes) {
            $n.PublicIp = Invoke-Aws ec2 describe-instances --instance-ids $n.InstanceId `
                --query "Reservations[0].Instances[0].PublicIpAddress"
        }
        Clear-KnownHosts @($s.Nodes | ForEach-Object { $_.PublicIp })
        Save-State $s
        $s.Nodes | Format-Table Name, PublicIp, PrivateIp | Out-String | Write-Host

        $MyIp = (Invoke-RestMethod -Uri "https://checkip.amazonaws.com").Trim() + "/32"
        if ($MyIp -ne $s.MyIp) {
            Write-Host "Your IP changed ($($s.MyIp) -> $MyIp). Rerun .\step2-network.ps1 to add it." -ForegroundColor Yellow
        }
        Write-Host "Give the cluster 1-2 minutes, then run .\status.ps1" -ForegroundColor Green
    }
    "Destroy" {
        $answer = Read-Host "Type 'destroy' to delete the NLB, $($ids.Count) instances and security groups"
        if ($answer -ne "destroy") { Write-Host "Cancelled."; return }

        if ($s.NlbArn) {
            Write-Step "Deleting load balancer"
            Try-Aws elbv2 delete-load-balancer --load-balancer-arn $s.NlbArn | Out-Null
            Try-Aws elbv2 wait load-balancers-deleted --load-balancer-arns $s.NlbArn | Out-Null
        }
        foreach ($tg in @($s.ApiTgArn, $s.IngressTgArn)) {
            if ($tg) { Try-Aws elbv2 delete-target-group --target-group-arn $tg | Out-Null }
        }

        Clear-KnownHosts @($s.Nodes | ForEach-Object { $_.PublicIp })
        Write-Step "Terminating instances"
        Invoke-Aws ec2 terminate-instances --instance-ids @ids | Out-Null
        Invoke-Aws ec2 wait instance-terminated --instance-ids @ids | Out-Null

        Write-Step "Deleting security groups (retries while network interfaces detach)"
        foreach ($sg in @($s.NlbSg, $s.NodesSg)) {
            for ($i = 1; $i -le 12; $i++) {
                if ($null -ne (Try-Aws ec2 delete-security-group --group-id $sg)) { Write-Host "  deleted $sg"; break }
                Start-Sleep -Seconds 10
            }
        }

        if ($DeleteKey) {
            Write-Step "Deleting key pair $KeyName"
            Try-Aws ec2 delete-key-pair --key-name $KeyName | Out-Null
            Remove-Item $KeyPath -Force -ErrorAction SilentlyContinue
        }

        if (Test-Admin) { Set-HostsEntry $null; Write-Host "Removed $AppHost from hosts file" }
        else { Write-Host "Remove the '$AppHost' line from your hosts file (needs Administrator)." -ForegroundColor Yellow }

        Remove-Item $StateFile, (Join-Path $Root "kubeconfig") -Force -ErrorAction SilentlyContinue

        Write-Step "Leftovers check (should all be empty)"
        Invoke-Aws ec2 describe-instances --filters "Name=tag:Project,Values=$Project" "Name=instance-state-name,Values=pending,running,stopped" --query "Reservations[].Instances[].InstanceId" | Write-Host
        Invoke-Aws ec2 describe-volumes --filters "Name=status,Values=available" --query "Volumes[].VolumeId" | Write-Host
        Write-Host "Destroyed." -ForegroundColor Green
    }
}
