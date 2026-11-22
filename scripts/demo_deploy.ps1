# PowerShell version of scripts/demo_deploy.sh.
# Pushes migrations, deploys every Edge Function and sets the function secrets on the HOSTED DEMO project.
# Does NOT seed (docs/DEMO-SETUP.md step 6).
#
# Run from anywhere:   powershell -ExecutionPolicy Bypass -File scripts\demo_deploy.ps1
# Needs (root .env): SUPABASE_URL, CONFIRM_PROJECT_REF, SUPABASE_DB_PASSWORD
# Needs: supabase CLI logged in (supabase login), supabase\functions\.env.demo filled in.
$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")

function Stop-Here($msg) { Write-Host $msg -ForegroundColor Red; exit 1 }
function Run($label) {
  if ($LASTEXITCODE -ne 0) { Stop-Here "FAILED: $label (exit code $LASTEXITCODE). Nothing after this step was run." }
}

if (-not (Test-Path .env)) { Stop-Here "No .env in the repo root." }
$envVars = @{}
foreach ($line in Get-Content .env) {
  if ($line -match '^\s*#' -or $line -notmatch '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$') { continue }
  $envVars[$Matches[1]] = $Matches[2].Trim().Trim('"').Trim("'")
}

$ref = $envVars["CONFIRM_PROJECT_REF"]
if (-not $ref) { Stop-Here "Set CONFIRM_PROJECT_REF=<demo project ref> in .env." }
if ($envVars["SUPABASE_URL"] -ne "https://$ref.supabase.co") {
  Stop-Here "SUPABASE_URL ($($envVars['SUPABASE_URL'])) does not match CONFIRM_PROJECT_REF ($ref). Stopping."
}
$dbPass = $envVars["SUPABASE_DB_PASSWORD"]
if (-not $dbPass) { Stop-Here "Set SUPABASE_DB_PASSWORD in .env (the database password chosen when the project was created)." }

$secretsFile = "supabase\functions\.env.demo"
if (-not (Test-Path $secretsFile)) { Stop-Here "Create $secretsFile from supabase\functions\.env.demo.example first." }
$secrets = Get-Content $secretsFile
foreach ($v in "PUSH_WEBHOOK_SECRET", "OTP_PEPPER", "SET_PASSWORD_URL", "ALLOWED_ORIGIN") {
  if (-not ($secrets | Where-Object { $_ -match "^$v=.+" })) { Stop-Here "$secretsFile has no value for $v." }
}
if ($secrets | Where-Object { $_ -match '^(OTP_DEV_LOG|PUSH_DRY_RUN)=' }) {
  Stop-Here "OTP_DEV_LOG / PUSH_DRY_RUN must not be set on a hosted project. Remove them from $secretsFile."
}
if (-not (Get-Command supabase -ErrorAction SilentlyContinue)) { Stop-Here "supabase CLI not found on PATH." }

Write-Host "== Project $ref =="
$again = Read-Host "Type the project ref again to continue"
if ($again -ne $ref) { Stop-Here "Mismatch, stopping." }

Write-Host "== 1/4 link =="
supabase link --project-ref $ref --password $dbPass; Run "supabase link"

Write-Host "== 2/4 migrations + district seed =="
supabase db push --include-seed --password $dbPass; Run "supabase db push"

Write-Host "== 3/4 secrets =="
supabase secrets set --env-file $secretsFile --project-ref $ref; Run "supabase secrets set"

Write-Host "== 4/4 functions =="
$funcs = Get-ChildItem supabase\functions -Directory | Where-Object { $_.Name -notlike "_*" } | Sort-Object Name
foreach ($f in $funcs) {
  Write-Host "-- deploy $($f.Name)"
  supabase functions deploy $f.Name --project-ref $ref; Run "deploy $($f.Name)"
}

Write-Host @"

Done. Still manual (docs/DEMO-SETUP.md):
  - scripts/demo_vault_secrets.sql in the SQL Editor (push_function_url + push_secret)
  - Auth -> URL Configuration (site URL + redirect URL) and Auth -> SMTP Settings
  - seed, privilege check, test matrix
"@