# Sahayogi Nepal - setup for Windows PowerShell (VS Code terminal)
# Run from the repo root:   .\scripts\setup.ps1
# If blocked:  Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")

function Need($cmd, $hint) {
  if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
    Write-Host "X missing: $cmd - $hint" -ForegroundColor Red
    return $true
  }
  return $false
}
function Run($label, [scriptblock]$block) {
  Write-Host "-> $label" -ForegroundColor Cyan
  & $block
  if ($LASTEXITCODE -ne 0) { throw "Step failed: $label" }
}

$missing = $false
if (Need "git" "https://git-scm.com/download/win") { $missing = $true }
if (Need "node" "https://nodejs.org (v20+)") { $missing = $true }
if (Need "npm" "comes with Node") { $missing = $true }
if (Need "docker" "Docker Desktop, needed for local Supabase") { $missing = $true }
if (Need "supabase" "scoop install supabase  (or: npm i -g supabase)") { $missing = $true }
if (Need "flutter" "https://docs.flutter.dev/get-started/install/windows") { $missing = $true }
if ($missing) { Write-Host "Install the missing tools above, then re-run." -ForegroundColor Yellow; exit 1 }

Run "admin web dependencies" { Push-Location apps/admin; npm install; $c = $LASTEXITCODE; Pop-Location; $global:LASTEXITCODE = $c }
if (-not (Test-Path apps/admin/.env)) { Copy-Item apps/admin/.env.example apps/admin/.env }

Run "script dependencies" { Push-Location scripts; npm install; $c = $LASTEXITCODE; Pop-Location; $global:LASTEXITCODE = $c }

Run "flutter platforms + packages" {
  Push-Location apps/mobile
  if (-not (Test-Path android)) {
    flutter create --platforms=android,ios . --org np.sahayogi --project-name sahayogi_mobile
  }
  if ($LASTEXITCODE -eq 0) { flutter pub get }
  $c = $LASTEXITCODE; Pop-Location; $global:LASTEXITCODE = $c
}

if (-not (Test-Path .env)) { Copy-Item .env.example .env }
Write-Host "Done. Next:  supabase start ; supabase db reset" -ForegroundColor Green