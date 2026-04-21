#Requires -RunAsAdministrator
param([int]$Port = 22)

$VERSION     = "10.0.0.0p2-Preview"   # update here to pin a different release
$URL         = "https://github.com/PowerShell/Win32-OpenSSH/releases/download/$VERSION/OpenSSH-Win64.zip"
$INSTALL_DIR = "C:\OpenSSH-Win64"
$DATA_DIR    = "C:\ProgramData\ssh"
$AUTH_KEYS   = "$DATA_DIR\administrators_authorized_keys"
$SSHD_EXE    = "$INSTALL_DIR\sshd.exe"
$AGENT_EXE   = "$INSTALL_DIR\ssh-agent.exe"

function ok($t)   { Write-Host "  [OK]   $t" -ForegroundColor Green }
function info($t) { Write-Host "  [INFO] $t" -ForegroundColor Cyan }
function err($t)  { Write-Host "  [ERR]  $t" -ForegroundColor Red }

# --- Download & extract ---
if (-not (Test-Path $INSTALL_DIR)) {
    $zip = "$env:TEMP\OpenSSH-Win64.zip"
    info "Downloading Win32-OpenSSH $VERSION..."
    Invoke-WebRequest $URL -OutFile $zip -UseBasicParsing
    Expand-Archive $zip $env:TEMP -Force
    $src = Get-ChildItem $env:TEMP -Directory |
           Where-Object { $_.Name -like "OpenSSH-Win64*" } |
           Select-Object -First 1
    Copy-Item $src.FullName "C:\" -Recurse -Force
    if ($src.Name -ne "OpenSSH-Win64") { Rename-Item "C:\$($src.Name)" "OpenSSH-Win64" }
    Remove-Item $zip -Force -ErrorAction SilentlyContinue
    ok "Installed to $INSTALL_DIR"
} else {
    ok "Already installed: $INSTALL_DIR"
}

# --- Fix permissions on all binaries ---
foreach ($f in @("sshd.exe","ssh-agent.exe","ssh.exe","ssh-add.exe","sftp.exe","scp.exe","libcrypto.dll")) {
    $p = "$INSTALL_DIR\$f"
    if (Test-Path $p) {
        icacls $p /grant "SYSTEM:(RX)" /grant "Administrators:(RX)" 2>&1 | Out-Null
    }
}
ok "Binary permissions set."

# --- Run bundled installer (registers services) ---
$installScript = "$INSTALL_DIR\install-sshd.ps1"
if (Test-Path $installScript) {
    info "Running install-sshd.ps1..."
    & powershell.exe -ExecutionPolicy Bypass -NonInteractive -File $installScript 2>&1 |
        ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
}

# --- Ensure services registered & auto-start ---
foreach ($pair in @(("sshd",$SSHD_EXE,"OpenSSH SSH Server"),("ssh-agent",$AGENT_EXE,"OpenSSH Authentication Agent"))) {
    $name, $exe, $disp = $pair
    if (-not (Get-Service $name -ErrorAction SilentlyContinue)) {
        sc.exe create $name "binPath=$exe" start= auto "DisplayName=$disp" 2>&1 | Out-Null
    }
    sc.exe config $name start= auto 2>&1 | Out-Null
}

# --- Authorized keys file + ACLs ---
New-Item -ItemType Directory -Force -Path $DATA_DIR | Out-Null
if (-not (Test-Path $AUTH_KEYS)) { New-Item $AUTH_KEYS -ItemType File -Force | Out-Null }
icacls $AUTH_KEYS /inheritance:r /grant "SYSTEM:(F)" /grant "Administrators:(F)" 2>&1 | Out-Null
ok "Authorized keys: $AUTH_KEYS"

# --- sshd_config: point to administrators_authorized_keys ---
$cfg = "$DATA_DIR\sshd_config"
if (-not (Test-Path $cfg)) { Copy-Item "$INSTALL_DIR\sshd_config_default" $cfg -ErrorAction SilentlyContinue }
if (Test-Path $cfg) {
    $c = Get-Content $cfg -Raw
    if ($c -notmatch "administrators_authorized_keys") {
        $c = $c -replace "#?AuthorizedKeysFile\s+[^\r\n]*",
                          "AuthorizedKeysFile __PROGRAMDATA__/ssh/administrators_authorized_keys"
        if ($Port -ne 22) { $c = $c -replace "#?Port\s+\d+", "Port $Port" }
        [System.IO.File]::WriteAllText($cfg, $c, [System.Text.UTF8Encoding]::new($false))
        ok "sshd_config updated."
    }
}

# --- Firewall ---
$ruleName = "OpenSSH-sshd-$Port"
if (-not (Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -Name $ruleName -DisplayName "OpenSSH Server (port $Port)" `
        -Direction Inbound -Protocol TCP -Action Allow -LocalPort $Port `
        -Program $SSHD_EXE | Out-Null
    ok "Firewall rule created for port $Port."
}

# --- Add to system PATH ---
$path = [System.Environment]::GetEnvironmentVariable("PATH", "Machine")
if ($path -notlike "*OpenSSH*") {
    [System.Environment]::SetEnvironmentVariable("PATH", "$path;$INSTALL_DIR", "Machine")
    ok "Added $INSTALL_DIR to PATH."
}

# --- Start services ---
Start-Service ssh-agent -ErrorAction SilentlyContinue; Start-Sleep 1
Start-Service sshd      -ErrorAction SilentlyContinue; Start-Sleep 2

foreach ($name in @("sshd","ssh-agent")) {
    $svc = Get-Service $name -ErrorAction SilentlyContinue
    $col = if ($svc.Status -eq "Running") { "Green" } else { "Red" }
    Write-Host "  $name : $($svc.Status)" -ForegroundColor $col
}

$ip = Get-NetIPAddress -AddressFamily IPv4 |
      Where-Object { $_.IPAddress -notlike "127.*" -and $_.PrefixOrigin -in @("Dhcp","Manual") } |
      Select-Object -First 1 -ExpandProperty IPAddress
if ($ip) { Write-Host "  Connect: ssh $env:USERNAME@$ip -p $Port" -ForegroundColor Cyan }
