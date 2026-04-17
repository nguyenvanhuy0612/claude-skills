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

Use `administrators_authorized_keys` not `authorized_keys` for Windows administrator accounts. Always fix ACLs on that file with `icacls /inheritance:r /grant Administrators:F /grant SYSTEM:F` — OpenSSH silently ignores the file if permissions are too permissive. Use Base64-encoded commands for any script longer than a few lines to avoid shell escaping issues. Never use `Start-Process` over SSH to launch visible windows — it will silently fail in Session 0. Always use Task Scheduler with `LogonType Interactive` for commands that need the user's desktop session. Use `explorer.exe` process owner to reliably identify the active interactive user. Always unregister the Scheduled Task after launching to avoid leftover task entries.

## Dependencies

Requires Win32-OpenSSH on the Windows target (downloaded automatically by the install script), PowerShell 5.1 or later on the Windows machine, and `iconv` on the client machine for Base64 encoding.
