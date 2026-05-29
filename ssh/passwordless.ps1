# Set up passwordless SSH from this Windows machine to a remote host.
#
# Just run it — you'll be prompted for host, user, password, and target OS:
#     .\passwordless.ps1
#
# Or pass any of them up front to skip the matching prompt:
#     .\passwordless.ps1 -RemoteHost 10.0.0.5 -RemoteUser root -TargetOS linux
#
# Usage: .\passwordless.ps1 [-RemoteHost <ip>] [-RemoteUser <user>] [-RemotePassword <pw>] [-Port 22] [-TargetOS windows|mac|linux]
param(
    [string]$RemoteHost     = "",
    [string]$RemoteUser     = "",
    [string]$RemotePassword = "",
    [int]$Port              = 22,
    [ValidateSet("windows","mac","linux","")][string]$TargetOS = ""
)

$ErrorActionPreference = "Stop"
$KEY_FILE = "$env:USERPROFILE\.ssh\id_ed25519"

function ok($t)   { Write-Host "  [OK]   $t" -ForegroundColor Green }
function info($t) { Write-Host "  [INFO] $t" -ForegroundColor Cyan }
function err($t)  { Write-Host "  [ERR]  $t" -ForegroundColor Red; exit 1 }

# --- Prompt for anything not supplied on the command line ---
if ([string]::IsNullOrWhiteSpace($RemoteHost)) {
    $RemoteHost = Read-Host "Remote host (IP or name)"
    if ([string]::IsNullOrWhiteSpace($RemoteHost)) { err "Remote host is required." }
}
if ([string]::IsNullOrWhiteSpace($RemoteUser)) {
    $RemoteUser = Read-Host "Remote username [admin]"
    if ([string]::IsNullOrWhiteSpace($RemoteUser)) { $RemoteUser = "admin" }
}
if ([string]::IsNullOrWhiteSpace($TargetOS)) {
    $TargetOS = Read-Host "Target OS - windows / mac / linux [linux]"
    if ([string]::IsNullOrWhiteSpace($TargetOS)) { $TargetOS = "linux" }
}
$TargetOS = $TargetOS.ToLower()
if ($TargetOS -notin @("windows","mac","linux")) { err "Invalid TargetOS '$TargetOS' (use windows|mac|linux)." }
if ([string]::IsNullOrWhiteSpace($RemotePassword)) {
    $sec = Read-Host "Remote password (leave blank to type it at the SSH prompt)" -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
    $RemotePassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
}

# --- Generate key if missing ---
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

# --- Clear stale host keys ---
ssh-keygen -R $RemoteHost 2>&1 | Out-Null
if ($Port -ne 22) { ssh-keygen -R "[$RemoteHost]:$Port" 2>&1 | Out-Null }
ok "Cleared known_hosts for $RemoteHost"

# --- Non-interactive password auth via SSH_ASKPASS (when a password was supplied) ---
$askpassFile = $null
if ($RemotePassword -ne "") {
    $askpassFile = "$env:TEMP\ssh_askpass_$PID.bat"
    Set-Content $askpassFile "@echo $RemotePassword"
    $env:SSH_ASKPASS         = $askpassFile
    $env:SSH_ASKPASS_REQUIRE = "force"
    $env:DISPLAY             = "none"   # required by some OpenSSH builds
    info "Using the supplied password (non-interactive)."
} else {
    info "No password supplied - SSH will prompt interactively."
}

$sshArgs = @("-o","StrictHostKeyChecking=no","-o","PasswordAuthentication=yes",
             "-o","PubkeyAuthentication=no","-p",$Port,"${RemoteUser}@${RemoteHost}")

try {
    if ($TargetOS -eq "mac" -or $TargetOS -eq "linux") {
        info "Deploying key to $TargetOS target..."
        $cmd = "mkdir -p ~/.ssh && chmod 700 ~/.ssh && " +
               "grep -qF '$pubKey' ~/.ssh/authorized_keys 2>/dev/null || " +
               "echo '$pubKey' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && echo done"
        & ssh @sshArgs $cmd
    } else {
        info "Deploying key to windows target..."
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
} finally {
    # Always clean up the askpass helper and env vars
    if ($askpassFile -and (Test-Path $askpassFile)) { Remove-Item $askpassFile -Force }
    $env:SSH_ASKPASS = $null; $env:SSH_ASKPASS_REQUIRE = $null; $env:DISPLAY = $null
}

ok "Key deployed."

# --- Test passwordless login ---
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
