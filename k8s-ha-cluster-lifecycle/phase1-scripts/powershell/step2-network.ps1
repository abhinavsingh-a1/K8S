# Step 2 - key pair and security groups in the default VPC.
#
#  k8s-ha-nodes : SSH + NodePorts from your IP, everything between nodes,
#                 6443 and 30080 from inside the VPC (the NLB forwards from there)
#  k8s-ha-nlb   : the load balancer accepts 80 from your IP, and 6443 from
#                 anywhere (nodes reach the API through the NLB's public IPs)
. "$PSScriptRoot\lib.ps1"

Write-Step "Region $Region - checking AWS credentials"
Invoke-Aws sts get-caller-identity --query Arn

$MyIp = (Invoke-RestMethod -Uri "https://checkip.amazonaws.com").Trim() + "/32"
Write-Host "Your public IP: $MyIp"

Write-Step "Default VPC"
$VpcId = Invoke-Aws ec2 describe-vpcs --filters Name=isDefault,Values=true --query "Vpcs[0].VpcId"
if ($VpcId -eq "None" -or -not $VpcId) {
    Write-Host "No default VPC - creating one"
    $VpcId = Invoke-Aws ec2 create-default-vpc --query "Vpc.VpcId"
}
$VpcCidr = Invoke-Aws ec2 describe-vpcs --vpc-ids $VpcId --query "Vpcs[0].CidrBlock"
Write-Host "VPC $VpcId ($VpcCidr)"

Write-Step "Key pair $KeyName"
$existingKey = Try-Aws ec2 describe-key-pairs --key-names $KeyName
if ($existingKey) {
    Write-Host "Key pair already exists in AWS."
    if (-not (Test-Path $KeyPath)) { throw "Key exists in AWS but $KeyPath is missing. Delete the AWS key pair or fix `$KeyPath in config.ps1." }
} else {
    New-Item -ItemType Directory -Force -Path (Split-Path $KeyPath) | Out-Null
    $material = Invoke-Aws ec2 create-key-pair --key-name $KeyName --key-type rsa --query KeyMaterial
    # ASCII + LF: OpenSSH rejects UTF-16 files that PowerShell 5.1 writes with '>'
    [System.IO.File]::WriteAllText($KeyPath, ($material -replace "`r", "") + "`n", [System.Text.Encoding]::ASCII)
    icacls $KeyPath /inheritance:r | Out-Null
    icacls $KeyPath /grant:r "$($env:USERNAME):R" | Out-Null
    Write-Host "Saved private key to $KeyPath"
}

function Get-OrCreateSg([string]$Name, [string]$Description) {
    $id = Invoke-Aws ec2 describe-security-groups --filters "Name=group-name,Values=$Name" "Name=vpc-id,Values=$VpcId" --query "SecurityGroups[0].GroupId"
    if ($id -and $id -ne "None") { Write-Host "$Name exists: $id"; return $id }
    $id = Invoke-Aws ec2 create-security-group --group-name $Name --description $Description --vpc-id $VpcId `
        --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=$Name},{Key=Project,Value=$Project}]" --query GroupId
    Write-Host "Created $Name : $id"
    return $id
}

# Ignore "rule already exists" so the script can be rerun.
function Add-Rule([string]$SgId, [string[]]$RuleArgs) {
    $ErrorActionPreference = "Continue"
    $out = & aws ec2 authorize-security-group-ingress --group-id $SgId @RuleArgs --region $Region --output text 2>&1
    if ($LASTEXITCODE -ne 0 -and ($out | Out-String) -notmatch "InvalidPermission.Duplicate") {
        throw "Adding rule failed: $out"
    }
}

Write-Step "Security groups"
$NodesSg = Get-OrCreateSg "$Project-nodes" "kubeadm HA cluster nodes"
$NlbSg   = Get-OrCreateSg "$Project-nlb"   "kubeadm HA cluster load balancer"

Add-Rule $NodesSg @("--protocol", "tcp", "--port", "22",          "--cidr", $MyIp)
Add-Rule $NodesSg @("--protocol", "tcp", "--port", "30000-32767", "--cidr", $MyIp)
Add-Rule $NodesSg @("--protocol", "tcp", "--port", "6443",        "--cidr", $VpcCidr)
Add-Rule $NodesSg @("--protocol", "tcp", "--port", "30080",       "--cidr", $VpcCidr)
Add-Rule $NodesSg @("--ip-permissions", "IpProtocol=-1,UserIdGroupPairs=[{GroupId=$NodesSg}]")

Add-Rule $NlbSg @("--protocol", "tcp", "--port", "80",   "--cidr", $MyIp)
# The NLB is internet-facing: its DNS name resolves to PUBLIC IPs even inside
# the VPC, so nodes reach it with their public IPs (which change on restart).
# Open 6443 to all; the API still requires TLS certificates/tokens.
# Enterprise alternative: a separate internal NLB for the API.
Add-Rule $NlbSg @("--protocol", "tcp", "--port", "6443", "--cidr", "0.0.0.0/0")

$state = [ordered]@{
    Region = $Region; VpcId = $VpcId; VpcCidr = $VpcCidr; MyIp = $MyIp
    NodesSg = $NodesSg; NlbSg = $NlbSg; Nodes = @()
}
if (Test-Path $StateFile) {
    $old = Get-State
    if ($old.Nodes) { $state.Nodes = $old.Nodes }
    foreach ($p in "NlbArn", "NlbDns", "ApiTgArn", "IngressTgArn") { if ($old.$p) { $state[$p] = $old.$p } }
}
Save-State $state

Write-Step "Verify"
Invoke-Aws ec2 describe-security-groups --group-ids $NodesSg $NlbSg `
    --query "SecurityGroups[].{Name:GroupName,Rules:IpPermissions[].[IpProtocol,FromPort,ToPort]}" | Write-Host
Write-Host "`nStep 2 done. Next: .\step3-instances.ps1" -ForegroundColor Green
