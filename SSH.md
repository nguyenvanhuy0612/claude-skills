# SSH Skill — appium-novawindows2-driver

Remote Windows machine: `admin@172.16.10.37`

---

## 1. Install OpenSSH Server on Windows

Run `scripts/install_ssh.ps1` **as Administrator** on the Windows machine. It:

1. Downloads Win32-OpenSSH to `C:\OpenSSH-Win64`
2. Runs `install-sshd.ps1`
3. Sets `sshd` and `ssh-agent` to auto-start
4. Opens firewall port 22

```powershell
# On Windows (as Administrator)
powershell -ExecutionPolicy Bypass -File scripts\install_ssh.ps1
```

After install, remove the stale host key from your Mac if needed:

```bash
ssh-keygen -R 172.16.10.37
```

---

## 2. Add SSH Public Key (Passwordless Login)

Adds your Mac's public key to the Windows `administrators_authorized_keys` file and fixes ACLs.

```bash
# On Mac — run once, requires password-based SSH for the first push
TARGET_IP="172.16.10.37"
TARGET_USER="admin"

# Generate key if missing
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

Reference: `scripts/mac/backup/ssh_helper.sh`

---

## 3. Run Commands Remotely

SSH always lands in **Session 0** (non-interactive, no desktop). Choose the method based on what the command needs:

| Scenario | Method |
|---|---|
| Read output, query state, file ops | Simple / inline |
| Long/complex script, avoid quoting hell | Base64-encoded |
| Needs GUI window, interactive desktop, or elevated user session | **Task Scheduler** |

---

### Simple one-liner

```bash
ssh admin@172.16.10.37 "powershell -Command \"Get-Process node\""
```

### Multi-step PowerShell (inline)

```bash
PS_CMD="Stop-Process -Name node -ErrorAction SilentlyContinue;"
PS_CMD+="Set-Location 'C:\\appium\\appium-novawindows2-driver';"
PS_CMD+="& './scripts/Start_Appium.ps1'"
ssh admin@172.16.10.37 "powershell -Command \"$PS_CMD\""
```

### Large/complex scripts (Base64-encoded to avoid quoting issues)

```bash
SCRIPT='Write-Host "Hello from remote"'
ENCODED=$(echo -n "$SCRIPT" | iconv -t UTF-16LE | base64 | tr -d '\n')
ssh admin@172.16.10.37 "powershell -EncodedCommand $ENCODED"
```

Reference: `scripts/mac/restart_appium_remotely.sh`

### Requires Session #0 / interactive desktop / specific user permissions → Task Scheduler

SSH Session 0 cannot create visible windows or interact with the user's desktop.  
Use this pattern whenever the command needs to:
- Show a GUI/console window in the logged-in user's session
- Run as the interactive user (not SYSTEM/SSH service account)
- Require desktop-level permissions (e.g. `RunLevel Highest` under the real user)

**How it works:** register a one-shot Scheduled Task under the interactive user, fire it, then clean up.

```powershell
# --- PowerShell to run on the remote machine (send via Base64-encoded SSH) ---

# Identify the logged-in user (owner of explorer.exe)
$u = (Get-Process explorer -IncludeUserName | Select-Object -First 1).UserName.Split('\')[-1]

# Replace this block with whatever command you need to run
$title     = 'AppiumServer'
$launchCmd = "[Console]::Title = '$title'; appium --relaxed-security --log-level debug:debug"
$actionArg = '-NoExit -Command "' + $launchCmd + '"'

$action    = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $actionArg
$principal = New-ScheduledTaskPrincipal -UserId $u -LogonType Interactive -RunLevel Highest

Register-ScheduledTask -TaskName 'RemoteTask' -Action $action -Principal $principal -Force | Out-Null
Start-ScheduledTask    -TaskName 'RemoteTask' | Out-Null

Start-Sleep 10   # give the task time to launch before unregistering
Unregister-ScheduledTask -TaskName 'RemoteTask' -Confirm:$false | Out-Null
```

Send from Mac via Base64:

```bash
# Write the PS script to a local file first, then:
ENCODED=$(iconv -t UTF-16LE < task.ps1 | base64 | tr -d '\n')
ssh admin@172.16.10.37 "powershell -EncodedCommand $ENCODED"
```

Full production example: `scripts/local/build_deploy_restart.ps1` — Step 6.

---

## 5. Build, Deploy & Restart (end-to-end)

```bash
# Mac — builds locally, SCPs zip, extracts, restarts Appium
./scripts/mac/build_deploy_restart.sh
```

What it does:
1. `npm run build`
2. `zip -r build.zip build package.json lib scripts`
3. `scp build.zip admin@172.16.10.37:C:/appium/appium-novawindows2-driver/`
4. Remote: stop node, clean dir (keep `node_modules`), unzip
5. Remote: start Appium via Scheduled Task (Session #0 workaround)
