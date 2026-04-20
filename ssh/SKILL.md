---
name: ssh
description: "Use this skill whenever the user wants to install OpenSSH server, configure passwordless login via SSH keys, or run commands remotely — on either a Mac or Windows target. Triggers include: 'SSH', 'remote execution', 'passwordless login', 'OpenSSH', deploy/restart/manage processes on a remote host, or Session 0 workaround via Task Scheduler on Windows. Do NOT use for general networking or non-SSH remote protocols."
license: MIT
---

# SSH Skill

Covers three operations — **install**, **passwordless login** (with stale key removal), and **run command** — for both Mac and Windows targets, from either a Mac/Linux or Windows client.

## Platform Matrix

| Client → Target | Install | Passwordless | Run Command |
|---|---|---|---|
| Mac → Mac | systemsetup | ssh-copy-id (.sh) | bash over SSH |
| Mac → Windows | PS1 over SSH | ssh-passwordless.sh | powershell over SSH |
| Windows → Windows | install-openssh.ps1 | ssh-passwordless.ps1 | powershell over SSH |
| Windows → Mac | systemsetup (manual) | ssh-passwordless.ps1 | ssh from PowerShell |

### Authorized keys file per target

| Target OS | File | Required permissions |
|---|---|---|
| macOS | `~/.ssh/authorized_keys` | `chmod 600`; `~/.ssh` must be `chmod 700` |
| Windows (admin) | `C:\ProgramData\ssh\administrators_authorized_keys` | `icacls /inheritance:r /grant Administrators:F /grant SYSTEM:F` |

---

## 1. Install OpenSSH Server

### Mac target

macOS ships OpenSSH. Enable it:

```bash
sudo systemsetup -setremotelogin on
sudo systemsetup -getremotelogin   # verify

mkdir -p ~/.ssh && chmod 700 ~/.ssh
touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys
```

### Windows target — `install-openssh.ps1`

Pinned to a known-good stable build. To upgrade, update `$VERSION` at the top.
Run as Administrator on the Windows machine:

```powershell
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
```

---

## 2. Passwordless Login

Always clear stale host keys first:

```bash
# Mac/Linux client
ssh-keygen -R <target-ip>
ssh-keygen -R [<target-ip>]:<port>   # non-standard port
```

```powershell
# Windows client
ssh-keygen -R <target-ip>
ssh-keygen -R ("[<target-ip>]:<port>")   # non-standard port
```

---

### `ssh-passwordless.sh` — Mac/Linux client → any target

```bash
#!/usr/bin/env bash
# Usage: ./ssh-passwordless.sh <target-ip> <username> [port] [mac|windows]
set -euo pipefail

TARGET_IP="${1:?Usage: $0 <ip> <user> [port] [mac|windows]}"
TARGET_USER="${2:?}"
PORT="${3:-22}"
TARGET_OS="${4:-windows}"
KEY_FILE="$HOME/.ssh/id_ed25519"

# Generate key if missing
if [ ! -f "$KEY_FILE" ]; then
    ssh-keygen -t ed25519 -f "$KEY_FILE" -N "" -C "$TARGET_USER@$TARGET_IP"
fi

PUB_KEY=$(cat "$KEY_FILE.pub")

# Clear stale host key
ssh-keygen -R "$TARGET_IP" 2>/dev/null || true
ssh-keygen -R "[$TARGET_IP]:$PORT" 2>/dev/null || true

if [ "$TARGET_OS" = "mac" ]; then
    # Mac target: use ssh-copy-id
    ssh-copy-id -i "$KEY_FILE.pub" -p "$PORT" "$TARGET_USER@$TARGET_IP"
else
    # Windows target: deploy via Base64-encoded PowerShell
    SCRIPT=$(cat <<'PSEOF'
param([string]$key)
$f = 'C:\ProgramData\ssh\administrators_authorized_keys'
New-Item -ItemType Directory -Force -Path (Split-Path $f) | Out-Null
if (-not (Test-Path $f)) { New-Item $f -ItemType File -Force | Out-Null }
$lines = Get-Content $f -ErrorAction SilentlyContinue
if ($lines -notcontains $key) { Add-Content $f $key; Write-Host 'Key added.' } else { Write-Host 'Key exists.' }
icacls $f /inheritance:r /grant 'SYSTEM:(F)' /grant 'Administrators:(F)' | Out-Null
$uf = "$env:USERPROFILE\.ssh\authorized_keys"
New-Item -ItemType Directory -Force -Path (Split-Path $uf) | Out-Null
if (-not (Test-Path $uf)) { New-Item $uf -ItemType File -Force | Out-Null }
$ul = Get-Content $uf -ErrorAction SilentlyContinue
if ($ul -notcontains $key) { Add-Content $uf $key }
PSEOF
)
    ENCODED=$(printf '%s' "$SCRIPT" | iconv -t UTF-16LE | base64 | tr -d '\n')
    ssh -o StrictHostKeyChecking=no -p "$PORT" "$TARGET_USER@$TARGET_IP" \
        "powershell -EncodedCommand $ENCODED -key '$PUB_KEY'"
fi

# Test passwordless
echo "Testing passwordless login..."
result=$(ssh -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=no \
    -i "$KEY_FILE" -p "$PORT" "$TARGET_USER@$TARGET_IP" "echo ok" 2>&1)

if [ "$result" = "ok" ]; then
    echo "Success: ssh -i $KEY_FILE -p $PORT $TARGET_USER@$TARGET_IP"
else
    echo "WARNING: test returned: $result"
    echo "Try: ssh -p $PORT $TARGET_USER@$TARGET_IP"
fi
```

---

### `ssh-passwordless.ps1` — Windows client → any target

```powershell
# Usage: .\ssh-passwordless.ps1 -RemoteHost <ip> [-RemoteUser admin] [-Port 22] [-TargetOS windows|mac]
param(
    [Parameter(Mandatory)][string]$RemoteHost,
    [string]$RemoteUser = "admin",
    [int]$Port          = 22,
    [ValidateSet("windows","mac")][string]$TargetOS = "windows"
)

$ErrorActionPreference = "Stop"
$KEY_FILE = "$env:USERPROFILE\.ssh\id_ed25519"

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

if ($TargetOS -eq "mac") {
    # Mac target: append to ~/.ssh/authorized_keys
    info "Deploying key to Mac target (password prompt)..."
    $cmd = "mkdir -p ~/.ssh && chmod 700 ~/.ssh && " +
           "grep -qF '$pubKey' ~/.ssh/authorized_keys 2>/dev/null || " +
           "echo '$pubKey' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && echo done"
    & ssh @sshArgs $cmd
} else {
    # Windows target: deploy via Base64-encoded PowerShell
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
info "Testing passwordless login..."
$result = & ssh -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=no `
    -i $KEY_FILE -p $Port "${RemoteUser}@${RemoteHost}" "echo ok" 2>&1

if ($result -eq "ok") {
    ok "Passwordless works."
    Write-Host "  Connect: ssh -i $KEY_FILE -p $Port $RemoteUser@$RemoteHost" -ForegroundColor Cyan
} else {
    Write-Host "  [WARN] Test returned: $result" -ForegroundColor Yellow
    Write-Host "  Try: ssh -p $Port $RemoteUser@$RemoteHost"
}
```

### Troubleshooting Windows passwordless

If the test still prompts for a password:
1. ACLs wrong: `icacls C:\ProgramData\ssh\administrators_authorized_keys` — only `SYSTEM` and `Administrators` allowed.
2. Wrong config: `sshd_config` must reference `administrators_authorized_keys`, not `%USERPROFILE%\.ssh\authorized_keys`.
3. Restart: `Restart-Service sshd`.

---

## 3. Run Command Remotely

### Mac target (from any client)

```bash
# One-liner
ssh -p 22 user@host "ls -la /tmp"

# Multi-line heredoc
ssh user@host bash << 'EOF'
cd /path/to/app
./start.sh
EOF
```

From Windows PowerShell:

```powershell
ssh user@host "ls -la /tmp"
ssh user@host "bash -c 'cd /path/to/app && ./start.sh'"
```

### Windows target

SSH into Windows lands in **Session 0** (non-interactive). Choose the method:

| Scenario | Method |
|---|---|
| Read output, query state, file ops | Simple inline |
| Long script, avoid quoting issues | Base64-encoded |
| GUI window, interactive desktop, user session | Task Scheduler |

**Simple one-liner (from Mac/Linux client):**

```bash
ssh user@host "powershell -Command \"Get-Process node\""
```

**Simple one-liner (from Windows client):**

```powershell
ssh user@host "powershell -Command `"Get-Process node`""
```

**Base64-encoded — recommended for complex scripts (Mac/Linux client):**

```bash
SCRIPT='Stop-Process -Name myapp -ErrorAction SilentlyContinue; Write-Host done'
ENCODED=$(echo -n "$SCRIPT" | iconv -t UTF-16LE | base64 | tr -d '\n')
ssh user@host "powershell -EncodedCommand $ENCODED"

# From a local .ps1 file:
ENCODED=$(iconv -t UTF-16LE < script.ps1 | base64 | tr -d '\n')
ssh user@host "powershell -EncodedCommand $ENCODED"
```

**Base64-encoded (Windows client):**

```powershell
$script  = 'Stop-Process -Name myapp -ErrorAction SilentlyContinue; Write-Host done'
$encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($script))
ssh user@host "powershell -EncodedCommand $encoded"

# From a local .ps1 file:
$encoded = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes("script.ps1"))
ssh user@host "powershell -EncodedCommand $encoded"
```

**Task Scheduler — for interactive desktop / visible windows:**

`Start-Process` over SSH silently spawns in Session 0. Use Task Scheduler with `LogonType Interactive`:

```powershell
# Send this block via Base64-encoded SSH from the client
$u = (Get-Process explorer -IncludeUserName | Select-Object -First 1).UserName.Split('\')[-1]

$cmd       = "Your-Command-Here --with-args"
$actionArg = '-NoExit -Command "' + $cmd + '"'

$action    = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $actionArg
$principal = New-ScheduledTaskPrincipal -UserId $u -LogonType Interactive -RunLevel Highest

Register-ScheduledTask -TaskName 'RemoteTask' -Action $action -Principal $principal -Force | Out-Null
Start-ScheduledTask    -TaskName 'RemoteTask' | Out-Null
Start-Sleep 10
Unregister-ScheduledTask -TaskName 'RemoteTask' -Confirm:$false | Out-Null
```

To target a window for later cleanup: prepend `[Console]::Title = 'MyApp';` to `$cmd`, then kill with `taskkill /fi "windowtitle eq MyApp"`.

---

## Critical Rules

- **Mac**: `authorized_keys` must be `chmod 600`; `~/.ssh` must be `chmod 700` — OpenSSH ignores the file if permissions are too open.
- **Windows**: use `administrators_authorized_keys` for admin accounts; fix ACLs with `icacls /inheritance:r /grant Administrators:F /grant SYSTEM:F` — OpenSSH silently ignores the file otherwise.
- Always run `ssh-keygen -R <host>` to clear stale host keys before re-deploying to a reimaged machine.
- Use Base64-encoded commands for any PowerShell script longer than a few lines.
- Never use `Start-Process` over SSH for visible windows on Windows — use Task Scheduler with `LogonType Interactive`.
- Use `explorer.exe` process owner to identify the active interactive user on Windows.
- Always unregister Scheduled Tasks after launch to avoid leftover entries.
- Pin `$VERSION` in `install-openssh.ps1` to a known-good release; update deliberately, not automatically.

## Dependencies

- **Mac target**: built-in OpenSSH (no install needed).
- **Windows target**: Win32-OpenSSH pinned build (downloaded by install script), PowerShell 5.1+.
- **Mac/Linux client**: `iconv`, `ssh-copy-id` (pre-installed on macOS/Linux).
- **Windows client**: built-in `ssh` / `ssh-keygen` (available since Windows 10 1809); PowerShell 5.1+.
