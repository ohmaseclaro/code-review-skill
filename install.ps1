<#
.SYNOPSIS
  Install the code-review agent skill (Windows PowerShell 5.1+ or PowerShell 7).
  UNTESTED ON WINDOWS: written to mirror install.sh, never run on a Windows machine.
  Run it from a clone. Skill hosts only (claude, cline, agents); no adapters, no piped mode.
  Use install.sh under WSL or Git Bash if you need those.
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\install.ps1 -Host claude,agents -DryRun
  powershell -ExecutionPolicy Bypass -File .\install.ps1 -Host all -Yes
#>
param(
  [Alias("Host")][string]$Hosts = "detected",
  [ValidateSet("global","project")][string]$Scope = "global",
  [ValidateSet("copy","symlink")][string]$Mode = "copy",
  [string]$Path = "",
  [switch]$Update, [switch]$Uninstall, [switch]$List,
  [switch]$DryRun, [switch]$Yes, [switch]$Force
)
$ErrorActionPreference = "Stop"
$Name = "code-review"
$Marker = ".code-review-skill.installed"
$Src = Join-Path $PSScriptRoot "skills\$Name"
if (-not (Test-Path (Join-Path $Src "SKILL.md"))) { Write-Error "cannot find $Src\SKILL.md"; exit 1 }

$hostArg = $Hosts

if ($Scope -eq "project") {
  $root = (& git rev-parse --show-toplevel 2>$null); if (-not $root) { $root = (Get-Location).Path }
} else { $root = $env:USERPROFILE }

$dirs = @{ claude = ".claude"; cline = ".cline"; agents = ".agents" }
$alias = @{}
"codex","cursor","gemini","copilot","opencode","windsurf","amp","roo","kilo","goose","junie","zed" | ForEach-Object { $alias[$_] = "agents" }
$detect = @{ claude = ".claude"; cline = ".cline"; agents = ".agents"; codex = ".codex"; cursor = ".cursor"; gemini = ".gemini"; copilot = ".copilot"; roo = ".roo"; kilo = ".kilo"; junie = ".junie" }

$keys = @()
if ($hostArg -eq "all" -or $List) { $keys = @("claude","cline","agents") }
elseif ($hostArg -eq "detected") {
  foreach ($h in $detect.Keys) {
    if (Test-Path (Join-Path $env:USERPROFILE $detect[$h])) {
      $k = if ($alias.ContainsKey($h)) { $alias[$h] } else { $h }
      if ($keys -notcontains $k) { $keys += $k }
    }
  }
} else {
  foreach ($h in $hostArg.Split(",")) {
    $k = if ($alias.ContainsKey($h)) { $alias[$h] } else { $h }
    if (-not $dirs.ContainsKey($k)) { Write-Error "unknown host: $h"; exit 2 }
    if ($keys -notcontains $k) { $keys += $k }
  }
}
$bases = @()
foreach ($k in $keys) { $bases += ,@($k, (Join-Path (Join-Path $root $dirs[$k]) "skills")) }
if ($Path) { $bases += ,@("path", (Resolve-Path -LiteralPath $Path -ErrorAction SilentlyContinue | ForEach-Object { $_.Path }) ) }
if ($Path -and -not $bases[-1][1]) { $bases[-1][1] = [IO.Path]::GetFullPath($Path) }
if ($bases.Count -eq 0) { Write-Error "no hosts detected; pass -Host or -Path"; exit 2 }

function Get-State($d) {
  if (-not (Test-Path -LiteralPath $d)) { return "absent" }
  $item = Get-Item -LiteralPath $d -Force
  if ($item.LinkType -eq "SymbolicLink") {
    if ($item.Target -and ($item.Target | Select-Object -First 1) -like "*skills*$Name") {
      if (($item.Target | Select-Object -First 1) -eq $Src -and $Mode -eq "symlink") { return "ours-ok" } else { return "ours-old" }
    }
    return "foreign"
  }
  if (Test-Path -LiteralPath (Join-Path $d $Marker)) {
    $a = Get-ChildItem -LiteralPath $Src -Recurse -File | ForEach-Object { $_.FullName.Substring($Src.Length) + (Get-FileHash $_.FullName).Hash }
    $b = Get-ChildItem -LiteralPath $d -Recurse -File | Where-Object { $_.Name -ne $Marker } | ForEach-Object { $_.FullName.Substring($d.Length) + (Get-FileHash $_.FullName).Hash }
    if ($Mode -eq "copy" -and -not (Compare-Object $a $b)) { return "ours-ok" } else { return "ours-old" }
  }
  return "foreign"
}

if ($List) {
  foreach ($b in $bases) { $d = Join-Path $b[1] $Name; "{0,-8} {1}  [{2}]" -f $b[0], $d, (Get-State $d) }
  exit 0
}

$plan = @(); $collide = $false
foreach ($b in $bases) {
  $d = Join-Path $b[1] $Name; $st = Get-State $d
  if ($Uninstall) {
    if ($st -like "ours-*") { $plan += ,@("remove", $d) } else { $plan += ,@("skip", $d, $st) }
  } else {
    switch ($st) {
      "absent"   { $plan += ,@("create-$Mode", $d) }
      "ours-ok"  { $plan += ,@("ok", $d) }
      "ours-old" { if ($Update) { $plan += ,@("replace-$Mode", $d) } else { $plan += ,@("ok", $d, "outdated or other mode; use -Update") } }
      "foreign"  { if ($Force) { $plan += ,@("force-$Mode", $d) } else { $plan += ,@("collision", $d); $collide = $true } }
    }
  }
}
"Plan ($(if ($Uninstall) {'uninstall'} else {'install'}), scope=$Scope, mode=$Mode):"
$plan | ForEach-Object { "  {0,-14} {1} {2}" -f $_[0], $_[1], $(if ($_.Count -gt 2) { "(" + $_[2] + ")" }) }
if ($collide) { "Nothing written: a different item exists. Re-run with -Force to back it up."; exit 3 }
if ($DryRun) { "Dry run: nothing written."; exit 0 }
$todo = $plan | Where-Object { $_[0] -ne "ok" -and $_[0] -ne "skip" }
if (-not $todo) { "Nothing to do."; exit 0 }
if (-not $Yes) { $ans = Read-Host "Proceed? [Y/n]"; if ($ans -and $ans -notmatch '^(y|yes)$') { "Declined."; exit 7 } }

$backup = Join-Path $env:USERPROFILE (".code-review-skill-backups\" + (Get-Date -Format yyyyMMdd-HHmmss))
function Remove-Dest($d) { if ((Get-Item -LiteralPath $d -Force).LinkType) { (Get-Item -LiteralPath $d -Force).Delete() } else { Remove-Item -LiteralPath $d -Recurse -Force } }
function Put-Skill($d) {
  New-Item -ItemType Directory -Force -Path (Split-Path $d) | Out-Null
  if ($Mode -eq "symlink") { New-Item -ItemType SymbolicLink -Path $d -Target $Src | Out-Null }
  else { Copy-Item -LiteralPath $Src -Destination $d -Recurse; Set-Content -LiteralPath (Join-Path $d $Marker) "managed by code-review-skill install.ps1" }
}
foreach ($p in $todo) {
  $d = $p[1]
  switch -Wildcard ($p[0]) {
    "create-*"  { Put-Skill $d; "installed $d" }
    "replace-*" { Remove-Dest $d; Put-Skill $d; "updated $d" }
    "force-*"   { New-Item -ItemType Directory -Force -Path $backup | Out-Null; Move-Item -LiteralPath $d -Destination (Join-Path $backup ($d -replace '[:\\/]','_')); Put-Skill $d; "installed $d (backup in $backup)" }
    "remove"    { Remove-Dest $d; $parent = Split-Path $d; if (-not (Get-ChildItem -LiteralPath $parent -Force)) { Remove-Item -LiteralPath $parent }; "removed $d" }
  }
}
"Restart or reload your agent so it rescans skills."
