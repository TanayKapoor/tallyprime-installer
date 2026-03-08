#Requires -Version 5.1
<#
.SYNOPSIS
    TallyPrime → PostgreSQL Pipeline — Milestone 1: Environment Setup
.DESCRIPTION
    Prepares the client's system to receive the pipeline code.
    Checks prerequisites (Python 3.11+, PostgreSQL), collects all
    configuration, and writes a ready-to-use .env file.

    Does NOT install any pipeline code — code is delivered separately.
.EXAMPLE
    iwr -useb https://github.com/TanayKapoor/TallyPrime-to-Postgres/releases/download/v0.1.0-milestone-1/install.ps1 | iex
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── Output helpers ────────────────────────────────────────────────────────────
function Write-Header { param($t) Write-Host "`n$t" -ForegroundColor Cyan }
function Write-Step   { param($t) Write-Host "  » $t" -ForegroundColor White }
function Write-OK     { param($t) Write-Host "  ✓ $t" -ForegroundColor Green }
function Write-Warn   { param($t) Write-Host "  ! $t" -ForegroundColor Yellow }
function Write-Fail   { param($t) Write-Host "  ✗ $t" -ForegroundColor Red }
function Write-Dim    { param($t) Write-Host "    $t" -ForegroundColor DarkGray }
function Write-Rule   { Write-Host "  ─────────────────────────────────────" -ForegroundColor DarkGray }

function Write-Banner {
    Clear-Host
    Write-Host ""
    Write-Host "  ╔════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "  ║  TallyPrime → PostgreSQL Pipeline      ║" -ForegroundColor Green
    Write-Host "  ║  Milestone 1 · Environment Setup       ║" -ForegroundColor Green
    Write-Host "  ╚════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host ""
    Write-Host "  This script prepares your system to run the pipeline." -ForegroundColor White
    Write-Host "  It checks prerequisites and creates your configuration file." -ForegroundColor DarkGray
    Write-Host "  The pipeline code will be delivered in a separate step." -ForegroundColor DarkGray
    Write-Host ""
    Write-Rule
    Write-Host ""
}

# ── Prompt helpers ────────────────────────────────────────────────────────────
function Prompt-Input {
    param([string]$Label, [string]$Default = "", [switch]$Secret)
    $hint = if ($Default) { " [$Default]" } else { "" }
    Write-Host "  → $Label${hint}: " -ForegroundColor White -NoNewline
    if ($Secret) {
        $raw = Read-Host -AsSecureString
        $val = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                   [Runtime.InteropServices.Marshal]::SecureStringToBSTR($raw))
    } else {
        $val = Read-Host
    }
    if (-not $val -and $Default) { return $Default }
    return $val
}

function Prompt-YesNo {
    param([string]$Label, [string]$Default = "Y")
    $hint = if ($Default -eq "Y") { "[Y/n]" } else { "[y/N]" }
    Write-Host "  → $Label $hint: " -ForegroundColor White -NoNewline
    $ans = Read-Host
    if (-not $ans) { $ans = $Default }
    return $ans -match "^[Yy]"
}

# ══════════════════════════════════════════════════════════════════════════════
# STEP 1 — Prerequisites
# ══════════════════════════════════════════════════════════════════════════════
function Check-Prerequisites {
    Write-Header "[ 1 / 3 ]  Prerequisites"

    # ── Python ────────────────────────────────────────────────
    Write-Step "Checking Python…"
    if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
        Write-Fail "Python not found."
        Write-Dim  "Download Python 3.11+ from: https://www.python.org/downloads/"
        Write-Dim  "During install, check 'Add Python to PATH', then re-run this script."
        Write-Host ""
        Read-Host  "  Press Enter to exit"
        exit 1
    }

    $pyVer = & python -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>&1
    $parts = $pyVer -split "\."
    if ([int]$parts[0] -lt 3 -or ([int]$parts[0] -eq 3 -and [int]$parts[1] -lt 11)) {
        Write-Fail "Python 3.11+ required — found $pyVer."
        Write-Dim  "Download from: https://www.python.org/downloads/"
        Write-Host ""
        Read-Host  "  Press Enter to exit"
        exit 1
    }
    Write-OK "Python $pyVer"

    # ── PostgreSQL ────────────────────────────────────────────
    Write-Step "Checking PostgreSQL…"
    if (Get-Command psql -ErrorAction SilentlyContinue) {
        $pgVer = & psql --version 2>&1 | Select-Object -First 1
        Write-OK "PostgreSQL found — $pgVer"
    } else {
        Write-Warn "psql not found on PATH."
        Write-Dim  "If PostgreSQL is installed but not on PATH, that is fine —"
        Write-Dim  "you just need a running PostgreSQL server accessible over the network."
        Write-Dim  "If not installed: https://www.postgresql.org/download/windows/"
        Write-Host ""
        $cont = Prompt-YesNo "Continue anyway?" -Default "Y"
        if (-not $cont) { exit 0 }
    }

    Write-Host ""
    Write-OK "Prerequisites satisfied"
}

# ══════════════════════════════════════════════════════════════════════════════
# STEP 2 — Choose install directory
# ══════════════════════════════════════════════════════════════════════════════
function Choose-Directory {
    param([ref]$OutDir)

    Write-Header "[ 2 / 3 ]  Install Location"

    Write-Dim "This is where the pipeline code will be placed when delivered."
    Write-Host ""

    $default = Join-Path $env:USERPROFILE "TallyPrime-to-Postgres"
    $dir = Prompt-Input "Install directory" -Default $default

    # Create the directory now so .env can be written into it
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Write-OK "Directory created: $dir"
    } else {
        Write-OK "Directory exists — will use: $dir"
    }

    $OutDir.Value = $dir
}

# ══════════════════════════════════════════════════════════════════════════════
# STEP 3 — Configuration (.env)
# ══════════════════════════════════════════════════════════════════════════════
function Write-EnvFile {
    param([string]$Dir)

    Write-Header "[ 3 / 3 ]  Configuration"

    $envFile = Join-Path $Dir ".env"

    if (Test-Path $envFile) {
        Write-Warn ".env already exists at $envFile"
        $overwrite = Prompt-YesNo "Overwrite it?" -Default "N"
        if (-not $overwrite) {
            Write-OK "Keeping existing .env — skipping configuration."
            return
        }
    }

    Write-Dim "Press Enter to accept the default shown in [brackets]."
    Write-Host ""

    # ── TallyPrime ────────────────────────────────────────────
    Write-Host "  ─── TallyPrime Connection ───────────────────" -ForegroundColor DarkGray
    Write-Dim  "The machine where TallyPrime is running."
    $tallyHost = Prompt-Input "Tally host" -Default "localhost"
    $tallyPort = Prompt-Input "Tally port" -Default "9000"

    # ── PostgreSQL ────────────────────────────────────────────
    Write-Host ""
    Write-Host "  ─── PostgreSQL Connection ───────────────────" -ForegroundColor DarkGray
    $useUrl = Prompt-YesNo "Do you have a full connection URL (DATABASE_URL)?" -Default "N"

    $dbUrl = $dbHost = $dbPort = $dbUser = $dbPass = $dbName = ""

    if ($useUrl) {
        Write-Dim  "Format: postgresql+psycopg://user:password@host:5432/dbname"
        $dbUrl = Prompt-Input "DATABASE_URL"
    } else {
        $dbHost = Prompt-Input "Host"     -Default "localhost"
        $dbPort = Prompt-Input "Port"     -Default "5432"
        $dbUser = Prompt-Input "Username" -Default "postgres"
        $dbPass = Prompt-Input "Password" -Secret
        $dbName = Prompt-Input "Database" -Default "tallyprime"
    }

    # ── Companies ─────────────────────────────────────────────
    Write-Host ""
    Write-Host "  ─── Company Names ───────────────────────────" -ForegroundColor DarkGray
    Write-Dim  "Enter names exactly as they appear in TallyPrime."
    Write-Dim  "Separate multiple companies with commas."
    $companies = Prompt-Input "Company list" -Default "My Company"

    # ── Sync settings ─────────────────────────────────────────
    Write-Host ""
    Write-Host "  ─── Sync Settings ───────────────────────────" -ForegroundColor DarkGray
    $pollInterval = Prompt-Input "Polling interval in seconds" -Default "10"

    # ── SMTP (optional) ───────────────────────────────────────
    Write-Host ""
    Write-Host "  ─── Email Alerts (optional) ─────────────────" -ForegroundColor DarkGray
    Write-Dim  "The pipeline can email you when a sync fails."
    $wantSmtp = Prompt-YesNo "Configure email alerts now?" -Default "N"

    $smtpHost = $smtpPort = $smtpUser = $smtpPass = $smtpFrom = $smtpTo = ""
    if ($wantSmtp) {
        $smtpHost = Prompt-Input "SMTP host"
        $smtpPort = Prompt-Input "SMTP port"      -Default "587"
        $smtpUser = Prompt-Input "SMTP username"
        $smtpPass = Prompt-Input "SMTP password"  -Secret
        $smtpFrom = Prompt-Input "From address"
        $smtpTo   = Prompt-Input "Alert recipient (to)"
    }

    # ── Write .env ────────────────────────────────────────────
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm"
    $lines = [System.Collections.Generic.List[string]]::new()

    $lines.Add("# TallyPrime → PostgreSQL — Environment Configuration")
    $lines.Add("# Generated by Milestone 1 setup script on $ts")
    $lines.Add("# Keep this file private — do not commit it to version control.")
    $lines.Add("")
    $lines.Add("# ── TallyPrime ──────────────────────────────────")
    $lines.Add("TALLY_HOST=$tallyHost")
    $lines.Add("TALLY_PORT=$tallyPort")
    $lines.Add("")
    $lines.Add("# ── Companies (comma-separated, match TallyPrime exactly) ──")
    $lines.Add("COMPANY_LIST=$companies")
    $lines.Add("")
    $lines.Add("# ── PostgreSQL ──────────────────────────────────")

    if ($useUrl) {
        $lines.Add("DATABASE_URL=$dbUrl")
    } else {
        $lines.Add("DB_HOST=$dbHost")
        $lines.Add("DB_PORT=$dbPort")
        $lines.Add("DB_USER=$dbUser")
        $lines.Add("DB_PASSWORD=$dbPass")
        $lines.Add("DB_NAME=$dbName")
    }

    $lines.Add("")
    $lines.Add("# ── Sync ─────────────────────────────────────────")
    $lines.Add("POLLING_INTERVAL=$pollInterval")
    $lines.Add("DB_POOL_SIZE=5")
    $lines.Add("DB_MAX_OVERFLOW=10")
    $lines.Add("")

    if ($wantSmtp) {
        $lines.Add("# ── SMTP Alerts ──────────────────────────────────")
        $lines.Add("SMTP_HOST=$smtpHost")
        $lines.Add("SMTP_PORT=$smtpPort")
        $lines.Add("SMTP_USER=$smtpUser")
        $lines.Add("SMTP_PASSWORD=$smtpPass")
        $lines.Add("SMTP_FROM=$smtpFrom")
        $lines.Add("SMTP_TO=$smtpTo")
    } else {
        $lines.Add("# ── SMTP Alerts (disabled — fill in to enable) ───")
        $lines.Add("# SMTP_HOST=")
        $lines.Add("# SMTP_PORT=587")
        $lines.Add("# SMTP_USER=")
        $lines.Add("# SMTP_PASSWORD=")
        $lines.Add("# SMTP_FROM=")
        $lines.Add("# SMTP_TO=")
    }

    $lines | Out-File -FilePath $envFile -Encoding UTF8
    Write-Host ""
    Write-OK ".env saved to $envFile"
}

# ══════════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════════
function Write-Summary {
    param([string]$Dir)

    Write-Host ""
    Write-Host "  ╔════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "  ║  Environment setup complete  ✓             ║" -ForegroundColor Green
    Write-Host "  ╚════════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Install directory : $Dir" -ForegroundColor White
    Write-Host "  Config file       : $Dir\.env" -ForegroundColor White
    Write-Host ""
    Write-Host "  What was set up:" -ForegroundColor White
    Write-Host "    ✓ Python 3.11+ verified" -ForegroundColor Green
    Write-Host "    ✓ PostgreSQL connection details saved" -ForegroundColor Green
    Write-Host "    ✓ TallyPrime endpoint configured" -ForegroundColor Green
    Write-Host "    ✓ Company list configured" -ForegroundColor Green
    Write-Host ""
    Write-Host "  What comes next:" -ForegroundColor White
    Write-Host "    The pipeline code will be delivered to this directory." -ForegroundColor DarkGray
    Write-Host "    Once received, a single command will complete the installation." -ForegroundColor DarkGray
    Write-Host ""
    Write-Rule
    Write-Host ""
}

# ══════════════════════════════════════════════════════════════════════════════
# MAIN
# ══════════════════════════════════════════════════════════════════════════════
Write-Banner

$proceed = Prompt-YesNo "Ready to begin?" -Default "Y"
if (-not $proceed) {
    Write-Host ""
    Write-Host "  Aborted. Re-run when ready." -ForegroundColor Yellow
    exit 0
}

$installDir = ""

Check-Prerequisites
Choose-Directory ([ref]$installDir)
Write-EnvFile    $installDir
Write-Summary    $installDir
