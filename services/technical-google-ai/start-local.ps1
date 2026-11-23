param([int]$Port = 8080)
$ErrorActionPreference = "Stop"
Set-Location -LiteralPath $PSScriptRoot
$configPath = Join-Path $PSScriptRoot ".env"
if (!(Test-Path -LiteralPath $configPath)) { throw "Create .env from .env.example first." }
foreach ($line in Get-Content -LiteralPath $configPath) {
    if ($line.Trim() -eq "" -or $line.TrimStart().StartsWith("#")) { continue }
    $parts = $line.Split("=", 2)
    if ($parts.Count -ne 2 -or $parts[0].Trim() -notmatch "^[A-Z][A-Z0-9_]*$") { throw "Invalid environment setting." }
    [Environment]::SetEnvironmentVariable($parts[0].Trim(), $parts[1].Trim(), "Process")
}
$python = Join-Path $PSScriptRoot ".venv/Scripts/python.exe"
if (!(Test-Path -LiteralPath $python)) { throw "Create .venv and install requirements-dev.txt first." }
if (!$env:GEMINI_API_KEY -or !$env:GOOGLE_ALLOWED_EMAILS -or $env:GEMINI_FREE_PROJECT_CONFIRMED -ne "true") {
    Write-Warning "AI requests require the private key, allowed email and project confirmation."
}
& $python -m uvicorn app:app --host 127.0.0.1 --port $Port --workers 1 --no-access-log
exit $LASTEXITCODE
