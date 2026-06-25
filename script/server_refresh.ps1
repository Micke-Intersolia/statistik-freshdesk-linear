#Requires -Version 5.1
<#
.SYNOPSIS
    Refreshar InternalStatistics direkt på servern

.DESCRIPTION
    Steg 1: Hämtar fillista från GitHub API (raw/freshdesk och raw/linear)
    Steg 2: Laddar nya snapshot-filer inkrementellt till bronze-tabellerna
    Steg 3: Kör silver-rebuild via SQL-skript hämtade från GitHub
    Steg 4: Loggar resultat och uppdaterar last_success.txt

    Kör på INTSQLSERVER01 med Windows-autentisering. 
    Enda externa beroende: GitHub-token (read-only).

.PARAMETER TokenPath
    Sökväg till textfil med GitHub-token (fine-grained, read-only, Contents).
    Standard: github_token.txt i samma mapp som scriptet.

.PARAMETER LogPath
    Sökväg till loggfil. Standard: logs\server_refresh.log bredvid scriptet.

.PARAMETER SqlServer
    SQL Server-instansnamn. Standard: localhost (kör på servern).

.PARAMETER Database
    Databasnamn. Standard: InternalStatistics

.PARAMETER Register
    Registrerar en schemalagd Windows-uppgift (kräver administratörsbehörighet)
    och avslutar utan att köra refreshen.

.EXAMPLE
    # Kör refresh direkt
    .\server_refresh.ps1

    # Registrera som schemalagd uppgift (kör en gång som admin)
    .\server_refresh.ps1 -Register
#>

param(
    [string]$TokenPath      = (Join-Path $PSScriptRoot "github_token.txt"),
    [string]$LogPath        = (Join-Path $PSScriptRoot "logs\server_refresh.log"),
    [string]$SqlServer      = "localhost",
    [string]$Database       = "InternalStatistics",
    [string]$TeamsWebhook   = "",   # Valfritt: Incoming Webhook URL för Teams-alert
    [switch]$Register,
    [switch]$WatchdogCheck  # Intern flagga — körs av watchdog-uppgiften kl. 16:00
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoOwner = "Micke-Intersolia"
$RepoName  = "statistik-freshdesk-linear"
$BatchSize = 500

# ── Logging ───────────────────────────────────────────────────
$LogDir = Split-Path -Parent $LogPath
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message"
    $line | Add-Content -Path $LogPath -Encoding UTF8
    if ($Level -eq "ERROR") { Write-Host $line -ForegroundColor Red }
    else { Write-Host $line }
}

# ── SOS-alert (körs av watchdog-uppgiften kl. 16:00) ─────────
if ($WatchdogCheck) {
    $successPath = Join-Path (Split-Path -Parent $LogPath) "last_success.txt"
    $alertNeeded = $true

    if (Test-Path $successPath) {
        $lastSuccess = (Get-Content $successPath -Raw).Trim()
        if ($lastSuccess -like "$(Get-Date -Format 'yyyy-MM-dd')*") {
            $alertNeeded = $false
        }
    }

    if ($alertNeeded) {
        $msg = "OPEX-Refresh: Ingen lyckad databas-refresh idag ($(Get-Date -Format 'yyyy-MM-dd')). Kontrollera $LogPath på $env:COMPUTERNAME."

        # Windows Event Log (kräver att källan registrerats — se -Register nedan)
        try {
            Write-EventLog -LogName Application -Source "OPEX-Refresh" `
                           -EventId 1001 -EntryType Error -Message $msg
        } catch {
            # Källan kanske inte är registrerad — skriv till System-loggen som fallback
            Write-Host "Event Log misslyckades: $_"
        }

        # Teams-webhook (valfritt — konfigurera URL i anropet eller lägg i webhook_url.txt)
        $webhookUrl = $TeamsWebhook
        if (-not $webhookUrl) {
            $wFile = Join-Path $PSScriptRoot "teams_webhook_url.txt"
            if (Test-Path $wFile) { $webhookUrl = (Get-Content $wFile -Raw).Trim() }
        }
        if ($webhookUrl) {
            $body = @{ text = $msg } | ConvertTo-Json
            try {
                Invoke-RestMethod -Uri $webhookUrl -Method Post `
                                  -Body $body -ContentType "application/json" | Out-Null
            } catch {
                Write-Host "Teams-webhook misslyckades: $_"
            }
        }

        Write-Host "SOS skickat: $msg"
        exit 1
    }

    Write-Host "Watchdog OK — lyckad refresh registrerad idag."
    exit 0
}

# ── Registrera schemalagda uppgifter ──────────────────────────
if ($Register) {
    $scriptPath = $MyInvocation.MyCommand.Path

    # Registrera Event Log-källa (krävs för Write-EventLog)
    if (-not [System.Diagnostics.EventLog]::SourceExists("OPEX-Refresh")) {
        New-EventLog -LogName Application -Source "OPEX-Refresh"
        Write-Host "Event Log-källa 'OPEX-Refresh' registrerad."
    }

    # Huvud-uppgift: kör varje timme 06:00–19:00
    $action   = New-ScheduledTaskAction `
                    -Execute "powershell.exe" `
                    -Argument "-NonInteractive -ExecutionPolicy Bypass -File `"$scriptPath`""
    $trigger  = New-ScheduledTaskTrigger -Daily -At "06:00"
    $settings = New-ScheduledTaskSettingsSet `
                    -ExecutionTimeLimit (New-TimeSpan -Hours 2) `
                    -RestartCount 3 `
                    -RestartInterval (New-TimeSpan -Minutes 60) `
                    -StartWhenAvailable
    Register-ScheduledTask `
        -TaskName "ServerRefresh_InternalStatistics" `
        -Action $action -Trigger $trigger -Settings $settings `
        -Description "Daglig refresh av InternalStatistics (bronze + silver)" `
        -RunLevel Highest -Force | Out-Null

    try {
        $task = Get-ScheduledTask -TaskName "ServerRefresh_InternalStatistics"
        $task.Triggers[0].RepetitionInterval = "PT1H"
        $task.Triggers[0].RepetitionDuration = "PT13H"
        $task | Set-ScheduledTask | Out-Null
        Write-Host "Huvud-uppgift registrerad med timrepetition: ServerRefresh_InternalStatistics"
    } catch {
        Write-Host "Huvud-uppgift registrerad (ange timrepetition manuellt i Task Scheduler)."
    }

    # Watchdog-uppgift: kontrollerar kl. 16:00 om refresh lyckats idag
    $wdAction = New-ScheduledTaskAction `
                    -Execute "powershell.exe" `
                    -Argument "-NonInteractive -ExecutionPolicy Bypass -File `"$scriptPath`" -WatchdogCheck"
    $wdTrigger  = New-ScheduledTaskTrigger -Daily -At "16:00"
    $wdSettings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
    Register-ScheduledTask `
        -TaskName "ServerRefresh_Watchdog" `
        -Action $wdAction -Trigger $wdTrigger -Settings $wdSettings `
        -Description "Kontrollerar kl. 16:00 om InternalStatistics refreshats idag — skickar SOS vid misslyckande" `
        -RunLevel Highest -Force | Out-Null
    Write-Host "Watchdog-uppgift registrerad: ServerRefresh_Watchdog (kör 16:00)"

    Write-Host ""
    Write-Host "Valfritt: lägg in Teams Incoming Webhook URL i '$PSScriptRoot\teams_webhook_url.txt' för SOS-meddelanden i Teams."
    exit 0
}

# ── GitHub-helpers ────────────────────────────────────────────
function Get-GithubToken {
    if (-not (Test-Path $TokenPath)) {
        throw "GitHub-token saknas: $TokenPath`nSkapa filen med tokenet på första raden."
    }
    $t = (Get-Content $TokenPath -Raw).Trim()
    if (-not $t) { throw "github_token.txt är tom." }
    return $t
}

function Get-GithubHeaders ([string]$Token) {
    return @{
        Authorization = "Bearer $Token"
        "User-Agent"  = "server_refresh.ps1/1.0"
        Accept        = "application/vnd.github.v3+json"
    }
}

function Get-RepoFiles ([string]$Token, [string]$Path) {
    $uri = "https://api.github.com/repos/$RepoOwner/$RepoName/contents/$Path"
    return Invoke-RestMethod -Uri $uri -Headers (Get-GithubHeaders $Token)
}

function Get-RepoJson ([string]$Token, [string]$DownloadUrl) {
    # Laddar ned en JSON-fil och returnerar parsad PSCustomObject/array
    $headers = @{ Authorization = "Bearer $Token"; "User-Agent" = "server_refresh.ps1/1.0" }
    return Invoke-RestMethod -Uri $DownloadUrl -Headers $headers
}

function Get-RepoSqlText ([string]$Token, [string]$RepoPath) {
    # Laddar ned ett SQL-skript via contents-API (base64-enkodad text)
    $uri  = "https://api.github.com/repos/$RepoOwner/$RepoName/contents/$RepoPath"
    $meta = Invoke-RestMethod -Uri $uri -Headers (Get-GithubHeaders $Token)
    $bytes = [System.Convert]::FromBase64String(($meta.content -replace '\s', ''))
    return [System.Text.Encoding]::UTF8.GetString($bytes)
}

# ── SQL-helpers ───────────────────────────────────────────────
function New-SqlConnection {
    $cs   = "Data Source=$SqlServer;Initial Catalog=$Database;Integrated Security=True;"
    $conn = New-Object System.Data.SqlClient.SqlConnection($cs)
    $conn.Open()
    return $conn
}

function Get-ImportedFiles ([System.Data.SqlClient.SqlConnection]$Conn) {
    $cmd    = $Conn.CreateCommand()
    $cmd.CommandText = "SELECT file_name FROM bronze.import_log"
    $reader = $cmd.ExecuteReader()
    $set    = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    while ($reader.Read()) { $set.Add($reader.GetString(0)) | Out-Null }
    $reader.Close()
    return $set
}

function Get-ExistingFreshdesk ([System.Data.SqlClient.SqlConnection]$Conn) {
    # Returnerar hashtable {ticket_id (int) → senaste updated_at-sträng}
    $cmd    = $Conn.CreateCommand()
    $cmd.CommandText = "SELECT id, MAX(updated_at) FROM bronze.freshdesk_tickets GROUP BY id"
    $cmd.CommandTimeout = 120
    $reader = $cmd.ExecuteReader()
    $dict   = @{}
    while ($reader.Read()) {
        $dict[[int]$reader.GetInt32(0)] = if ($reader.IsDBNull(1)) { "" } else { $reader.GetString(1) }
    }
    $reader.Close()
    return $dict
}

function Get-ExistingLinear ([System.Data.SqlClient.SqlConnection]$Conn) {
    # Returnerar hashtable {issue_id (string) → senaste updated_at-sträng}
    $cmd    = $Conn.CreateCommand()
    $cmd.CommandText = "SELECT id, MAX(updated_at) FROM bronze.linear_issues GROUP BY id"
    $cmd.CommandTimeout = 120
    $reader = $cmd.ExecuteReader()
    $dict   = @{}
    while ($reader.Read()) {
        $dict[$reader.GetString(0)] = if ($reader.IsDBNull(1)) { "" } else { $reader.GetString(1) }
    }
    $reader.Close()
    return $dict
}

function Invoke-SqlBatches ([System.Data.SqlClient.SqlConnection]$Conn, [string]$Sql) {
    # Delar på GO-rader och kör varje batch separat (silver-skript hanterar egna transaktioner)
    $batches = $Sql -split '(?im)^\s*GO\s*$'
    foreach ($batch in $batches) {
        $batch = $batch.Trim()
        if (-not $batch) { continue }
        $cmd = $Conn.CreateCommand()
        $cmd.CommandText    = $batch
        $cmd.CommandTimeout = 600
        $cmd.ExecuteNonQuery() | Out-Null
    }
}

# ── Freshdesk bronze-loader ───────────────────────────────────
function Import-FreshdeskFile {
    param(
        [System.Data.SqlClient.SqlConnection]$Conn,
        [string]$Token,
        [PSCustomObject]$FileInfo,
        [bool]$Incremental
    )

    $fileName = $FileInfo.name
    $mode     = if ($Incremental) { "inkrementell" } else { "full" }
    Write-Log "Freshdesk $mode : $fileName"

    $tickets  = Get-RepoJson -Token $Token -DownloadUrl $FileInfo.download_url
    Write-Log "  $($tickets.Count) tickets i filen"

    $existing = if ($Incremental) { Get-ExistingFreshdesk $Conn } else { @{} }

    # Bygg DataTable med exakt samma kolumnnamn som bronze-tabellen
    $dt = New-Object System.Data.DataTable
    foreach ($col in @("id","subject","status","priority","created_at","updated_at",
                        "due_by","group_id","product_id","_snapshot_file")) {
        $dt.Columns.Add($col) | Out-Null
    }

    $skipped = 0
    foreach ($t in $tickets) {
        $tid       = [int]$t.id
        $updatedAt = if ($t.updated_at) { [string]$t.updated_at } else { "" }

        if ($Incremental -and $existing.ContainsKey($tid) -and $updatedAt -le $existing[$tid]) {
            $skipped++
            continue
        }

        $row = $dt.NewRow()
        $row["id"]             = $tid
        $row["subject"]        = if ($t.subject)             { $t.subject }     else { [DBNull]::Value }
        $row["status"]         = if ($null -ne $t.status)    { $t.status }      else { [DBNull]::Value }
        $row["priority"]       = if ($null -ne $t.priority)  { $t.priority }    else { [DBNull]::Value }
        $row["created_at"]     = if ($t.created_at)          { $t.created_at }  else { [DBNull]::Value }
        $row["updated_at"]     = if ($updatedAt)             { $updatedAt }     else { [DBNull]::Value }
        $row["due_by"]         = if ($t.due_by)              { $t.due_by }      else { [DBNull]::Value }
        $row["group_id"]       = if ($null -ne $t.group_id)  { $t.group_id }    else { [DBNull]::Value }
        $row["product_id"]     = if ($null -ne $t.product_id){ $t.product_id }  else { [DBNull]::Value }
        $row["_snapshot_file"] = $fileName
        $dt.Rows.Add($row) | Out-Null
    }

    if ($skipped -gt 0) { Write-Log "  $skipped oförändrade poster hoppades över" }

    if ($dt.Rows.Count -eq 0) {
        Write-Log "  Inga nya poster."
        # Logga ändå i import_log så filen inte bearbetas igen
        $cmd = $Conn.CreateCommand()
        $cmd.CommandText = "INSERT INTO bronze.import_log (source, file_name, row_count) VALUES (@src,@fn,@rc)"
        $cmd.Parameters.AddWithValue("@src", "freshdesk") | Out-Null
        $cmd.Parameters.AddWithValue("@fn",  $fileName)   | Out-Null
        $cmd.Parameters.AddWithValue("@rc",  0)           | Out-Null
        $cmd.ExecuteNonQuery() | Out-Null
        return 0
    }

    # Transaktionsomslutning: bulk insert + import_log i ett
    $tx   = $Conn.BeginTransaction()
    $bulk = New-Object System.Data.SqlClient.SqlBulkCopy(
                $Conn, [System.Data.SqlClient.SqlBulkCopyOptions]::Default, $tx)
    try {
        $bulk.DestinationTableName = "bronze.freshdesk_tickets"
        $bulk.BatchSize            = $BatchSize
        $bulk.BulkCopyTimeout      = 300
        $bulk.WriteToServer($dt)

        $cmd = $Conn.CreateCommand()
        $cmd.Transaction = $tx
        $cmd.CommandText = "INSERT INTO bronze.import_log (source, file_name, row_count) VALUES (@src,@fn,@rc)"
        $cmd.Parameters.AddWithValue("@src", "freshdesk")    | Out-Null
        $cmd.Parameters.AddWithValue("@fn",  $fileName)      | Out-Null
        $cmd.Parameters.AddWithValue("@rc",  $dt.Rows.Count) | Out-Null
        $cmd.ExecuteNonQuery() | Out-Null

        $tx.Commit()
        Write-Log "  Infogade $($dt.Rows.Count) rader"
        return $dt.Rows.Count
    } catch {
        $tx.Rollback()
        throw
    } finally {
        $bulk.Close()
        $tx.Dispose()
    }
}

# ── Linear bronze-loader ──────────────────────────────────────
function Import-LinearFile {
    param(
        [System.Data.SqlClient.SqlConnection]$Conn,
        [string]$Token,
        [PSCustomObject]$FileInfo,
        [bool]$Incremental
    )

    $fileName = $FileInfo.name
    $mode     = if ($Incremental) { "inkrementell" } else { "full" }
    Write-Log "Linear $mode : $fileName"

    $issues   = Get-RepoJson -Token $Token -DownloadUrl $FileInfo.download_url
    Write-Log "  $($issues.Count) issues i filen"

    $existing = if ($Incremental) { Get-ExistingLinear $Conn } else { @{} }

    $cols = @(
        "id","number","identifier","title","description",
        "created_at","updated_at","archived_at","completed_at",
        "canceled_at","started_at","due_date",
        "priority","estimate","trashed",
        "state_id","state_name","state_type",
        "assignee_id","assignee_name","assignee_email",
        "project_id","project_name",
        "team_id","team_name",
        "parent_id","parent_identifier",
        "cycle_id","cycle_name","cycle_starts_at","cycle_ends_at",
        "labels","_snapshot_file"
    )
    $dt = New-Object System.Data.DataTable
    foreach ($col in $cols) { $dt.Columns.Add($col) | Out-Null }

    $skipped = 0
    foreach ($issue in $issues) {
        $iid       = [string]$issue.id
        $updatedAt = if ($issue.updatedAt) { [string]$issue.updatedAt } else { "" }

        if ($Incremental -and $existing.ContainsKey($iid) -and $updatedAt -le $existing[$iid]) {
            $skipped++
            continue
        }

        # Platta ut nästlade objekt (null-säkert)
        $state    = $issue.state
        $assignee = $issue.assignee
        $project  = $issue.project
        $team     = $issue.team
        $parent   = $issue.parent
        $cycle    = $issue.cycle

        # Labels: array av objekt → pipe-separerad sträng
        $labelNodes = if ($issue.labels -and $issue.labels.nodes) { $issue.labels.nodes } else { @() }
        $labels = if ($labelNodes.Count -gt 0) {
            ($labelNodes | ForEach-Object { $_.name } | Where-Object { $_ }) -join "|"
        } else { $null }

        $row = $dt.NewRow()
        $row["id"]                = $iid
        $row["number"]            = if ($null -ne $issue.number)           { $issue.number }           else { [DBNull]::Value }
        $row["identifier"]        = if ($issue.identifier)                 { $issue.identifier }        else { [DBNull]::Value }
        $row["title"]             = if ($issue.title)                      { $issue.title }             else { [DBNull]::Value }
        $row["description"]       = if ($issue.description)                { $issue.description }       else { [DBNull]::Value }
        $row["created_at"]        = if ($issue.createdAt)                  { $issue.createdAt }         else { [DBNull]::Value }
        $row["updated_at"]        = if ($updatedAt)                        { $updatedAt }               else { [DBNull]::Value }
        $row["archived_at"]       = if ($issue.archivedAt)                 { $issue.archivedAt }        else { [DBNull]::Value }
        $row["completed_at"]      = if ($issue.completedAt)                { $issue.completedAt }       else { [DBNull]::Value }
        $row["canceled_at"]       = if ($issue.canceledAt)                 { $issue.canceledAt }        else { [DBNull]::Value }
        $row["started_at"]        = if ($issue.startedAt)                  { $issue.startedAt }         else { [DBNull]::Value }
        $row["due_date"]          = if ($issue.dueDate)                    { $issue.dueDate }           else { [DBNull]::Value }
        $row["priority"]          = if ($null -ne $issue.priority)         { $issue.priority }          else { [DBNull]::Value }
        $row["estimate"]          = if ($null -ne $issue.estimate)         { $issue.estimate }          else { [DBNull]::Value }
        $row["trashed"]           = if ($null -ne $issue.trashed)          { [int][bool]$issue.trashed} else { [DBNull]::Value }
        $row["state_id"]          = if ($state    -and $state.id)          { $state.id }                else { [DBNull]::Value }
        $row["state_name"]        = if ($state    -and $state.name)        { $state.name }              else { [DBNull]::Value }
        $row["state_type"]        = if ($state    -and $state.type)        { $state.type }              else { [DBNull]::Value }
        $row["assignee_id"]       = if ($assignee -and $assignee.id)       { $assignee.id }             else { [DBNull]::Value }
        $row["assignee_name"]     = if ($assignee -and $assignee.name)     { $assignee.name }           else { [DBNull]::Value }
        $row["assignee_email"]    = if ($assignee -and $assignee.email)    { $assignee.email }          else { [DBNull]::Value }
        $row["project_id"]        = if ($project  -and $project.id)        { $project.id }              else { [DBNull]::Value }
        $row["project_name"]      = if ($project  -and $project.name)      { $project.name }            else { [DBNull]::Value }
        $row["team_id"]           = if ($team     -and $team.id)           { $team.id }                 else { [DBNull]::Value }
        $row["team_name"]         = if ($team     -and $team.name)         { $team.name }               else { [DBNull]::Value }
        $row["parent_id"]         = if ($parent   -and $parent.id)         { $parent.id }               else { [DBNull]::Value }
        $row["parent_identifier"] = if ($parent   -and $parent.identifier) { $parent.identifier }       else { [DBNull]::Value }
        $row["cycle_id"]          = if ($cycle    -and $cycle.id)          { $cycle.id }                else { [DBNull]::Value }
        $row["cycle_name"]        = if ($cycle    -and $cycle.name)        { $cycle.name }              else { [DBNull]::Value }
        $row["cycle_starts_at"]   = if ($cycle    -and $cycle.startsAt)    { $cycle.startsAt }          else { [DBNull]::Value }
        $row["cycle_ends_at"]     = if ($cycle    -and $cycle.endsAt)      { $cycle.endsAt }            else { [DBNull]::Value }
        $row["labels"]            = if ($labels)                           { $labels }                  else { [DBNull]::Value }
        $row["_snapshot_file"]    = $fileName
        $dt.Rows.Add($row) | Out-Null
    }

    if ($skipped -gt 0) { Write-Log "  $skipped oförändrade poster hoppades över" }

    if ($dt.Rows.Count -eq 0) {
        Write-Log "  Inga nya poster."
        $cmd = $Conn.CreateCommand()
        $cmd.CommandText = "INSERT INTO bronze.import_log (source, file_name, row_count) VALUES (@src,@fn,@rc)"
        $cmd.Parameters.AddWithValue("@src", "linear") | Out-Null
        $cmd.Parameters.AddWithValue("@fn",  $fileName) | Out-Null
        $cmd.Parameters.AddWithValue("@rc",  0)        | Out-Null
        $cmd.ExecuteNonQuery() | Out-Null
        return 0
    }

    $tx   = $Conn.BeginTransaction()
    $bulk = New-Object System.Data.SqlClient.SqlBulkCopy(
                $Conn, [System.Data.SqlClient.SqlBulkCopyOptions]::Default, $tx)
    try {
        $bulk.DestinationTableName = "bronze.linear_issues"
        $bulk.BatchSize            = $BatchSize
        $bulk.BulkCopyTimeout      = 300
        $bulk.WriteToServer($dt)

        $cmd = $Conn.CreateCommand()
        $cmd.Transaction = $tx
        $cmd.CommandText = "INSERT INTO bronze.import_log (source, file_name, row_count) VALUES (@src,@fn,@rc)"
        $cmd.Parameters.AddWithValue("@src", "linear")       | Out-Null
        $cmd.Parameters.AddWithValue("@fn",  $fileName)      | Out-Null
        $cmd.Parameters.AddWithValue("@rc",  $dt.Rows.Count) | Out-Null
        $cmd.ExecuteNonQuery() | Out-Null

        $tx.Commit()
        Write-Log "  Infogade $($dt.Rows.Count) rader"
        return $dt.Rows.Count
    } catch {
        $tx.Rollback()
        throw
    } finally {
        $bulk.Close()
        $tx.Dispose()
    }
}

# ── Silver rebuild ────────────────────────────────────────────
function Invoke-SilverScript {
    param([System.Data.SqlClient.SqlConnection]$Conn, [string]$Token, [string]$RepoPath)
    Write-Log "Silver: kör $RepoPath"

    # Bronze-kontroll (varna om tabellen är tom)
    $bronzeTable = if ($RepoPath -like "*freshdesk*") { "bronze.freshdesk_tickets" } else { "bronze.linear_issues" }
    $cmd = $Conn.CreateCommand()
    $cmd.CommandText = "SELECT COUNT(*) FROM $bronzeTable"
    $count = [int]$cmd.ExecuteScalar()
    if ($count -eq 0) {
        throw "Bronze-tabellen $bronzeTable är tom — silver-rebuild avbröts."
    }
    Write-Log "  Bronze-kontroll: $bronzeTable har $count rader"

    $sql = Get-RepoSqlText -Token $Token -RepoPath $RepoPath
    Invoke-SqlBatches -Conn $Conn -Sql $sql
    Write-Log "  $RepoPath klar."
}

# ── Huvudflöde ────────────────────────────────────────────────
try {
    Write-Log "=== server_refresh.ps1 startar ==="

    $token = Get-GithubToken

    $conn = New-SqlConnection
    Write-Log "Ansluten till $SqlServer / $Database"

    # Redan importerade filer
    $imported = Get-ImportedFiles -Conn $conn
    Write-Log "$($imported.Count) filer redan importerade i import_log"

    # Hämta fillista från GitHub
    Write-Log "Hämtar fillista från GitHub..."
    $fdFiles  = Get-RepoFiles -Token $token -Path "raw/freshdesk"
    $linFiles = Get-RepoFiles -Token $token -Path "raw/linear"

    # Varna om fillistan börjar närma sig GitHub API-gränsen (1000 per katalog)
    $fdSnapshotCount  = ($fdFiles  | Where-Object { $_.name -like "*_snapshot_*.json" }).Count
    $linSnapshotCount = ($linFiles | Where-Object { $_.name -like "*_snapshot_*.json" }).Count
    if ($fdSnapshotCount -gt 950 -or $linSnapshotCount -gt 950) {
        Write-Log "VARNING: raw/freshdesk/ har $fdSnapshotCount snapshot-filer, raw/linear/ har $linSnapshotCount. GitHub contents-API:et ger max 1000 per katalog — rensa gamla filer." -Level "WARN"
    }

    # Filtrera: bara JSON-filer, ej .meta.json, ej redan importerade
    $fdNew = $fdFiles | Where-Object {
        $_.type -eq "file" -and
        $_.name -like "freshdesk_*.json" -and
        -not $_.name.EndsWith(".meta.json") -and
        -not $imported.Contains($_.name)
    } | Sort-Object name

    $linNew = $linFiles | Where-Object {
        $_.type -eq "file" -and
        $_.name -like "linear_*.json" -and
        -not $_.name.EndsWith(".meta.json") -and
        -not $imported.Contains($_.name)
    } | Sort-Object name

    Write-Log "$($fdNew.Count) nya Freshdesk-filer, $($linNew.Count) nya Linear-filer"

    # Bronze — Freshdesk
    foreach ($f in $fdNew) {
        $incremental = $f.name -like "*_snapshot_*"
        Import-FreshdeskFile -Conn $conn -Token $token -FileInfo $f -Incremental $incremental
    }

    # Bronze — Linear
    foreach ($f in $linNew) {
        $incremental = $f.name -like "*_snapshot_*"
        Import-LinearFile -Conn $conn -Token $token -FileInfo $f -Incremental $incremental
    }

    # Silver rebuild (skript hämtas direkt från GitHub — alltid senaste versionen)
    Invoke-SilverScript -Conn $conn -Token $token -RepoPath "sql/05_silver_load_freshdesk.sql"
    Invoke-SilverScript -Conn $conn -Token $token -RepoPath "sql/07_silver_load_linear.sql"

    $conn.Close()

    # Uppdatera last_success.txt
    $successPath = Join-Path (Split-Path -Parent $LogPath) "last_success.txt"
    (Get-Date -Format "yyyy-MM-dd HH:mm:ss") | Set-Content -Path $successPath -Encoding UTF8

    Write-Log "=== Klar ==="

} catch {
    Write-Log "FEL: $_" -Level "ERROR"
    Write-Log $_.ScriptStackTrace -Level "ERROR"
    exit 1
}
