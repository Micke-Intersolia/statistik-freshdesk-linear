<#
.SYNOPSIS
    Daily BI pipeline: git pull -> bronze_loader.py -> silver_loader.py
    Retries every hour until the database is reachable (handles office vs. VPN).
    Sends a Windows alert if no successful run by end of working day.

.USAGE
    Register with Task Scheduler (run once, as Administrator):
        powershell -ExecutionPolicy Bypass -File "script\morning_refresh.ps1" -Register

    Run manually at any time:
        powershell -ExecutionPolicy Bypass -File "script\morning_refresh.ps1"

.RETRY LOGIC
    The task runs every hour on weekdays 07:00-20:00.
    - Already ran today       -> exits immediately (idempotent)
    - Database unreachable    -> logs a warning, exits, retries next hour
    - Past 16:00 on a weekday and missed both today and yesterday -> SOS alert
    - Laptop was off          -> StartWhenAvailable fires the task on next wake-up
#>
param([switch]$Register)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
$REPO_ROOT  = (Resolve-Path "$PSScriptRoot\..").Path
$LOG_DIR    = Join-Path $REPO_ROOT "logs"
$LOG_FILE   = Join-Path $LOG_DIR "refresh.log"
$STATE_FILE = Join-Path $LOG_DIR "last_success.txt"
$CRED_FILE  = Join-Path $REPO_ROOT "credentials\sql_connection.txt"
$TASK_NAME  = "InternalStatistics - Daily Refresh"
$SOS_HOUR   = 16
$DB_TIMEOUT = 8

# Use the repo virtual environment (has pyodbc); fall back to system Python
$PYTHON = if (Test-Path "$REPO_ROOT\.venv\Scripts\python.exe") {
    "$REPO_ROOT\.venv\Scripts\python.exe"
} else {
    "python"
}

# ---------------------------------------------------------------------------
# Register scheduled task  (run once as Administrator)
# ---------------------------------------------------------------------------
if ($Register) {
    $scriptPath = $MyInvocation.MyCommand.Path
    $psArgs = "-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`""

    $action   = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $psArgs
    $trigger  = New-ScheduledTaskTrigger `
                    -Weekly `
                    -DaysOfWeek Monday, Tuesday, Wednesday, Thursday, Friday `
                    -At "07:00"
    $settings = New-ScheduledTaskSettingsSet `
                    -StartWhenAvailable `
                    -RunOnlyIfNetworkAvailable `
                    -ExecutionTimeLimit (New-TimeSpan -Minutes 30)

    $repetitionOk = $false
    try {
        $trigger.Repetition.Interval = "PT1H"
        $trigger.Repetition.Duration = "PT13H"
        $repetitionOk = $true
    } catch { }

    Register-ScheduledTask `
        -TaskName $TASK_NAME `
        -Action   $action `
        -Trigger  $trigger `
        -Settings $settings `
        -RunLevel Highest `
        -Force | Out-Null

    Write-Host ""
    Write-Host "Task '$TASK_NAME' registered."

    if ($repetitionOk) {
        Write-Host "  Schedule: weekdays 07:00-20:00, every hour."
    } else {
        Write-Host "  Schedule: weekdays at 07:00 only."
        Write-Host "  Hourly repetition must be added manually:"
        Write-Host "    1. Open Task Scheduler"
        Write-Host "    2. Find '$TASK_NAME' in Task Scheduler Library"
        Write-Host "    3. Right-click -> Properties -> Triggers tab"
        Write-Host "    4. Select the trigger -> Edit"
        Write-Host "    5. Tick 'Repeat task every: 1 hour' for a duration of '13 hours'"
        Write-Host "    6. Click OK"
    }

    Write-Host "  StartWhenAvailable: ON (runs as soon as laptop wakes if a run was missed)"
    Write-Host ""
    Write-Host "To verify: open Task Scheduler -> Task Scheduler Library."
    Write-Host "To test now: right-click the task -> Run"
    exit 0
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
if (-not (Test-Path $LOG_DIR)) {
    New-Item -ItemType Directory -Path $LOG_DIR -Force | Out-Null
}

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  [$Level]  $Message"
    Add-Content -Path $LOG_FILE -Value $line -Encoding UTF8
    Write-Host $line
}

function Get-LastSuccessDate {
    if (Test-Path $STATE_FILE) {
        try {
            return [datetime]::ParseExact(
                (Get-Content $STATE_FILE -Raw -Encoding UTF8).Trim(),
                "yyyy-MM-dd", $null)
        } catch { }
    }
    return $null
}

function Get-LastWorkingDay {
    $d = (Get-Date).Date.AddDays(-1)
    while ($d.DayOfWeek -in @([DayOfWeek]::Saturday, [DayOfWeek]::Sunday)) {
        $d = $d.AddDays(-1)
    }
    return $d
}

function Test-DbConnection {
    $connStr = if ($env:SQL_CONNECTION_STRING) {
        $env:SQL_CONNECTION_STRING
    } elseif (Test-Path $CRED_FILE) {
        (Get-Content $CRED_FILE -Raw -Encoding UTF8).Trim()
    } else {
        Write-Log "No connection string found." "ERROR"
        return $false
    }
    try {
        Add-Type -AssemblyName System.Data
        $conn = New-Object System.Data.Odbc.OdbcConnection($connStr)
        $conn.ConnectionTimeout = $DB_TIMEOUT
        $conn.Open()
        $conn.Close()
        return $true
    } catch {
        return $false
    }
}

function Send-SosAlert {
    param([string]$Body)
    Write-Log $Body "SOS"

    # Attempt 1: Windows Forms balloon notification
    try {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        $notify = New-Object System.Windows.Forms.NotifyIcon
        $notify.Icon            = [System.Drawing.SystemIcons]::Warning
        $notify.Visible         = $true
        $notify.BalloonTipTitle = "BI Pipeline - SOS"
        $notify.BalloonTipText  = $Body
        $notify.BalloonTipIcon  = [System.Windows.Forms.ToolTipIcon]::Warning
        $notify.ShowBalloonTip(30000)
        Start-Sleep -Seconds 3
        $notify.Dispose()
    } catch { }

    # Attempt 2: flag file on the Desktop (always works, hard to miss)
    $flagPath = "$env:USERPROFILE\Desktop\PIPELINE SOS $(Get-Date -Format 'yyyy-MM-dd').txt"
    Set-Content -Path $flagPath -Value $Body -Encoding UTF8
    Write-Log "SOS flag written to Desktop: $flagPath" "SOS"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
$now         = Get-Date
$today       = $now.Date
$lastSuccess = Get-LastSuccessDate

if ($lastSuccess -and $lastSuccess.Date -eq $today) {
    Write-Log "Already refreshed today - nothing to do."
    exit 0
}

Write-Log "Checking database connection..."
if (-not (Test-DbConnection)) {
    Write-Log "Database unreachable - VPN not connected? Retrying next scheduled run." "WARN"

    $isWeekday       = $now.DayOfWeek -notin @([DayOfWeek]::Saturday, [DayOfWeek]::Sunday)
    $pastSosHour     = $now.Hour -ge $SOS_HOUR
    $lastOK          = if ($lastSuccess) { $lastSuccess.Date } else { [datetime]::MinValue }
    $missedYesterday = $lastOK -lt (Get-LastWorkingDay).Date

    if ($isWeekday -and $pastSosHour -and $missedYesterday) {
        $since = if ($lastSuccess) { $lastSuccess.ToString("yyyy-MM-dd") } else { "never" }
        Send-SosAlert "No successful pipeline refresh since $since. Check VPN / SQL Server. Log: $LOG_FILE"
    }
    exit 1
}

Write-Log "Connected. Starting pipeline..."
Set-Location $REPO_ROOT

Write-Log "Step 1/3  git pull"
$out = git pull 2>&1
Write-Log ($out -join " | ")
if ($LASTEXITCODE -ne 0) {
    Write-Log "git pull failed - aborting." "ERROR"
    exit 1
}

Write-Log "Step 2/3  bronze_loader.py"
$ErrorActionPreference = "Continue"
$out = & $PYTHON "script\bronze_loader.py" 2>&1
$ErrorActionPreference = "Stop"
Write-Log ($out -join " | ")
if ($LASTEXITCODE -ne 0) {
    Write-Log "bronze_loader.py failed - aborting." "ERROR"
    exit 1
}

Write-Log "Step 3/3  silver_loader.py"
$ErrorActionPreference = "Continue"
$out = & $PYTHON "script\silver_loader.py" 2>&1
$ErrorActionPreference = "Stop"
Write-Log ($out -join " | ")
if ($LASTEXITCODE -ne 0) {
    Write-Log "silver_loader.py failed - aborting." "ERROR"
    exit 1
}

Set-Content -Path $STATE_FILE -Value (Get-Date -Format "yyyy-MM-dd") -Encoding UTF8
Write-Log "Pipeline complete. Data is up to date."
