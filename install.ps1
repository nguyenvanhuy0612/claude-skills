# install.ps1 — install a skill from this repo into ~/.claude/skills/
# Usage: irm https://raw.githubusercontent.com/nguyenvanhuy0612/claude-skills/main/install.ps1 | iex
#        (installs all skills)
# Or:   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/nguyenvanhuy0612/claude-skills/main/install.ps1))) ssh
#        (installs one skill by name)
param([string]$Skill = "")

$REPO    = "nguyenvanhuy0612/claude-skills"
$DEST    = "$env:USERPROFILE\.claude\skills"
$API     = "https://api.github.com/repos/$REPO/contents"
$RAW     = "https://raw.githubusercontent.com/$REPO/main"

function ok($t)   { Write-Host "  [OK]   $t" -ForegroundColor Green }
function info($t) { Write-Host "  [INFO] $t" -ForegroundColor Cyan }
function err($t)  { Write-Host "  [ERR]  $t" -ForegroundColor Red }

function Install-Skill([string]$name) {
    info "Installing skill: $name"
    $files = Invoke-RestMethod "$API/$name" -UseBasicParsing -ErrorAction Stop
    $dir   = "$DEST\$name"
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    foreach ($f in $files) {
        if ($f.type -eq "file") {
            Invoke-WebRequest "$RAW/$name/$($f.name)" -OutFile "$dir\$($f.name)" -UseBasicParsing
        }
    }
    ok "Installed '$name' → $dir"
}

# Discover available skills (top-level folders containing SKILL.md)
$root    = Invoke-RestMethod $API -UseBasicParsing
$skills  = $root | Where-Object { $_.type -eq "dir" -and $_.name -notlike ".*" }

if ($Skill) {
    $target = $skills | Where-Object { $_.name -eq $Skill }
    if (-not $target) { err "Skill '$Skill' not found. Available: $($skills.name -join ', ')"; exit 1 }
    Install-Skill $Skill
} else {
    foreach ($s in $skills) { Install-Skill $s.name }
}
