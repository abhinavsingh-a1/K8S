# Shared helpers. Dot-sourced by every step script:  . "$PSScriptRoot\lib.ps1"

. "$PSScriptRoot\config.ps1"
$ErrorActionPreference = "Stop"

function Write-Step([string]$Text) {
    Write-Host ""
    Write-Host "==> $Text" -ForegroundColor Cyan
}

# Run an AWS CLI command in $Region, return text output, throw on failure.
function Invoke-Aws {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$AwsArgs)
    # 'Continue' here: in Windows PowerShell 5.1, stderr from a native exe
    # combined with 'Stop' becomes an exception before we can read it.
    $ErrorActionPreference = "Continue"
    $out = & aws @AwsArgs --region $Region --output text 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "aws $($AwsArgs -join ' ') failed:`n$out"
    }
    if ($null -eq $out) { return "" }
    return ($out | Out-String).Trim()
}

# Like Invoke-Aws but never throws; returns $null on failure.
function Try-Aws {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$AwsArgs)
    $ErrorActionPreference = "Continue"
    $out = & aws @AwsArgs --region $Region --output text 2>&1
    if ($LASTEXITCODE -ne 0) { return $null }
    return ($out | Out-String).Trim()
}

# Add or overwrite a property on the state object.
function Set-StateValue($State, [string]$Name, $Value) {
    $State | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
}

function Get-State {
    if (-not (Test-Path $StateFile)) { throw "No state file. Run the earlier steps first ($StateFile)." }
    return Get-Content $StateFile -Raw | ConvertFrom-Json
}

function Save-State($State) {
    $State | ConvertTo-Json -Depth 10 | Set-Content -Path $StateFile -Encoding UTF8
}

function Get-Node([string]$Name) {
    $node = (Get-State).Nodes | Where-Object { $_.Name -eq $Name }
    if (-not $node) { throw "Node $Name not found in state.json" }
    return $node
}

$SshOptions = @("-i", $KeyPath, "-o", "StrictHostKeyChecking=accept-new",
                "-o", "ConnectTimeout=15", "-o", "ServerAliveInterval=30")

# Forget old host keys for these IPs (AWS reuses public IPs after rebuilds).
function Clear-KnownHosts([string[]]$Ips) {
    $ErrorActionPreference = "Continue"
    foreach ($ip in $Ips) {
        if ($ip -and $ip -ne "None") { & ssh-keygen -R $ip 2>&1 | Out-Null }
    }
}

# Run a command on a node over SSH, streaming output to the console.
function Invoke-Node([string]$Name, [string]$Command) {
    $ip = (Get-Node $Name).PublicIp
    & ssh @SshOptions "ubuntu@$ip" $Command
    if ($LASTEXITCODE -ne 0) { throw "Command failed on ${Name}: $Command" }
}

# Run a command on a node over SSH and return its output.
function Get-NodeOutput([string]$Name, [string]$Command) {
    $ip = (Get-Node $Name).PublicIp
    $out = & ssh @SshOptions "ubuntu@$ip" $Command
    if ($LASTEXITCODE -ne 0) { throw "Command failed on ${Name}: $Command" }
    return ($out | Out-String).Trim()
}

# Copy local files/folders to a node's home directory.
function Copy-ToNode([string]$Name, [string[]]$Paths, [string]$Dest = "~/") {
    $ip = (Get-Node $Name).PublicIp
    & scp @SshOptions -r @Paths "ubuntu@${ip}:$Dest"
    if ($LASTEXITCODE -ne 0) { throw "scp to $Name failed" }
}

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Point $AppHost to an IP in the Windows hosts file (needs Administrator).
function Set-HostsEntry([string]$Ip) {
    $hosts = "$env:SystemRoot\System32\drivers\etc\hosts"
    $pattern = "\s" + [regex]::Escape($AppHost) + "\s*$"
    $lines = Get-Content $hosts | Where-Object { $_ -notmatch $pattern }
    if ($Ip) { $lines += "$Ip $AppHost" }
    Set-Content -Path $hosts -Value $lines -Encoding ASCII
    ipconfig /flushdns | Out-Null
}
