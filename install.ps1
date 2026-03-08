#Requires -Version 5.1
<#
.SYNOPSIS
    TallyPrime -> PostgreSQL Pipeline -- Milestone 1: Environment Setup
.DESCRIPTION
    Prepares the client's system to receive the pipeline code.
    Checks prerequisites (Python 3.11+, PostgreSQL), collects all
    configuration, and writes a ready-to-use .env file.

    Does NOT install any pipeline code -- code is delivered separately.
.EXAMPLE
    iwr -useb https://github.com/TanayKapoor/tallyprime-installer/releases/download/v0.1.0-milestone-1/install.ps1 | iex
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Force UTF-8 output so box-drawing and special characters render correctly
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding            = [System.Text.Encoding]::UTF8

# ── Output helpers ────────────────────────────────────────────────────────────
function Write-Header { param($t) Write-Host "" ; Write-Host $t -ForegroundColor Cyan }
function Write-Step   { param($t) Write-Host "  > $t" -ForegroundColor White }
function Write-OK     { param($t) Write-Host "  [OK] $t" -ForegroundColor Green }
function Write-Warn   { param($t) Write-Host "  [!]  $t" -ForegroundColor Yellow }
function Write-Fail   { param($t) Write-Host "  [X]  $t" -ForegroundColor Red }
function Write-Dim    { param($t) Write-Host "       $t" -ForegroundColor DarkGray }
function Write-Rule   { Write-Host "  ------------------------------------------------" -ForegroundColor DarkGray }
function Write-Blank  { Write-Host "" }

function Write-Banner {
    Clear-Host
    Write-Host ""
    Write-Host "  +------------------------------------------+" -ForegroundColor Green
    Write-Host "  |  TallyPrime -> PostgreSQL Pipeline        |" -ForegroundColor Green
    Write-Host "  |  Milestone 1  |  Environment Setup        |" -ForegroundColor Green
    Write-Host "  +------------------------------------------+" -ForegroundColor Green
    Write-Blank
    Write-Host "  This script prepares your system to run the pipeline." -ForegroundColor White
    Write-Host "  It checks prerequisites and creates your configuration file." -ForegroundColor DarkGray
    Write-Host "  The pipeline code will be delivered in a separate step." -ForegroundColor DarkGray
    Write-Blank
    Write-Rule
    Write-Blank
}

# ── Prompt helpers ────────────────────────────────────────────────────────────
function Prompt-Input {
    param([string]$Label, [string]$Default = "", [switch]$Secret)
    $hint = if ($Default) { " [$Default]" } else { "" }
    Write-Host "  $Label${hint}: " -ForegroundColor White -NoNewline
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
    Write-Host "  $Label ${hint}: " -ForegroundColor White -NoNewline
    $ans = Read-Host
    if (-not $ans) { $ans = $Default }
    return $ans -match "^[Yy]"
}

# ── Section heading helper ────────────────────────────────────────────────────
function Write-Section {
    param([string]$Step, [string]$Title)
    Write-Blank
    Write-Host "  ---- $Step : $Title ----" -ForegroundColor Cyan
    Write-Blank
}

# ══════════════════════════════════════════════════════════════════════════════
# STEP 1 -- Prerequisites
# ══════════════════════════════════════════════════════════════════════════════
function Check-Prerequisites {
    Write-Section "Step 1 of 3" "Prerequisites"

    # ── Python ────────────────────────────────────────────────
    Write-Step "Checking Python..."

    function Install-Python {
        # Try winget first (built into Windows 10 1709+ and Windows 11)
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            Write-Step "Installing Python 3.11 via winget..."
            winget install --id Python.Python.3.11 --silent --accept-package-agreements --accept-source-agreements
            if ($LASTEXITCODE -eq 0) {
                # Refresh PATH so python is available in this session
                $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                            [System.Environment]::GetEnvironmentVariable("Path","User")
                Write-OK "Python 3.11 installed via winget"
                return $true
            }
        }

        # Fallback: download the official installer silently
        Write-Step "winget not available -- downloading Python 3.11 installer..."
        $installer = Join-Path $env:TEMP "python-3.11.9-amd64.exe"
        try {
            Invoke-WebRequest -Uri "https://www.python.org/ftp/python/3.11.9/python-3.11.9-amd64.exe" `
                              -OutFile $installer -UseBasicParsing
            Write-Step "Running Python installer (this may take a minute)..."
            # /quiet = silent, PrependPath=1 = add to PATH automatically
            Start-Process -FilePath $installer -ArgumentList "/quiet PrependPath=1 Include_pip=1" -Wait
            Remove-Item $installer -Force
            # Refresh PATH
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                        [System.Environment]::GetEnvironmentVariable("Path","User")
            Write-OK "Python 3.11 installed"
            return $true
        } catch {
            Write-Fail "Automatic Python installation failed: $_"
            return $false
        }
    }

    $pythonFound = Get-Command python -ErrorAction SilentlyContinue
    if (-not $pythonFound) {
        Write-Warn "Python not found."
        $install = Prompt-YesNo "Install Python 3.11 automatically?" -Default "Y"
        if ($install) {
            $ok = Install-Python
            if (-not $ok) {
                Write-Dim  "Please install manually: https://www.python.org/downloads/"
                Write-Dim  "During install, tick 'Add Python to PATH', then re-run this script."
                Write-Blank
                Read-Host  "  Press Enter to exit"
                exit 1
            }
        } else {
            Write-Dim  "Please install Python 3.11+ from: https://www.python.org/downloads/"
            Write-Dim  "Tick 'Add Python to PATH' during install, then re-run this script."
            Write-Blank
            Read-Host  "  Press Enter to exit"
            exit 1
        }
    }

    $pyVer = & python -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>&1
    $parts = $pyVer -split "\."
    if ([int]$parts[0] -lt 3 -or ([int]$parts[0] -eq 3 -and [int]$parts[1] -lt 11)) {
        Write-Warn "Python $pyVer is installed but 3.11+ is required."
        $install = Prompt-YesNo "Install Python 3.11 alongside it?" -Default "Y"
        if ($install) {
            $ok = Install-Python
            if (-not $ok) {
                Write-Fail "Could not install Python 3.11 automatically."
                Write-Dim  "Please install manually: https://www.python.org/downloads/"
                Write-Blank
                Read-Host  "  Press Enter to exit"
                exit 1
            }
            # Re-check version after install
            $pyVer = & python -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>&1
        } else {
            Write-Fail "Python 3.11+ is required. Exiting."
            exit 1
        }
    }
    Write-OK "Python $pyVer"

    # ── PostgreSQL ────────────────────────────────────────────
    Write-Step "Checking PostgreSQL..."
    if (Get-Command psql -ErrorAction SilentlyContinue) {
        $pgVer = & psql --version 2>&1 | Select-Object -First 1
        Write-OK "PostgreSQL found -- $pgVer"
    } else {
        Write-Warn "psql not found on PATH."
        Write-Dim  "If PostgreSQL is installed but not on PATH, that is fine --"
        Write-Dim  "you just need a running PostgreSQL server accessible over the network."
        Write-Dim  "If not installed: https://www.postgresql.org/download/windows/"
        Write-Blank
        $cont = Prompt-YesNo "Continue anyway?" -Default "Y"
        if (-not $cont) { exit 0 }
    }

    Write-Blank
    Write-OK "Prerequisites satisfied"
}

# ══════════════════════════════════════════════════════════════════════════════
# STEP 2 -- Choose install directory
# ══════════════════════════════════════════════════════════════════════════════
function Choose-Directory {
    param([ref]$OutDir)

    Write-Section "Step 2 of 3" "Install Location"

    Write-Dim "This is where the pipeline code will be placed when delivered."
    Write-Blank

    $default = Join-Path $env:USERPROFILE "TallyPrime-to-Postgres"
    $dir = Prompt-Input "Install directory" -Default $default

    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Write-OK "Directory created: $dir"
    } else {
        Write-OK "Directory exists, will use: $dir"
    }

    $OutDir.Value = $dir
}

# ══════════════════════════════════════════════════════════════════════════════
# STEP 3 -- Configuration (.env)
# ══════════════════════════════════════════════════════════════════════════════
function Write-EnvFile {
    param([string]$Dir)

    Write-Section "Step 3 of 3" "Configuration"

    $envFile = Join-Path $Dir ".env"

    if (Test-Path $envFile) {
        Write-Warn ".env already exists at $envFile"
        $overwrite = Prompt-YesNo "Overwrite it?" -Default "N"
        if (-not $overwrite) {
            Write-OK "Keeping existing .env -- skipping configuration."
            return
        }
    }

    Write-Dim "Press Enter to accept the default shown in [brackets]."
    Write-Blank

    # ── TallyPrime ────────────────────────────────────────────
    Write-Host "  -- TallyPrime Connection --" -ForegroundColor DarkGray
    Write-Dim  "The machine where TallyPrime is running."
    $tallyHost = Prompt-Input "Tally host" -Default "localhost"
    $tallyPort = Prompt-Input "Tally port" -Default "9000"

    # ── PostgreSQL ────────────────────────────────────────────
    Write-Blank
    Write-Host "  -- PostgreSQL Connection --" -ForegroundColor DarkGray
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
    Write-Blank
    Write-Host "  -- Company Names --" -ForegroundColor DarkGray
    Write-Dim  "Enter names exactly as they appear in TallyPrime."
    Write-Dim  "Separate multiple companies with commas."
    $companies = Prompt-Input "Company list" -Default "My Company"

    # ── Sync settings ─────────────────────────────────────────
    Write-Blank
    Write-Host "  -- Sync Settings --" -ForegroundColor DarkGray
    $pollInterval = Prompt-Input "Polling interval in seconds" -Default "10"

    # ── SMTP (optional) ───────────────────────────────────────
    Write-Blank
    Write-Host "  -- Email Alerts (optional) --" -ForegroundColor DarkGray
    Write-Dim  "The pipeline can email you when a sync fails."
    $wantSmtp = Prompt-YesNo "Configure email alerts now?" -Default "N"

    $smtpHost = $smtpPort = $smtpUser = $smtpPass = $smtpFrom = $smtpTo = ""
    if ($wantSmtp) {
        $smtpHost = Prompt-Input "SMTP host"
        $smtpPort = Prompt-Input "SMTP port"          -Default "587"
        $smtpUser = Prompt-Input "SMTP username"
        $smtpPass = Prompt-Input "SMTP password"      -Secret
        $smtpFrom = Prompt-Input "From address"
        $smtpTo   = Prompt-Input "Alert recipient"
    }

    # ── Write .env ────────────────────────────────────────────
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm"
    $lines = [System.Collections.Generic.List[string]]::new()

    $lines.Add("# TallyPrime -> PostgreSQL -- Environment Configuration")
    $lines.Add("# Generated by Milestone 1 setup script on $ts")
    $lines.Add("# Keep this file private -- do not commit it to version control.")
    $lines.Add("")
    $lines.Add("# -- TallyPrime --")
    $lines.Add("TALLY_HOST=$tallyHost")
    $lines.Add("TALLY_PORT=$tallyPort")
    $lines.Add("")
    $lines.Add("# -- Companies (comma-separated, match TallyPrime exactly) --")
    $lines.Add("COMPANY_LIST=$companies")
    $lines.Add("")
    $lines.Add("# -- PostgreSQL --")

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
    $lines.Add("# -- Sync --")
    $lines.Add("POLLING_INTERVAL=$pollInterval")
    $lines.Add("DB_POOL_SIZE=5")
    $lines.Add("DB_MAX_OVERFLOW=10")
    $lines.Add("")

    if ($wantSmtp) {
        $lines.Add("# -- SMTP Alerts --")
        $lines.Add("SMTP_HOST=$smtpHost")
        $lines.Add("SMTP_PORT=$smtpPort")
        $lines.Add("SMTP_USER=$smtpUser")
        $lines.Add("SMTP_PASSWORD=$smtpPass")
        $lines.Add("SMTP_FROM=$smtpFrom")
        $lines.Add("SMTP_TO=$smtpTo")
    } else {
        $lines.Add("# -- SMTP Alerts (disabled -- fill in to enable) --")
        $lines.Add("# SMTP_HOST=")
        $lines.Add("# SMTP_PORT=587")
        $lines.Add("# SMTP_USER=")
        $lines.Add("# SMTP_PASSWORD=")
        $lines.Add("# SMTP_FROM=")
        $lines.Add("# SMTP_TO=")
    }

    $lines | Out-File -FilePath $envFile -Encoding UTF8
    Write-Blank
    Write-OK ".env saved to $envFile"
}

# ══════════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════════
function Write-Summary {
    param([string]$Dir)

    Write-Blank
    Write-Rule
    Write-Blank
    Write-Host "  Environment setup complete!" -ForegroundColor Green
    Write-Blank
    Write-Host "  Install directory : $Dir" -ForegroundColor White
    Write-Host "  Config file       : $Dir\.env" -ForegroundColor White
    Write-Blank
    Write-Host "  What was set up:" -ForegroundColor White
    Write-OK "Python 3.11+ verified"
    Write-OK "PostgreSQL connection details saved"
    Write-OK "TallyPrime endpoint configured"
    Write-OK "Company list configured"
    Write-Blank
    Write-Host "  What comes next:" -ForegroundColor White
    Write-Dim  "The pipeline code will be delivered to this directory."
    Write-Dim  "Once received, a single command will complete the installation."
    Write-Blank
    Write-Rule
    Write-Blank
}

# ══════════════════════════════════════════════════════════════════════════════
# MAIN
# ══════════════════════════════════════════════════════════════════════════════
Write-Banner

$proceed = Prompt-YesNo "Ready to begin?" -Default "Y"
if (-not $proceed) {
    Write-Blank
    Write-Host "  Aborted. Re-run when ready." -ForegroundColor Yellow
    exit 0
}

$installDir = ""

Check-Prerequisites
Choose-Directory ([ref]$installDir)
Write-EnvFile    $installDir
Write-Summary    $installDir
