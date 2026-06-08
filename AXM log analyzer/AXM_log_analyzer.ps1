<#
.SYNOPSIS
Standalone AXM log analyzer for SimonsVoss AXM support engineers.

.DESCRIPTION
Parses AXM log files, extracts environment details, detects sessions, summarizes issues, highlights recurring patterns,
and generates technician-friendly console summaries and structured JSON output.

.EXAMPLE
powershell -File .\AXM_log_analyzer.ps1 -Path .\AXMLog-PlatformPlus-20260602_003.log

.EXAMPLE
powershell -File .\AXM_log_analyzer.ps1 -Path .\AXMLog-PlatformPlus-20260602_003.log -Json -Output .\AXMReport.json
#>

param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Path,

    [switch]$Json,

    [string]$Output
)

function Show-Usage {
    Write-Host "AXM Log Analyzer"
    Write-Host "Usage: .\AXM_log_analyzer.ps1 -Path <logfile> [-Json] [-Output <report.json>]"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -Path    Path to an AXM log file"
    Write-Host "  -Json    Emit structured JSON report"
    Write-Host "  -Output  Path to JSON output file when using -Json"
}

function Parse-AXMLogLine {
    param(
        [string]$Line
    )

    if (-not $Line) {
        return $null
    }

    $regex = '^(?<Timestamp>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3})(?: (?<Offset>[+-]\d{2}:\d{2}))?\s+(?<ThreadId>\d+)\|\s*(?<Level>[A-Z]+)\|\s*(?<Message>.+?)(?:\s*<s:(?<Component>.+)>)?$'
    $m = [regex]::Match($Line, $regex)
    if (-not $m.Success) {
        return $null
    }

    $timestampText = $m.Groups['Timestamp'].Value
    $offsetText = $m.Groups['Offset'].Value
    $timestamp = [datetime]::ParseExact($timestampText, 'yyyy-MM-dd HH:mm:ss.fff', [System.Globalization.CultureInfo]::InvariantCulture)
    if ($offsetText) {
        $timestamp = [datetimeoffset]::ParseExact("$timestampText $offsetText", 'yyyy-MM-dd HH:mm:ss.fff zzz', [System.Globalization.CultureInfo]::InvariantCulture).UtcDateTime
    }

    [PSCustomObject]@{
        Timestamp = $timestamp
        Offset = $offsetText
        ThreadId = $m.Groups['ThreadId'].Value
        Level = $m.Groups['Level'].Value
        Message = $m.Groups['Message'].Value.Trim()
        Component = if ($m.Groups['Component'].Success) { $m.Groups['Component'].Value.Trim() } else { $null }
        RawLine = $Line
    }
}

function Get-AXMLogEntries {
    param(
        [string]$LogPath
    )

    if (-not (Test-Path -Path $LogPath)) {
        throw "Log file not found: $LogPath"
    }

    Get-Content -Path $LogPath -ErrorAction Stop | ForEach-Object {
        $entry = Parse-AXMLogLine -Line $_
        if ($entry) {
            $entry
        }
    }
}

function Get-UniqueValues {
    param(
        [string[]]$Items,
        [int]$Max = 20
    )

    if (-not $Items) { return @() }
    $Items | Where-Object { $_ } | Select-Object -Unique | Select-Object -First $Max
}

function Analyze-Environment {
    param(
        [object[]]$Entries,
        [string]$LogPath
    )

    $version = $null
    $databaseType = 'Unknown'
    $databaseVersion = 'Unknown'
    $gatewayAddresses = [System.Collections.Generic.HashSet[string]]::new()
    $components = [System.Collections.Generic.HashSet[string]]::new()
    $cardEvents = 0
    $serviceNames = [System.Collections.Generic.HashSet[string]]::new()

    foreach ($entry in $Entries) {
        if ($entry.Component) {
            $components.Add($entry.Component) | Out-Null
        }

        $text = $entry.Message
        if ($text -match 'AXM Version\s*[:=]\s*(?<value>[\d\.]+)') {
            $version = $matches['value']
        }

        if ($text -match 'Database\s*[:=]\s*(?<value>.+)') {
            $databaseType = $matches['value'].Trim()
        }

        if ($text -match '(?<value>SQL Server|MSSQL|PostgreSQL|Oracle|MySQL)') {
            $databaseType = $matches['value']
        }

        if ($text -match 'Database version\s*[:=]\s*(?<value>.+)') {
            $databaseVersion = $matches['value'].Trim()
        }

        if ($text -match 'DestinationAddress\s*:\s*(?<value>[^,\s]+)') {
            $gatewayAddresses.Add($matches['value']) | Out-Null
        }

        if ($text -match 'Gateway\s*[:=]\s*(?<value>[^,\s]+)') {
            $gatewayAddresses.Add($matches['value']) | Out-Null
        }

        if ($text -match '(Card|CardInfo|Card Read|Card Write|CardData|Transponder)') {
            $cardEvents++
        }

        if ($entry.Component -and $entry.Component -match '\.') {
            $serviceNames.Add(($entry.Component -split '\.')[0]) | Out-Null
        }
    }

    if (-not $version) {
        $version = 'Unknown'
    }

    [PSCustomObject]@{
        LogFile = $LogPath
        AXMVersion = $version
        DatabaseType = $databaseType
        DatabaseVersion = $databaseVersion
        ConnectedGateways = $gatewayAddresses.Count
        GatewayAddresses = $gatewayAddresses.ToArray()
        DetectedServices = $serviceNames.ToArray()
        DetectedComponents = $components.ToArray()
        CardEventCount = $cardEvents
    }
}

function Analyze-Sessions {
    param(
        [object[]]$Entries
    )

    $progSessionGroups = @{}
    $loginSessions = @()
    $serviceRestarts = @()
    $communicationEvents = @()

    foreach ($entry in $Entries) {
        $sessionId = $null
        if ($entry.Message -match 'ProgSession\s*:\s*"(?<id>[0-9a-fA-F-]{36})"') {
            $sessionId = $matches['id']
        }

        if ($sessionId) {
            if (-not $progSessionGroups.ContainsKey($sessionId)) {
                $progSessionGroups[$sessionId] = @()
            }
            $progSessionGroups[$sessionId] += $entry
        }

        if ($entry.Message -match '\b(Login|Authentication|Sign ?in|Sign ?out|Log ?on|Log ?off)\b') {
            $loginSessions += $entry
        }

        if ($entry.Message -match '\b(starting|started|stopped|restart|restarted|Initializing|Shutdown|Shutdown completed)\b') {
            $serviceRestarts += $entry
        }

        if ($entry.Message -match '\b(SendProgrammingMessage|MessageEvent|Forwarding programming message|SignalR|EventBus|Processing programming message)\b') {
            $communicationEvents += $entry
        }
    }

    $programmingSessions = foreach ($sessionId in $progSessionGroups.Keys | Sort-Object) {
        $group = $progSessionGroups[$sessionId]
        $start = ($group | Sort-Object Timestamp | Select-Object -First 1).Timestamp
        $end = ($group | Sort-Object Timestamp | Select-Object -Last 1).Timestamp
        $duration = $end - $start
        $errorCount = ($group | Where-Object { $_.Level -in 'E' -or $_.Level -eq 'F' -or $_.Message -match 'Exception|Failed|Fatal|unavailable|timeout|disconnect' }).Count
        $warningCount = ($group | Where-Object { $_.Level -eq 'W' -or $_.Message -match 'Retry|Disconnect|Slow response|Offline|Reconnect|Timeout' }).Count
        $success = if ($group.Message -match 'Package answer received|Programming completed|Done with SimonsVoss|Completed') { $true } else { $false }

        [PSCustomObject]@{
            SessionId = $sessionId
            StartTime = $start
            EndTime = $end
            Duration = [math]::Round($duration.TotalSeconds, 1)
            EventCount = $group.Count
            ErrorCount = $errorCount
            WarningCount = $warningCount
            Outcome = if ($errorCount -gt 0) { 'Error' } elseif (-not $success) { 'Incomplete' } else { 'Success' }
            SampleMessages = ($group | Select-Object -ExpandProperty Message | Select-Object -Unique | Select-Object -First 5)
        }
    }

    [PSCustomObject]@{
        ProgrammingSessionCount = $programmingSessions.Count
        ProgrammingSessions = $programmingSessions
        LoginEventCount = $loginSessions.Count
        LoginEvents = $loginSessions | Select-Object Timestamp, Level, Message, Component
        ServiceRestartCount = $serviceRestarts.Count
        ServiceRestartEvents = $serviceRestarts | Select-Object Timestamp, Level, Message, Component
        CommunicationEventCount = $communicationEvents.Count
        CommunicationEvents = $communicationEvents | Select-Object Timestamp, Level, Message, Component
    }
}

function Analyze-Issues {
    param(
        [object[]]$Entries
    )

    $issueBuckets = @{}

    foreach ($entry in $Entries) {
        $text = $entry.Message.ToLowerInvariant()
        $severity = if ($entry.Level -in 'E','F') { 'Critical' } elseif ($entry.Level -eq 'W') { 'Warning' } else { 'Informational' }

        if ($text -match 'exception|fatal|crash|unavailable|failed|timeout') {
            $key = 'Programming Failure or Exception'
            $severity = 'Critical'
        }
        elseif ($text -match 'retry|disconnect|slow response|offline|reconnect|timeout') {
            $key = 'Connectivity or Retry Issue'
            if ($severity -eq 'Informational') { $severity = 'Warning' }
        }
        elseif ($text -match 'database|sql server|mssql|postgresql|oracle') {
            $key = 'Database Access Issue'
            if ($severity -eq 'Informational') { $severity = 'Warning' }
        }
        elseif ($text -match 'completed|established|connected|started|sent|received') {
            $key = 'Informational Activity'
        }
        else {
            $key = 'General Message'
        }

        if (-not $issueBuckets.ContainsKey($key)) {
            $issueBuckets[$key] = [PSCustomObject]@{
                Title = $key
                Severity = $severity
                Count = 0
                Examples = @()
            }
        }

        $bucket = $issueBuckets[$key]
        $bucket.Count++
        if ($bucket.Examples.Count -lt 3) {
            $bucket.Examples += $entry.Message
        }
    }

    $issueBuckets.Values | Sort-Object @{Expression='Severity';Descending=$true}, @{Expression='Count';Descending=$true}
}

function Analyze-Patterns {
    param(
        [object[]]$Entries
    )

    $patterns = @{
        'Programming Timeout' = 'timeout';
        'Gateway Disconnect' = 'disconnect|offline';
        'SignalR Reconnect' = 'reconnect';
        'Database Connection Failure' = 'database|sql server|mssql|postgresql|oracle|unavailable';
        'Programming Failure or Exception' = 'exception|failed|fatal|crash';
    }

    $results = @()
    foreach ($patternName in $patterns.Keys) {
        $regex = [regex]::Escape($patterns[$patternName])
        $count = ($Entries | Where-Object { $_.Message -match $patterns[$patternName] }).Count
        if ($count -gt 0) {
            $results += [PSCustomObject]@{
                Pattern = $patternName
                Count = $count
                Examples = ($Entries | Where-Object { $_.Message -match $patterns[$patternName] } | Select-Object -First 3 -ExpandProperty Message)
            }
        }
    }

    $results | Sort-Object Count -Descending
}

function Generate-Timeline {
    param(
        [object[]]$Entries
    )

    $significant = $Entries | Where-Object {
        $_.Message -match 'Running SimonsVoss|Calling hub method SendProgrammingMessage|Package send|Package answer received|Notification|CardInfo set|ProgDataSetter|Programming completed|Completed|Exception|Failed|Disconnect|Offline|Timeout|Reconnect|Database' }

    $timeline = $significant | Sort-Object Timestamp | Select-Object Timestamp, @{Name='Summary';Expression={
        if ($_.Message -match 'Running SimonsVoss') { 'Programming message interpret started' }
        elseif ($_.Message -match 'Calling hub method SendProgrammingMessage') { 'SignalR programming message sent' }
        elseif ($_.Message -match 'Package send') { 'Packet sent to agent' }
        elseif ($_.Message -match 'Package answer received') { 'Packet answer received' }
        elseif ($_.Message -match 'Notification') { 'Notification event sent' }
        elseif ($_.Message -match 'CardInfo set') { 'Card information set' }
        elseif ($_.Message -match 'ProgDataSetter') { 'Programming data setter event' }
        elseif ($_.Message -match 'Exception|Failed|Fatal|Timeout|Disconnect|Offline|Reconnect|Database') { 'Issue detected' }
        else { $_.Message }
    }} | Select-Object -First 50

    $timeline
}

function Get-Recommendations {
    param(
        [object[]]$IssuePatterns,
        [object]$SessionSummary,
        [object]$EnvironmentSummary
    )

    $recs = @()

    $patternMap = @{}
    foreach ($item in $IssuePatterns) {
        $patternMap[$item.Pattern] = $item.Count
    }

    if ($patternMap['Gateway Disconnect'] -gt 2) {
        $recs += 'Gateway communication appears unstable. Verify network connectivity between gateway and server.'
    }
    if ($patternMap['Programming Timeout'] -gt 2) {
        $recs += 'Programming timeouts were detected. Review programmer/device stability and local network latency.'
    }
    if ($patternMap['Database Connection Failure'] -gt 0) {
        $recs += 'Database connection instability observed. Check SQL Server availability and credentials.'
    }
    if ($patternMap['Programming Failure or Exception'] -gt 0) {
        $recs += 'Exceptions or programming failures are present. Review the related stack traces and service health.'
    }
    if ($SessionSummary.ProgrammingSessionCount -gt 0 -and ($SessionSummary.ProgrammingSessions | Where-Object { $_.Outcome -eq 'Error' }).Count -gt 0) {
        $recs += 'One or more programming sessions ended with errors. Inspect session event details and device status.'
    }

    if (-not $recs) {
        $recs += 'No major issues identified by the automated pattern engine. Review the full activity timeline for normal operation.'
    }

    $recs
}

function Format-AXMConsoleReport {
    param(
        [object]$EnvironmentSummary,
        [object]$SessionSummary,
        [object[]]$Issues,
        [object[]]$Patterns,
        [string[]]$Recommendations,
        [object[]]$Timeline
    )

    Write-Host ('=' * 38)
    Write-Host 'AXM LOG ANALYSIS REPORT'
    Write-Host ('=' * 38)
    Write-Host ''
    Write-Host 'Environment'
    Write-Host '-----------'
    Write-Host "AXM Version: $($EnvironmentSummary.AXMVersion)"
    Write-Host "Database: $($EnvironmentSummary.DatabaseType)"
    if ($EnvironmentSummary.DatabaseVersion -and $EnvironmentSummary.DatabaseVersion -ne 'Unknown') { Write-Host "Database Version: $($EnvironmentSummary.DatabaseVersion)" }
    Write-Host "Connected Gateways: $($EnvironmentSummary.ConnectedGateways)"
    Write-Host "Detected Services: $(([string]::Join(', ', ($EnvironmentSummary.DetectedServices | Select-Object -First 5))) -replace ', $','')"
    Write-Host ''
    Write-Host 'Activity'
    Write-Host '--------'
    Write-Host "Programming Sessions: $($SessionSummary.ProgrammingSessionCount)"
    Write-Host "Login Events: $($SessionSummary.LoginEventCount)"
    Write-Host "Service Restart Events: $($SessionSummary.ServiceRestartCount)"
    Write-Host "Communication Events: $($SessionSummary.CommunicationEventCount)"
    Write-Host ''
    Write-Host 'Issues'
    Write-Host '------'
    foreach ($issue in $Issues | Select-Object -First 6) {
        Write-Host "$($issue.Title): $($issue.Count) [$($issue.Severity)]"
        if ($issue.Examples) {
            Write-Host "  Example: $($issue.Examples[0])"
        }
    }
    Write-Host ''
    Write-Host 'Recurring Patterns'
    Write-Host '------------------'
    foreach ($pattern in $Patterns | Select-Object -First 6) {
        Write-Host "$($pattern.Pattern): $($pattern.Count)"
    }
    Write-Host ''
    Write-Host 'Investigation Recommendations'
    Write-Host '-----------------------------'
    foreach ($rec in $Recommendations) {
        Write-Host "- $rec"
    }
    Write-Host ''
    Write-Host 'Timeline (significant events)'
    Write-Host '------------------------------'
    foreach ($item in $Timeline | Select-Object -First 8) {
        $timeText = $item.Timestamp.ToString('HH:mm:ss')
        Write-Host "$timeText $($item.Summary)"
    }
    Write-Host ''
}

function Export-AXMJsonReport {
    param(
        [object]$EnvironmentSummary,
        [object]$SessionSummary,
        [object[]]$Issues,
        [object[]]$Patterns,
        [string[]]$Recommendations,
        [object[]]$Timeline,
        [string]$OutputPath
    )

    $report = [PSCustomObject]@{
        environment = $EnvironmentSummary
        activity = [PSCustomObject]@{
            programmingSessions = $SessionSummary.ProgrammingSessions
            loginEventCount = $SessionSummary.LoginEventCount
            serviceRestartCount = $SessionSummary.ServiceRestartCount
            communicationEventCount = $SessionSummary.CommunicationEventCount
        }
        issues = $Issues
        patterns = $Patterns
        recommendations = $Recommendations
        timeline = $Timeline
    }

    if ($OutputPath) {
        $report | ConvertTo-Json -Depth 6 | Set-Content -Path $OutputPath -Encoding UTF8
        Write-Host "JSON report written to $OutputPath"
    }
    else {
        $report | ConvertTo-Json -Depth 6
    }
}

# Main execution
try {
    if (-not (Test-Path -Path $Path)) {
        throw "Log file not found: $Path"
    }

    $entries = Get-AXMLogEntries -LogPath $Path
    if (-not $entries) {
        throw "No parsable log entries found in $Path"
    }

    $environmentSummary = Analyze-Environment -Entries $entries -LogPath $Path
    $sessionSummary = Analyze-Sessions -Entries $entries
    $issues = Analyze-Issues -Entries $entries
    $patterns = Analyze-Patterns -Entries $entries
    $timeline = Generate-Timeline -Entries $entries
    $recommendations = Get-Recommendations -IssuePatterns $patterns -SessionSummary $sessionSummary -EnvironmentSummary $environmentSummary

    if ($Json) {
        $outputPath = if ($Output) { $Output } else { [System.IO.Path]::ChangeExtension($Path, '.json') }
        Export-AXMJsonReport -EnvironmentSummary $environmentSummary -SessionSummary $sessionSummary -Issues $issues -Patterns $patterns -Recommendations $recommendations -Timeline $timeline -OutputPath $outputPath
    }
    else {
        Format-AXMConsoleReport -EnvironmentSummary $environmentSummary -SessionSummary $sessionSummary -Issues $issues -Patterns $patterns -Recommendations $recommendations -Timeline $timeline
    }
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
