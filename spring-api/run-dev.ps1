# run-dev.ps1 — Load .env file and start the Spring Boot server
# Usage: .\run-dev.ps1
# This script loads all KEY=VALUE pairs from .env into the current session
# and then launches Spring Boot with those environment variables.

$envFile = Join-Path $PSScriptRoot ".env"

if (-not (Test-Path $envFile)) {
    Write-Error ".env file not found at $envFile. Copy .env.example to .env and fill in your values."
    exit 1
}

Write-Host "Loading environment from $envFile ..." -ForegroundColor Cyan

# Parse each non-comment, non-empty line as KEY=VALUE
Get-Content $envFile | ForEach-Object {
    $line = $_.Trim()
    if ($line -and -not $line.StartsWith("#")) {
        $idx = $line.IndexOf("=")
        if ($idx -gt 0) {
            $key   = $line.Substring(0, $idx).Trim()
            $value = $line.Substring($idx + 1).Trim()
            [System.Environment]::SetEnvironmentVariable($key, $value, "Process")
            Write-Host "  SET $key" -ForegroundColor DarkGray
        }
    }
}

Write-Host ""
Write-Host "Starting quotapp-api on http://localhost:8080 ..." -ForegroundColor Green
Write-Host ""

$env:JAVA_HOME = "C:\Program Files\Eclipse Adoptium\jdk-21.0.12.101-hotspot"
& "C:\Program Files\Maven\apache-maven-3.9.6\bin\mvn.cmd" spring-boot:run
