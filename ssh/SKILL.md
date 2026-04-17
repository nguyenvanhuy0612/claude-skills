---
name: ssh
description: "Use this skill whenever the user wants to set up SSH on a remote Windows machine, configure passwordless login via SSH keys, or run commands on a remote machine over SSH. Triggers include: any mention of 'SSH', 'remote execution', 'passwordless login', 'OpenSSH', or requests to deploy, restart, or manage processes on a remote Windows host. Also use when the task requires running a command in an interactive user session (Session 0 workaround) via Task Scheduler. Do NOT use for Linux/Mac SSH server setup, general networking, or non-SSH remote protocols."
license: MIT
---

# SSH Skill

A skill for setting up OpenSSH on a remote Windows machine, managing SSH keys for passwordless login, and executing commands remotely — including commands that require an interactive user session via Task Scheduler.

## Overview & Quick Reference

SSH into a Windows machine runs under **Session 0** (non-interactive, no desktop). This means most commands work fine over SSH, but anything that needs a visible window or desktop-level user permissions must be launched through a Scheduled Task targeting the interactive user session.

The skill covers four main operations: installing OpenSSH Server on Windows, adding a public key for passwordless login, running remote commands, and using Task Scheduler to run commands that require Session 0 / interactive desktop access.

## Installing OpenSSH Server on Windows

OpenSSH Server must be installed and running on the Windows target before any SSH connection is possible. The installation must be run as Administrator and covers downloading Win32-OpenSSH, running the installer, configuring services for auto-start, and opening the firewall.

Run the following on the Windows machine as Administrator:

```powershell
$U = "https://github.com/PowerShell/Win32-OpenSSH/releases/download/10.0.0.0p2-Preview/OpenSSH-Win64.zip"
$D = Get-Location; $Z = "$D\OpenSSH-Win64.zip"; $S = "$D\OpenSSH-Win64"; $T = "C:\OpenSSH-Win64"

if (-not (Test-Path $Z)) { Invoke-WebRequest $U -OutFile $Z }
if (-not (Test-Path $S)) { Expand-Archive $Z $D -Force }
if (-not (Test-Path $T)) { Copy-Item $S C:\ -Recurse -Force }

icacls "$T\libcrypto.dll" /grant Everyone:RX | Out-Null
powershell -ExecutionPolicy Bypass -File "$T\install-sshd.ps1"

New-Item -Path "$env:ProgramData\ssh\administrators_authorized_keys" -Force | Out-Null

Set-Service -Name sshd      -StartupType Automatic
Set-Service -Name ssh-agent -StartupType Automatic
Start-Service -Name ssh-agent
Start-Service -Name sshd

if (-not (Get-NetFirewallRule -Name sshd -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -Name sshd -DisplayName "OpenSSH SSH Server" `
        -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 `
        -Program "$T\sshd.exe"
}
```

After installing on a new machine, remove any stale host key on the client side:

```bash
ssh-keygen -R <windows-machine-ip>
```

## Adding a Public Key for Passwordless Login

Windows SSH uses `C:\ProgramData\ssh\administrators_authorized_keys` (not `~/.ssh/authorized_keys`) for administrator accounts. The file requires strict ACLs — only `Administrators` and `SYSTEM` may have access, otherwise OpenSSH silently ignores it.

### From a Linux/Mac client (sshpass available)

Run this once from the client machine. It generates a key if missing, then pushes the public key to the Windows machine idempotently (no duplicate entries) and fixes ACLs:

```bash
TARGET_IP="<windows-machine-ip>"
TARGET_USER="<username>"

[ ! -f ~/.ssh/id_rsa ] && ssh-keygen -t rsa -b 4096 -C "$TARGET_USER@$TARGET_IP"

PUB_KEY=$(cat ~/.ssh/id_rsa.pub)
REMOTE_CMD="\$path = 'C:\ProgramData\ssh\administrators_authorized_keys'; \
if (-not (Test-Path \$path)) { New-Item -Path \$path -Force | Out-Null }; \
\$content = Get-Content -Path \$path -Raw -ErrorAction SilentlyContinue; \
if (-not \$content -or -not \$content.Contains('$PUB_KEY')) { \
  Add-Content -Path \$path -Value '$PUB_KEY' -Encoding Ascii -Force }; \
& icacls \$path /inheritance:r /grant Administrators:F /grant SYSTEM:F"

ssh $TARGET_USER@$TARGET_IP "powershell -Command \"$REMOTE_CMD\""
ssh $TARGET_USER@$TARGET_IP "echo SSH key installed"
```

### From a Windows client (no sshpass — use Posh-SSH)

`sshpass` is not available on Windows. Use the **Posh-SSH** PowerShell module instead, which handles password-authenticated SSH natively. Run this from `pwsh` (PowerShell 7):

```powershell
# Install Posh-SSH once if needed
if (-not (Get-Module -ListAvailable -Name Posh-SSH)) {
    Install-Module -Name Posh-SSH -Force -Scope CurrentUser -Repository PSGallery
}
Import-Module Posh-SSH

$targetIP   = "<windows-machine-ip>"
$targetUser = "<username>"
$password   = "<password>"

# Generate key if missing
if (-not (Test-Path "$env:USERPROFILE\.ssh\id_rsa")) {
    ssh-keygen -t rsa -b 4096 -N '""' -C "$targetUser@$targetIP" -f "$env:USERPROFILE\.ssh\id_rsa"
}
$pubKey = (Get-Content "$env:USERPROFILE\.ssh\id_rsa.pub" -Raw).Trim()

$pass    = ConvertTo-SecureString $password -AsPlainText -Force
$cred    = New-Object System.Management.Automation.PSCredential($targetUser, $pass)
$session = New-SSHSession -ComputerName $targetIP -Credential $cred -AcceptKey -Force

# Detect remote OS: 'ver' returns Windows version string; on Linux it fails/returns nothing
$osCheck     = Invoke-SSHCommand -SessionId $session.SessionId -Command "ver" -TimeOut 10
$remoteIsWin = $osCheck.Output -match "Windows"

if ($remoteIsWin) {
    # Windows: write to administrators_authorized_keys and fix ACLs
    $script = @"
`$path = 'C:\ProgramData\ssh\administrators_authorized_keys'
if (-not (Test-Path `$path)) { New-Item -Path `$path -Force | Out-Null }
`$content = Get-Content -Path `$path -Raw -ErrorAction SilentlyContinue
if (-not `$content -or -not `$content.Contains('$pubKey')) {
    Add-Content -Path `$path -Value '$pubKey' -Encoding Ascii -Force
    Write-Host 'Key added'
} else { Write-Host 'Key already present' }
icacls `$path /inheritance:r /grant 'Administrators:F' /grant 'SYSTEM:F'
"@
    $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($script))
    $r = Invoke-SSHCommand -SessionId $session.SessionId -Command "powershell -EncodedCommand $encoded" -TimeOut 30
} else {
    # Linux: standard authorized_keys
    $cmds = @(
        "mkdir -p ~/.ssh && chmod 700 ~/.ssh",
        "touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys",
        "grep -qxF '$pubKey' ~/.ssh/authorized_keys || echo '$pubKey' >> ~/.ssh/authorized_keys"
    )
    foreach ($cmd in $cmds) {
        Invoke-SSHCommand -SessionId $session.SessionId -Command $cmd -TimeOut 15 | Out-Null
    }
}

$r.Output
Remove-SSHSession -SessionId $session.SessionId | Out-Null
Write-Host "Done — test with: ssh $targetUser@$targetIP"
```

**Key notes for the Windows-client approach:**
- `$IsWindows` is a reserved read-only variable in PowerShell — always use a different name (e.g. `$remoteIsWin`) for OS detection results.
- Use `ver` (not `echo`) to detect remote OS: `ver` returns a Windows version string on Windows and fails/returns nothing on Linux.
- Use Base64-encoded `-EncodedCommand` for the remote PowerShell script to avoid shell escaping issues with quotes and backslashes.
- The CLIXML blob in `$r.Error` is normal PowerShell progress serialization — check `$r.Output` for actual results.

## Running Commands Remotely

SSH always lands in Session 0. Choose the method based on what the command needs:

| Scenario | Method |
|---|---|
| Read output, query state, file operations | Simple / inline |
| Long or complex script, avoid quoting issues | Base64-encoded |
| Needs GUI window, interactive desktop, or elevated user session | Task Scheduler |

**Simple one-liner:**

```bash
ssh user@host "powershell -Command \"Get-Process node\""
```

**Multi-step inline:**

```bash
PS_CMD="Stop-Process -Name myapp -ErrorAction SilentlyContinue;"
PS_CMD+="Set-Location 'C:\\path\\to\\app';"
PS_CMD+="& './scripts/Start.ps1'"
ssh user@host "powershell -Command \"$PS_CMD\""
```

**Base64-encoded — recommended for complex scripts to avoid quoting issues:**

```bash
SCRIPT='Write-Host "Hello from remote"'
ENCODED=$(echo -n "$SCRIPT" | iconv -t UTF-16LE | base64 | tr -d '\n')
ssh user@host "powershell -EncodedCommand $ENCODED"
```

For multi-line scripts, write to a local file first then encode:

```bash
ENCODED=$(iconv -t UTF-16LE < script.ps1 | base64 | tr -d '\n')
ssh user@host "powershell -EncodedCommand $ENCODED"
```

**Task Scheduler — for commands that require Session 0 / interactive desktop / specific user permissions:**

SSH Session 0 cannot create visible windows or interact with the logged-in user's desktop. `Start-Process` launched over SSH will silently spawn in an invisible session. Use Task Scheduler whenever the command needs to show a console or GUI window, run as the interactive user rather than the SSH service account, or requires desktop-level permissions.

The interactive user is identified by finding the owner of `explorer.exe`. The task is created with `LogonType Interactive` and `RunLevel Highest`, placing it in the correct desktop session with full user permissions. After the task launches, it is immediately unregistered to avoid leftover entries.

```powershell
# Run on the remote machine — send via Base64-encoded SSH from the client
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

To set a window title for later identification (e.g. to kill by title), prepend `[Console]::Title = 'MyApp';` to the command string. This allows targeted cleanup with `taskkill /fi "windowtitle eq MyApp"`.

## Critical Rules Summary

Use `administrators_authorized_keys` not `authorized_keys` for Windows administrator accounts. Always fix ACLs on that file with `icacls /inheritance:r /grant Administrators:F /grant SYSTEM:F` — OpenSSH silently ignores the file if permissions are too permissive. Use Base64-encoded commands for any script longer than a few lines to avoid shell escaping issues. Never use `Start-Process` over SSH to launch visible windows — it will silently fail in Session 0. Always use Task Scheduler with `LogonType Interactive` for commands that need the user's desktop session. Use `explorer.exe` process owner to reliably identify the active interactive user. Always unregister the Scheduled Task after launching to avoid leftover task entries. On Windows clients, use Posh-SSH instead of sshpass (which is not available on Windows). Never use `$IsWindows` as a variable name — it is read-only in PowerShell. Use `ver` to detect remote Windows vs Linux over SSH.

## Dependencies

Requires Win32-OpenSSH on the Windows target (downloaded automatically by the install script), PowerShell 5.1 or later on the Windows machine, and `iconv` on the client machine for Base64 encoding. For pushing keys from a Windows client: Posh-SSH module (`Install-Module Posh-SSH`) and PowerShell 7 (`pwsh`).
