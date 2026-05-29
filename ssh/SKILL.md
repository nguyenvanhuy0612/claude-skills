---
name: ssh
description: "Use this skill whenever the user wants to install OpenSSH server, configure passwordless login via SSH keys, or run commands remotely — on a Mac, Windows, or Linux target. Triggers include: 'SSH', 'remote execution', 'passwordless login', 'OpenSSH', deploy/restart/manage processes on a remote host, or Session 0 workaround via Task Scheduler on Windows. Do NOT use for general networking or non-SSH remote protocols."
license: MIT
---

# SSH Skill

Three operations — **install** OpenSSH, set up **passwordless login**, and **run commands remotely** — across Mac, Windows, and Linux, from either a Unix or Windows client.

The install and passwordless steps are handled by the bundled scripts (below); you normally just run one and follow the prompts. The **Run Command Remotely** section is reference material — read it, there is no script for it.

## Scripts in this skill

| Script | Run it on | What it does |
|---|---|---|
| `install.ps1` | the Windows **target** (as Administrator) | Downloads a pinned Win32-OpenSSH build, registers `sshd`/`ssh-agent`, sets ACLs on `administrators_authorized_keys`, opens the firewall, starts the services. `-Port N` to change port. |
| `passwordless.ps1` | a Windows **client** | Generates a key if needed, deploys it to the target, verifies key-only login. Targets windows/mac/linux. |
| `passwordless.sh` | a Mac/Linux **client** | Same as above, from a Unix client. |

Run a passwordless script with **no arguments** and it prompts for host, user, target OS, and password, then sets everything up — *run → enter creds → success*. See [§2](#2-passwordless-login).

## Platform matrix

| Client → Target | Install | Passwordless | Run command |
|---|---|---|---|
| Mac/Linux → Mac/Linux | systemsetup / built-in | `passwordless.sh` | bash over SSH |
| Mac/Linux → Windows | bootstrap via RDP, then `install.ps1` | `passwordless.sh` | powershell over SSH |
| Windows → Windows | `install.ps1` | `passwordless.ps1` | powershell over SSH |
| Windows → Mac/Linux | systemsetup / built-in | `passwordless.ps1` | ssh from PowerShell |

### Authorized-keys file per target

| Target OS | File | Required permissions |
|---|---|---|
| macOS / Linux | `~/.ssh/authorized_keys` | `chmod 600`; `~/.ssh` must be `chmod 700` |
| Windows (admin) | `C:\ProgramData\ssh\administrators_authorized_keys` | `icacls /inheritance:r /grant Administrators:F /grant SYSTEM:F` |

OpenSSH **silently ignores** an authorized-keys file whose permissions are too loose — this is the #1 cause of "still asks for a password."

---

## 1. Install OpenSSH server

### Mac / Linux target

macOS and most Linux distros already ship OpenSSH. On macOS, enable the server:

```bash
sudo systemsetup -setremotelogin on
sudo systemsetup -getremotelogin            # verify
mkdir -p ~/.ssh && chmod 700 ~/.ssh
touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys
```

(On Linux, ensure `sshd` is installed and running, e.g. `sudo systemctl enable --now ssh`.)

### Windows target

Run **`install.ps1` as Administrator** on the Windows machine. It pins a known-good Win32-OpenSSH release (bump `$VERSION` at the top to upgrade), installs to `C:\OpenSSH-Win64`, registers and auto-starts `sshd` + `ssh-agent`, points `sshd_config` at `administrators_authorized_keys`, opens the firewall, and adds OpenSSH to `PATH`. Pass `-Port N` for a non-default port.

#### Bootstrap via RDP (when you can't copy a file onto the box yet)

Paste one of these into a PowerShell session over RDP; afterward use `passwordless.*` as normal.

**Admin — already in an elevated PowerShell (Win+X → A):**

```powershell
$t=$env:TEMP
iwr https://github.com/PowerShell/Win32-OpenSSH/releases/latest/download/OpenSSH-Win64.zip -Out $t\s.zip
Expand-Archive $t\s.zip $t -Force
$d=ls $t -d|?{$_.Name-like'OpenSSH*'}|select -f 1
cp $d.FullName C:\ -r -Force
if($d.Name-ne'OpenSSH-Win64'){ren C:\$($d.Name) OpenSSH-Win64}
powershell -ep Bypass -NonI -File C:\OpenSSH-Win64\install-sshd.ps1
Set-Service sshd,ssh-agent -StartupType Automatic
Start-Service ssh-agent,sshd
netsh advfirewall firewall add rule name=sshd protocol=TCP dir=in localport=22 action=allow|Out-Null
$f='C:\ProgramData\ssh\administrators_authorized_keys'
if(!(Test-Path $f)){ni $f -Force}
icacls $f /inheritance:r /grant 'SYSTEM:(F)' /grant 'Administrators:(F)'|Out-Null
```

**User — non-elevated PowerShell (triggers a UAC prompt):**

```powershell
Start-Process powershell -Verb RunAs -Wait -Args @(
  '-NoP','-ep','Bypass','-c',
  '$t=$env:TEMP;iwr https://github.com/PowerShell/Win32-OpenSSH/releases/latest/download/OpenSSH-Win64.zip -Out $t\s.zip;Expand-Archive $t\s.zip $t -Force;$d=ls $t -d|?{$_.Name-like''OpenSSH*''}|select -f 1;cp $d.FullName C:\ -r -Force;if($d.Name-ne''OpenSSH-Win64''){ren C:\$($d.Name) OpenSSH-Win64};powershell -ep Bypass -NonI -File C:\OpenSSH-Win64\install-sshd.ps1;Set-Service sshd,ssh-agent -StartupType Automatic;Start-Service ssh-agent,sshd;netsh advfirewall firewall add rule name=sshd protocol=TCP dir=in localport=22 action=allow|Out-Null;$f=''C:\ProgramData\ssh\administrators_authorized_keys'';if(!(Test-Path $f)){ni $f -Force};icacls $f /inheritance:r /grant ''SYSTEM:(F)'' /grant ''Administrators:(F)''|Out-Null'
)
```

> Inside the user one-liner, `''` is an escaped literal `'` within the single-quoted `-Args` string.

---

## 2. Passwordless login

From the **client**, run the matching script and follow the prompts:

```powershell
# Windows client
.\passwordless.ps1
# non-interactive: .\passwordless.ps1 -RemoteHost <ip> -RemoteUser <user> -RemotePassword <pw> -TargetOS windows|mac|linux [-Port 22]
```

```bash
# Mac/Linux client
./passwordless.sh
# non-interactive: ./passwordless.sh <host> <user> <port> <windows|mac|linux> <password>
```

Each script: generates an `ed25519` key if you don't have one, clears stale host keys, deploys the public key to the target's authorized-keys file (Unix branch for mac/linux, Base64 PowerShell for windows), and verifies that key-only login works.

- **Password handling** — supply the password and the deploy runs non-interactively (Windows uses a temp `SSH_ASKPASS` helper; Mac/Linux uses `sshpass`). Leave it blank to type it at the SSH prompt instead.
- **Headless use** — pass every value as an argument/param so nothing blocks on a prompt.

Stale host keys (a reimaged host reuses its IP) cause `REMOTE HOST IDENTIFICATION HAS CHANGED`. The scripts clear them automatically; to do it by hand:

```bash
ssh-keygen -R <host>                 # default port
ssh-keygen -R "[<host>]:<port>"      # non-standard port
```

### Troubleshooting Windows passwordless

If login still prompts for a password:
1. **ACLs** — `icacls C:\ProgramData\ssh\administrators_authorized_keys` should list only `SYSTEM` and `Administrators`.
2. **Config** — `sshd_config` must reference `administrators_authorized_keys`, not `%USERPROFILE%\.ssh\authorized_keys`.
3. **Restart** — `Restart-Service sshd`.

---

## 3. Run command remotely

No script for this — these are the patterns to use directly.

### Mac / Linux target (from any client)

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

SSH into Windows lands in **Session 0** (non-interactive). Pick the method by what you need:

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

**Task Scheduler — for an interactive desktop / visible window:**

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

## Critical rules

- **Run a passwordless script and follow the prompts** — host, user (Enter = admin), target OS (Enter = linux), password. For headless/background use, pass every value as an arg/param so nothing blocks on a prompt.
- **Authorized-keys permissions matter** — Mac/Linux: `authorized_keys` `chmod 600`, `~/.ssh` `chmod 700`. Windows admin accounts: `administrators_authorized_keys` with ACLs `icacls /inheritance:r /grant Administrators:F /grant SYSTEM:F`. Too-loose permissions are silently ignored.
- **Clear stale host keys** with `ssh-keygen -R <host>` before re-deploying to a reimaged machine.
- **Base64-encode** any PowerShell longer than a few lines sent over SSH.
- **Never `Start-Process` over SSH for visible windows** — it spawns in Session 0. Use Task Scheduler with `LogonType Interactive`, identify the active user via the `explorer.exe` process owner, and unregister the task after launch.
- **Pin `$VERSION` in `install.ps1`** to a known-good release; upgrade deliberately.

## Dependencies

- **Mac/Linux target**: built-in OpenSSH (enable the server; no install script needed).
- **Windows target**: Win32-OpenSSH pinned build (downloaded by `install.ps1`), PowerShell 5.1+.
- **Mac/Linux client**: `iconv`, `ssh-copy-id` (pre-installed on macOS/Linux); `sshpass` only to pass a password non-interactively (macOS: `brew install sshpass`; Debian/Ubuntu: `apt install sshpass`).
- **Windows client**: built-in `ssh` / `ssh-keygen` (Windows 10 1809+); PowerShell 5.1+.
