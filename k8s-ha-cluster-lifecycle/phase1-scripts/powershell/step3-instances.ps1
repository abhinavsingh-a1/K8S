# Step 3 - launch 3 control planes + 3 workers across 3 availability zones,
# and a Network Load Balancer in front of them:
#
#   NLB :6443 -> control planes :6443   (Kubernetes API, HA endpoint)
#   NLB :80   -> workers        :30080  (NGINX Ingress NodePort)
. "$PSScriptRoot\lib.ps1"
$s = Get-State

Write-Step "Ubuntu 24.04 x86 AMI (from Canonical's public SSM parameter)"
$Ami = Invoke-Aws ssm get-parameters `
    --names /aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id `
    --query "Parameters[0].Value"
Write-Host "AMI: $Ami"

Write-Step "One default subnet in each of 3 availability zones"
$subnetText = Invoke-Aws ec2 describe-subnets `
    --filters "Name=vpc-id,Values=$($s.VpcId)" "Name=default-for-az,Values=true" `
    --query "Subnets[].[AvailabilityZone,SubnetId]"
$Subnets = $subnetText -split "`r?`n" | ForEach-Object {
    $p = $_ -split "\s+"; [pscustomobject]@{ Az = $p[0]; SubnetId = $p[1] }
} | Sort-Object Az | Select-Object -First 3
if ($Subnets.Count -lt 3) { throw "Need default subnets in 3 AZs, found $($Subnets.Count)" }
$Subnets | Format-Table | Out-String | Write-Host

# Plan: name, role, type, AZ index (round-robin over the 3 AZs)
$plan = @()
for ($i = 1; $i -le $ControlPlaneCount; $i++) {
    $plan += [pscustomobject]@{ Name = "$Project-cp-$i"; Role = "control-plane"; Type = $ControlPlaneType; AzIndex = ($i - 1) % 3 }
}
for ($i = 1; $i -le $WorkerCount; $i++) {
    $plan += [pscustomobject]@{ Name = "$Project-worker-$i"; Role = "worker"; Type = $WorkerType; AzIndex = ($i - 1) % 3 }
}

Write-Step "Launching instances (existing ones with the same Name tag are reused)"
foreach ($n in $plan) {
    $existing = Invoke-Aws ec2 describe-instances `
        --filters "Name=tag:Name,Values=$($n.Name)" "Name=instance-state-name,Values=pending,running,stopping,stopped" `
        --query "Reservations[0].Instances[0].InstanceId"
    if ($existing -and $existing -ne "None") {
        Write-Host "$($n.Name) exists: $existing"
        $n | Add-Member -NotePropertyName InstanceId -NotePropertyValue $existing
        continue
    }
    $subnet = $Subnets[$n.AzIndex].SubnetId
    $id = Invoke-Aws ec2 run-instances `
        --image-id $Ami --instance-type $n.Type --key-name $KeyName `
        --security-group-ids $s.NodesSg --subnet-id $subnet `
        --block-device-mappings "DeviceName=/dev/sda1,Ebs={VolumeSize=$RootVolumeGiB,VolumeType=gp3,DeleteOnTermination=true}" `
        --metadata-options "HttpTokens=required,HttpEndpoint=enabled,HttpPutResponseHopLimit=2" `
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$($n.Name)},{Key=Project,Value=$Project},{Key=Role,Value=$($n.Role)}]" `
        --query "Instances[0].InstanceId"
    Write-Host "Launched $($n.Name): $id in $($Subnets[$n.AzIndex].Az)"
    $n | Add-Member -NotePropertyName InstanceId -NotePropertyValue $id
}

$ids = $plan | ForEach-Object { $_.InstanceId }
Write-Step "Waiting for all instances to be running and pass status checks (2-4 min)"
Invoke-Aws ec2 wait instance-running --instance-ids @ids | Out-Null
Invoke-Aws ec2 wait instance-status-ok --instance-ids @ids | Out-Null

$nodes = @()
foreach ($n in $plan) {
    $info = Invoke-Aws ec2 describe-instances --instance-ids $n.InstanceId `
        --query "Reservations[0].Instances[0].[PrivateIpAddress,PublicIpAddress,Placement.AvailabilityZone]"
    $p = $info -split "\s+"
    $nodes += [pscustomobject]@{
        Name = $n.Name; Role = $n.Role; InstanceId = $n.InstanceId
        PrivateIp = $p[0]; PublicIp = $p[1]; Az = $p[2]
    }
}
Clear-KnownHosts @($nodes | ForEach-Object { $_.PublicIp })
Set-StateValue $s "Nodes" $nodes
Set-StateValue $s "SubnetIds" @($Subnets | ForEach-Object { $_.SubnetId })
Save-State $s

Write-Step "Network Load Balancer"
$nlbName = "$Project-nlb"
$nlb = Try-Aws elbv2 describe-load-balancers --names $nlbName --query "LoadBalancers[0].[LoadBalancerArn,DNSName]"
if (-not $nlb) {
    $subnetIds = @($s.SubnetIds)     # '@subnetIds' below splats them as separate arguments
    $nlb = Invoke-Aws elbv2 create-load-balancer --name $nlbName --type network --scheme internet-facing `
        --subnets @subnetIds --security-groups $s.NlbSg `
        --tags "Key=Project,Value=$Project" `
        --query "LoadBalancers[0].[LoadBalancerArn,DNSName]"
}
$NlbArn, $NlbDns = $nlb -split "\s+"
Invoke-Aws elbv2 modify-load-balancer-attributes --load-balancer-arn $NlbArn `
    --attributes "Key=load_balancing.cross_zone.enabled,Value=true" | Out-Null

function Get-OrCreateTg([string]$Name, [int]$Port) {
    $arn = Try-Aws elbv2 describe-target-groups --names $Name --query "TargetGroups[0].TargetGroupArn"
    if (-not $arn) {
        $arn = Invoke-Aws elbv2 create-target-group --name $Name --protocol TCP --port $Port `
            --vpc-id $s.VpcId --target-type instance `
            --health-check-protocol TCP --health-check-interval-seconds 10 `
            --healthy-threshold-count 2 --unhealthy-threshold-count 2 `
            --query "TargetGroups[0].TargetGroupArn"
    }
    # A node calling the NLB that forwards back to itself ("hairpin") fails
    # when the client IP is preserved. kubeadm needs exactly that, so turn it off.
    Invoke-Aws elbv2 modify-target-group-attributes --target-group-arn $arn `
        --attributes "Key=preserve_client_ip.enabled,Value=false" "Key=deregistration_delay.timeout_seconds,Value=30" | Out-Null
    return $arn
}

$ApiTg     = Get-OrCreateTg "$Project-api" 6443
$IngressTg = Get-OrCreateTg "$Project-ingress" 30080

$cpTargets = $nodes | Where-Object Role -eq "control-plane" | ForEach-Object { "Id=$($_.InstanceId)" }
$wkTargets = $nodes | Where-Object Role -eq "worker"        | ForEach-Object { "Id=$($_.InstanceId)" }
Invoke-Aws elbv2 register-targets --target-group-arn $ApiTg     --targets @cpTargets | Out-Null
Invoke-Aws elbv2 register-targets --target-group-arn $IngressTg --targets @wkTargets | Out-Null

function Add-Listener([int]$Port, [string]$TgArn) {
    $existing = Invoke-Aws elbv2 describe-listeners --load-balancer-arn $NlbArn --query "Listeners[?Port==``$Port``].ListenerArn"
    if (-not $existing) {
        Invoke-Aws elbv2 create-listener --load-balancer-arn $NlbArn --protocol TCP --port $Port `
            --default-actions "Type=forward,TargetGroupArn=$TgArn" | Out-Null
    }
}
Add-Listener 6443 $ApiTg
Add-Listener 80   $IngressTg

Write-Host "Waiting for the NLB to become active..."
Invoke-Aws elbv2 wait load-balancer-available --load-balancer-arns $NlbArn | Out-Null

Set-StateValue $s "NlbArn" $NlbArn
Set-StateValue $s "NlbDns" $NlbDns
Set-StateValue $s "ApiTgArn" $ApiTg
Set-StateValue $s "IngressTgArn" $IngressTg
Save-State $s

Write-Step "Result"
$nodes | Format-Table Name, Role, Az, PrivateIp, PublicIp, InstanceId | Out-String | Write-Host
Write-Host "API endpoint : ${NlbDns}:6443"
Write-Host "App endpoint : http://$NlbDns  (Host: $AppHost)"
Write-Host "Target health shows 'unhealthy' until Steps 5 and 7 - that is expected."
Write-Host "`nSSH example  : ssh -i $KeyPath ubuntu@$($nodes[0].PublicIp)"
Write-Host "`nStep 3 done. Next: .\step4-prepare-nodes.ps1" -ForegroundColor Green
