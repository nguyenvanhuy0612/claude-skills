# Usage: .\passwordless.ps1 -RemoteHost <ip> [-RemoteUser admin] [-Port 22] [-TargetOS windows|mac|linux]
param(
    [Parameter(Mandatory)][string]$RemoteHost,
    [string]$RemoteUser = "",        # if empty, prompt (Enter = admin)
    [int]$Port          = 22,
    [ValidateSet("windows","mac","linux","")][string]$TargetOS = ""   # if empty, prompt
)

$ErrorActionPreference = "Stop"
$KEY_FILE = "$env:USERPROFILE\.ssh\id_ed25519"

# Prompt for the remote username if not supplied on the command line
if ([string]::IsNullOrWhiteSpace($RemoteUser)) {
    $RemoteUser = Read-Host "Remote username [admin]"
    if ([string]::IsNullOrWhiteSpace($RemoteUser)) { $RemoteUser = "admin" }
}

# Prompt for the target OS if not supplied (avoids silently defaulting to windows)
if ([string]::IsNullOrWhiteSpace($TargetOS)) {
    $TargetOS = Read-Host "Target OS - windows / mac / linux [linux]"
    if ([string]::IsNullOrWhiteSpace($TargetOS)) { $TargetOS = "linux" }
}
$TargetOS = $TargetOS.ToLower()
if ($TargetOS -notin @("windows","mac","linux")) {
    Write-Host "  [ERR]  Invalid TargetOS '$TargetOS' (use windows|mac|linux)" -ForegroundColor Red; exit 1
}

function ok($t)   { Write-Host "  [OK]   $t" -ForegroundColor Green }
function info($t) { Write-Host "  [INFO] $t" -ForegroundColor Cyan }
function err($t)  { Write-Host "  [ERR]  $t" -ForegroundColor Red; exit 1 }

# Generate key if missing
if (-not (Test-Path "$KEY_FILE.pub")) {
    info "Generating ed25519 key pair..."
    New-Item -ItemType Directory -Force -Path (Split-Path $KEY_FILE) | Out-Null
    ssh-keygen -t ed25519 -f $KEY_FILE -N '""' -C "$env:USERNAME@$env:COMPUTERNAME"
    if (-not (Test-Path "$KEY_FILE.pub")) { err "ssh-keygen failed." }
    ok "Key: $KEY_FILE.pub"
} else {
    ok "Key exists: $KEY_FILE.pub"
}

$pubKey = (Get-Content "$KEY_FILE.pub").Trim()

# Clear stale host keys
ssh-keygen -R $RemoteHost 2>&1 | Out-Null
if ($Port -ne 22) { ssh-keygen -R "[$RemoteHost]:$Port" 2>&1 | Out-Null }
ok "Cleared known_hosts for $RemoteHost"

$sshArgs = @("-o","StrictHostKeyChecking=no","-p",$Port,"${RemoteUser}@${RemoteHost}")

if ($TargetOS -eq "mac" -or $TargetOS -eq "linux") {
    info "Deploying key to $TargetOS target (password prompt)..."
    $cmd = "mkdir -p ~/.ssh && chmod 700 ~/.ssh && " +
           "grep -qF '$pubKey' ~/.ssh/authorized_keys 2>/dev/null || " +
           "echo '$pubKey' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && echo done"
    & ssh @sshArgs $cmd
} else {
    info "Deploying key to Windows target (password prompt)..."
    $remoteScript = @"
`$key  = '$pubKey'
`$f    = 'C:\ProgramData\ssh\administrators_authorized_keys'
New-Item -ItemType Directory -Force -Path (Split-Path `$f) | Out-Null
if (-not (Test-Path `$f)) { New-Item `$f -ItemType File -Force | Out-Null }
`$lines = Get-Content `$f -ErrorAction SilentlyContinue
if (`$lines -notcontains `$key) { Add-Content `$f `$key; Write-Host 'Key added.' } else { Write-Host 'Key exists.' }
icacls `$f /inheritance:r /grant 'SYSTEM:(F)' /grant 'Administrators:(F)' | Out-Null
`$uf = "`$env:USERPROFILE\.ssh\authorized_keys"
New-Item -ItemType Directory -Force -Path (Split-Path `$uf) | Out-Null
if (-not (Test-Path `$uf)) { New-Item `$uf -ItemType File -Force | Out-Null }
`$ul = Get-Content `$uf -ErrorAction SilentlyContinue
if (`$ul -notcontains `$key) { Add-Content `$uf `$key }
Write-Host 'done'
"@
    $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($remoteScript))
    & ssh @sshArgs "powershell -EncodedCommand $encoded"
    if ($LASTEXITCODE -ne 0) { err "Deploy failed (exit=$LASTEXITCODE)." }
}

ok "Key deployed."

# Test passwordless
# Drop stderr (login banners / TMOUT warnings) so they don't trip ErrorActionPreference=Stop,
# and match 'ok' loosely since servers may prepend banner text.
info "Testing passwordless login..."
$prevEAP = $ErrorActionPreference
$ErrorActionPreference = "Continue"
$result = & ssh -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=no `
    -i $KEY_FILE -p $Port "${RemoteUser}@${RemoteHost}" "echo ok" 2>$null
$ErrorActionPreference = $prevEAP

if ($result -match '\bok\b') {
    ok "Passwordless works."
    Write-Host "  Connect: ssh -i $KEY_FILE -p $Port $RemoteUser@$RemoteHost" -ForegroundColor Cyan
} else {
    Write-Host "  [WARN] Test returned: $result" -ForegroundColor Yellow
    Write-Host "  Try: ssh -i $KEY_FILE -p $Port $RemoteUser@$RemoteHost"
}
