<#
.SYNOPSIS
    Checks the local machine for installed AXM services and AXM-related software.

.DESCRIPTION
    This script scans Windows services and installed applications for names
    containing "AXM", "SimonsVoss", SQL Express, or SQL Server Express LocalDB.
    It helps identify installed AXM instances and SQL Server Express installations
    by service and software inventory.

.EXAMPLE
    .\Check-AXMInstances.ps1

.EXAMPLE
    .\Check-AXMInstances.ps1 -Services

.EXAMPLE
    .\Check-AXMInstances.ps1 -Software
#>

[CmdletBinding()]
param(
    [switch]$Services,
    [switch]$Software,
    [switch]$SQL,
    [switch]$MainDB,
    [switch]$Repository,
    [switch]$Log,
    [switch]$All,
    [switch]$Dump,
    [string]$OutFile = "$env:COMPUTERNAME - AXM-info.txt"
)

function Get-ServiceListeningPorts {
    [OutputType([string])]
    param(
        [int]$ProcessId
    )

    if (-not $ProcessId -or $ProcessId -eq 0) {
        return $null
    }

    $ports = @()
    $tcpPorts = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
        Where-Object { $_.OwningProcess -eq $ProcessId } |
        Select-Object -ExpandProperty LocalPort -Unique
    $udpPorts = Get-NetUDPEndpoint -ErrorAction SilentlyContinue |
        Where-Object { $_.OwningProcess -eq $ProcessId } |
        Select-Object -ExpandProperty LocalPort -Unique

    if ($tcpPorts) {
        $ports += ($tcpPorts | Sort-Object | ForEach-Object { "TCP:$($_)" })
    }
    if ($udpPorts) {
        $ports += ($udpPorts | Sort-Object | ForEach-Object { "UDP:$($_)" })
    }

    if ($ports.Count -gt 0) {
        return $ports -join ', '
    }

    return $null
}

function Get-ServiceDependencyTree {
    [OutputType([string])]
    param(
        [Parameter(Mandatory=$true)] [string]$ServiceName
    )

    $visited = @{}

    function BuildTree {
        param([string]$Name, [int]$Level)
        if ($visited.ContainsKey($Name)) {
            return (" " * ($Level*2)) + "- $Name (circular)"
        }
        $visited[$Name] = $true

        $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
        if (-not $svc) {
            return (" " * ($Level*2)) + "- $Name (not found)"
        }

        $indent = " " * ($Level*2)
        $line = "$indent- $($svc.Name) [$($svc.Status)]"

        $deps = $svc.ServicesDependedOn
        if ($deps) {
            foreach ($d in $deps) {
                $line += "`n" + (BuildTree -Name $d.Name -Level ($Level + 1))
            }
        }
        return $line
    }

    return BuildTree -Name $ServiceName -Level 0
}


function Get-AXMServiceInfo {
    [OutputType([PSCustomObject])]
    param()

    $matchPattern = '(?i)(axm|SimonsVoss)'

    Get-CimInstance -ClassName Win32_Service |
        Where-Object {
            $_.Name -match $matchPattern -or $_.DisplayName -match $matchPattern
        } |
        Select-Object -Property Name, DisplayName, State, StartMode, Status, PathName, StartName,
            @{Name='LastErrorCode';Expression={ $_.ExitCode }},
            @{Name='Ports';Expression={ Get-ServiceListeningPorts -ProcessId $_.ProcessId }},
            @{Name='Dependencies';Expression={
                $svc = Get-Service -Name $_.Name -ErrorAction SilentlyContinue
                if ($svc -and $svc.ServicesDependedOn) {
                    ($svc.ServicesDependedOn | ForEach-Object { "$($_.Name) [$($_.Status)]" }) -join ', '
                } else {
                    $null
                }
            }},
            @{Name='Dependents';Expression={
                $svc = Get-Service -Name $_.Name -ErrorAction SilentlyContinue
                if ($svc -and $svc.DependentServices) {
                    ($svc.DependentServices | ForEach-Object { "$($_.Name) [$($_.Status)]" }) -join ', '
                } else {
                    $null
                }
            }},
            @{Name='DependencyTree';Expression={ Get-ServiceDependencyTree -ServiceName $_.Name }}
}

function Get-AXMSoftwareInfo {
    [OutputType([PSCustomObject])]
    param()

    $matchPattern = '(?i)(axm|SimonsVoss)'
    $registryPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )

    $software = foreach ($path in $registryPaths) {
        if (-not (Test-Path $path)) { continue }

        Get-ChildItem -Path $path -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $props = Get-ItemProperty -Path $_.PSPath -ErrorAction Stop
                [PSCustomObject]@{
                    DisplayName     = $props.DisplayName
                    DisplayVersion  = $props.DisplayVersion
                    Publisher       = $props.Publisher
                    InstallDate     = $props.InstallDate
                    InstallLocation = $props.InstallLocation
                    UninstallString = $props.UninstallString
                    RegistryPath    = $_.PSPath
                }
            } catch {
                # skip entries that cannot be read
            }
        }
    }

    $software |
        Where-Object {
            ($_.DisplayName -and $_.DisplayName -match $matchPattern) -or
            ($_.Publisher -and $_.Publisher -match $matchPattern)
        } |
        Sort-Object -Property DisplayName
}

function Get-LockSysMgrMainInfo {
    [OutputType([PSCustomObject])]
    param()

    $configRoot = Join-Path $env:ProgramData 'SimonsVoss\LockSysMgr\config'
    if (-not (Test-Path $configRoot)) {
        return @()
    }

    $results = @()
    $nameMatches = Get-ChildItem -Path $configRoot -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '(?i)^main_' }
    foreach ($item in $nameMatches) {
        $results += [PSCustomObject]@{
            Path       = $item.FullName
            ObjectType = if ($item.PSIsContainer) { 'Directory' } else { 'File' }
            MatchType  = 'Name'
            Details    = $null
        }
    }

    $configFiles = Get-ChildItem -Path $configRoot -Recurse -Force -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in '.xml', '.json', '.ini', '.cfg', '.conf', '.txt' }
    foreach ($file in $configFiles) {
        $matches = Select-String -Path $file.FullName -Pattern '(?i)main_' -ErrorAction SilentlyContinue
        foreach ($match in $matches) {
            $results += [PSCustomObject]@{
                Path       = $file.FullName
                ObjectType = 'File'
                MatchType  = 'Content'
                Details    = $match.Line.Trim()
            }
        }
    }

    if ($results.Count -eq 0) {
        $results += [PSCustomObject]@{
            Path       = $configRoot
            ObjectType = 'Directory'
            MatchType  = 'ConfigFolderExists'
            Details    = 'Config directory exists, but no main_* entries or Repository-* folders were found.'
        }
    }

    $results
}

function Get-LockSysMgrRepositoryInfo {
    [OutputType([PSCustomObject])]
    param()

    $repoRoot = Join-Path $env:ProgramData 'SimonsVoss'
    if (-not (Test-Path $repoRoot)) {
        return @()
    }

    $results = @()
    $repoDirs = Get-ChildItem -Path $repoRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like 'Repository-*' }
    foreach ($repo in $repoDirs) {
        $repoSizeBytes = (Get-ChildItem -Path $repo.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        $repoSizeMB = if ($repoSizeBytes) { [math]::Round($repoSizeBytes / 1MB, 2) } else { 0 }
        $repoSizeText = "{0:N2} MB" -f $repoSizeMB

        $subfolders = Get-ChildItem -Path $repo.FullName -Directory -ErrorAction SilentlyContinue
        foreach ($subfolder in $subfolders) {
            $relativeName = $subfolder.FullName.Substring($repo.FullName.Length + 1)
            $subfolderSizeBytes = (Get-ChildItem -Path $subfolder.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
            $subfolderSizeMB = if ($subfolderSizeBytes) { [math]::Round($subfolderSizeBytes / 1MB, 2) } else { 0 }
            $subfolderSizeText = "{0:N2} MB" -f $subfolderSizeMB
            $hasMdf = Test-Path (Join-Path $subfolder.FullName 'lsmax.mdf')
            $hasLog = Test-Path (Join-Path $subfolder.FullName 'lsmax_log.ldf')
            $status = if ($hasMdf -and $hasLog) { 'OK' } else { 'Missing' }

            $mdfPath = Join-Path $subfolder.FullName 'lsmax.mdf'
            $mdfInfo = if (Test-Path $mdfPath) { Get-Item -Path $mdfPath -ErrorAction SilentlyContinue } else { $null }

            $results += [PSCustomObject]@{
                Repository             = $repo.Name
                RepositorySize         = $repoSizeText
                SubfolderName          = $relativeName
                SubfolderSize          = $subfolderSizeText
                FullPath               = $subfolder.FullName
                Status                 = $status
                LsmaxMdf               = $hasMdf
                LsmaxMdfName           = if ($mdfInfo) { $mdfInfo.Name } else { $null }
                LsmaxMdfLength         = if ($mdfInfo) { $mdfInfo.Length } else { $null }
                LsmaxMdfCreationTime   = if ($mdfInfo) { $mdfInfo.CreationTime } else { $null }
                LsmaxMdfLastWriteTime  = if ($mdfInfo) { $mdfInfo.LastWriteTime } else { $null }
                LsmaxLogMdf            = $hasLog
            }
        }
    }

    $results
}

function Get-LockSysMgrLogInfo {
    [OutputType([PSCustomObject])]
    param()

    $logRoot = Join-Path $env:LOCALAPPDATA 'SimonsVoss\LockSysMgr\log'
    if (-not (Test-Path $logRoot)) {
        return @()
    }

    $logFile = Get-ChildItem -Path $logRoot -File -Filter 'AXM*' -ErrorAction SilentlyContinue |
        Sort-Object -Property LastWriteTime -Descending |
        Select-Object -First 1

    if (-not $logFile) {
        return @()
    }

    $lines = Get-Content -Path $logFile.FullName -ErrorAction SilentlyContinue
    $licenseLine = $lines | Where-Object { $_ -match 'Query \{"\$type":"GetLicense"\} done; Response:' } | Select-Object -Last 1
    if (-not $licenseLine) {
        return [PSCustomObject]@{
            LogFile       = $logFile.FullName
            FoundLicense  = $false
            Error         = 'No GetLicense response found in latest AXM log.'
        }
    }

    $responseIndex = $licenseLine.IndexOf('Response:')
    $jsonText = if ($responseIndex -ge 0) { $licenseLine.Substring($responseIndex + 9).Trim() } else { $null }
    if (-not $jsonText) {
        return [PSCustomObject]@{
            LogFile       = $logFile.FullName
            FoundLicense  = $true
            Error         = 'Response JSON section could not be extracted.'
        }
    }

    # Trim trailing non-JSON suffix such as XML-style log metadata
    if ($jsonText -match '^(.*\})(?:\s*<s:.*)?$') {
        $jsonText = $matches[1].Trim()
    }

    try {
        $licenseData = $jsonText | ConvertFrom-Json -ErrorAction Stop
        $registration = $licenseData.RegistrationDetails
        $subscription = $licenseData.SubscriptionInfo
        return [PSCustomObject]@{
            LogFile                  = $logFile.FullName
            FoundLicense             = $true
            LicenseType              = $licenseData.Type
            SoftwareEdition          = $licenseData.SoftwareEdition
            StartDate                = $licenseData.StartDate
            ExpirationDate           = $licenseData.ExpirationDate
            CompanyName              = $registration.CompanyName
            City                     = $registration.City
            Country                  = $registration.Country
            Email                    = $registration.Email
            LicenseKey               = $registration.LicenseKey
            CommissionNumber         = $registration.CommissionNumber
            SubscriptionExpiryDate   = $subscription.ExpiryDate
            PaymentApproved          = $subscription.PaymentApproved
            AreOnlineFeaturesAllowed = $licenseData.AreOnlineFeaturesAllowed
            IsDeactivated            = $licenseData.IsDeactivated
        }
    } catch {
        return [PSCustomObject]@{
            LogFile       = $logFile.FullName
            FoundLicense  = $true
            Error         = "Failed to parse license JSON: $($_.Exception.Message)"
            RawResponse   = $jsonText
        }
    }
}

function Get-SQLServerInstanceInfo {
    [OutputType([PSCustomObject])]
    param()

    $instances = @()
    $registryPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Microsoft SQL Server\Instance Names\SQL'
    )

    foreach ($path in $registryPaths) {
        if (-not (Test-Path $path)) { continue }

        $props = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue
        foreach ($property in $props.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' }) {
            $instanceName = $property.Name
            $instanceId = $property.Value
            $setupPath = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$instanceId\Setup"
            if (-not (Test-Path $setupPath)) {
                $setupPath = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Microsoft SQL Server\$instanceId\Setup"
            }

            $setupProps = if (Test-Path $setupPath) { Get-ItemProperty -Path $setupPath -ErrorAction SilentlyContinue } else { $null }
            $edition = $setupProps.Edition
            $version = $setupProps.Version
            $serviceName = "MSSQL`$$instanceName"
            $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
            $serviceStatus = if ($service) { $service.Status } else { 'Not found' }

            $instances += [PSCustomObject]@{
                InstanceName = $instanceName
                InstanceType = 'Database Engine'
                InstanceId   = $instanceId
                Edition      = $edition
                Version      = $version
                ServiceName  = $serviceName
                ServiceStatus= $serviceStatus
                RegistryPath = $path
            }
        }
    }

    $instances
}

function Get-SQLLocalDBInstanceInfo {
    [OutputType([PSCustomObject])]
    param()

    $instances = @()
    $localDbCmd = Get-Command sqllocaldb -ErrorAction SilentlyContinue

    if ($localDbCmd) {
        $instanceNames = & $localDbCmd.Source i 2>$null
        foreach ($instanceName in $instanceNames) {
            $instanceName = $instanceName.Trim()
            if ([string]::IsNullOrWhiteSpace($instanceName)) { continue }

            $infoLines = & $localDbCmd.Source i $instanceName 2>$null
            $info = @{}
            foreach ($line in $infoLines) {
                if ($line -match '^(?<name>[^:]+)\s*:\s*(?<value>.+)$') {
                    $info[$matches['name'].Trim()] = $matches['value'].Trim()
                }
            }

            $instances += [PSCustomObject]@{
                InstanceName = $instanceName
                InstanceType = 'LocalDB'
                Edition      = $info['Edition']
                Version      = $info['Version']
                State        = $info['State']
                LastStartTime= $info['Last start time']
                CreationTime = $info['Creation time']
                RegistryPath = 'sqllocaldb'
            }
        }
    } else {
        $localDbRegistryPath = 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server Local DB\Installed Versions'
        if (Test-Path $localDbRegistryPath) {
            Get-ChildItem -Path $localDbRegistryPath -ErrorAction SilentlyContinue | ForEach-Object {
                $props = Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue
                $instances += [PSCustomObject]@{
                    InstanceName = $_.PSChildName
                    InstanceType = 'LocalDB Version'
                    Edition      = $null
                    Version      = $props.Version
                    State        = 'Installed'
                    CreationTime = $null
                    RegistryPath = $_.PSPath
                }
            }
        }
    }

    $instances
}

function Get-SQLInstanceInfo {
    [OutputType([PSCustomObject])]
    param()

    $instances = @()
    $instances += Get-SQLServerInstanceInfo
    $instances += Get-SQLLocalDBInstanceInfo
    $instances
}

function Show-Usage {
    Write-Host "Usage: .\Check-AXMInstances.ps1 [-Services] [-Software] [-SQL] [-MainDB] [-Repository] [-Log] [-All]" -ForegroundColor Yellow
    Write-Host "If no switch is provided, the script runs Log, Software, Services, Repository, MainDB, and SQL checks." -ForegroundColor Yellow
}

# If no arguments were provided, offer an interactive prompt to select checks.
$noArgs = -not ($Services -or $Software -or $SQL -or $MainDB -or $Repository -or $Log -or $All)
$dumpConfirmed = $false
if ($noArgs) {
    try {
        $runAllAnswer = Read-Host "No arguments provided. Run all checks? (Y/N) [Y]"
        if ($runAllAnswer -and $runAllAnswer -match '^(?i:n|no)$') {
            $svcAns = Read-Host "Run Services? (Y/N) [Y]"
            $Services = -not ($svcAns -and $svcAns -match '^(?i:n|no)$')

            $softAns = Read-Host "Run Software scan? (Y/N) [Y]"
            $Software = -not ($softAns -and $softAns -match '^(?i:n|no)$')

            $sqlAns = Read-Host "Run SQL instance scan? (Y/N) [Y]"
            $SQL = -not ($sqlAns -and $sqlAns -match '^(?i:n|no)$')

            $mainAns = Read-Host "Run Main DB config scan? (Y/N) [Y]"
            $MainDB = -not ($mainAns -and $mainAns -match '^(?i:n|no)$')

            $repoAns = Read-Host "Run Repository scan? (Y/N) [Y]"
            $Repository = -not ($repoAns -and $repoAns -match '^(?i:n|no)$')

            $logAns = Read-Host "Run latest AXM log lookup? (Y/N) [Y]"
            $Log = -not ($logAns -and $logAns -match '^(?i:n|no)$')

            $dumpAns = Read-Host "Save report to file? (Y/N) [N]"
            if ($dumpAns -and $dumpAns -match '^(?i:y|yes)$') {
                $Dump = $true
                $dumpConfirmed = $true
                $customOut = Read-Host "Output filename (press Enter to use default: $OutFile)"
                if ($customOut) { $OutFile = $customOut }
            }
        } else {
            $Services = $true
            $Software = $true
            $SQL = $true
            $MainDB = $true
            $Repository = $true
            $Log = $true
        }
    } catch {
        # Non-interactive host (Read-Host unavailable) — fall back to previous behavior
        $Services = $true
        $Software = $true
        $SQL = $true
        $MainDB = $true
        $Repository = $true
        $Log = $true
    }
}

if ($All) {
    $Services = $true
    $Software = $true
    $SQL = $true
    $MainDB = $true
    $Repository = $true
    $Log = $true
}

# Handle optional dumping of script output to a file using Start-Transcript
$transcribing = $false
if (-not $Dump) {
    # If Dump wasn't provided on the CLI, offer to save now (works for interactive and non-interactive selections when host supports Read-Host)
    try {
        $saveNow = Read-Host "Save report to file? (Y/N)"
        if ($saveNow -and $saveNow -match '^(?i:y|yes)$') {
            $Dump = $true
            $dumpConfirmed = $true
            $customOut = Read-Host "Output filename (press Enter to use default: $OutFile)"
            if ($customOut) { $OutFile = $customOut }
        }
    } catch {
        # Read-Host not available; do nothing
    }
}

if ($Dump) {
    $outfileFull = Join-Path (Get-Location).Path $OutFile

    if ($dumpConfirmed) {
        try {
            Start-Transcript -Path $outfileFull -Force -ErrorAction Stop
            $transcribing = $true
            $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
            Write-Host "=== AXM Info Report ==="
            Write-Host "Timestamp: $timestamp"
        } catch {
            Write-Warning "Failed to start transcript to '$outfileFull': $($_.Exception.Message)"
        }
    } else {
        $saveReport = $true
        try {
            $answer = Read-Host "Save report to '$outfileFull'? (Y/N)"
            if ($answer -and $answer -match '^(?i:n|no)$') {
                $saveReport = $false
            }
        } catch {
            Write-Verbose "Read-Host unavailable; defaulting to save report."
        }

        if (-not $saveReport) {
            Write-Host "Skipping report save as requested." -ForegroundColor Yellow
        } else {
            try {
                Start-Transcript -Path $outfileFull -Force -ErrorAction Stop
                $transcribing = $true
                $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                Write-Host "=== AXM Info Report ==="
                Write-Host "Timestamp: $timestamp"
            } catch {
                Write-Warning "Failed to start transcript to '$outfileFull': $($_.Exception.Message)"
            }
        }
    }
}

if (-not ($Services) -and -not ($Software) -and -not ($SQL) -and -not ($MainDB) -and -not ($Repository) -and -not ($Log)) {
    Show-Usage
    exit 1
}

if ($Log) {
    Write-Host "\nAXM log lookup from AppData\Local\SimonsVoss\LockSysMgr\log..." -ForegroundColor Cyan
    $logResults = Get-LockSysMgrLogInfo
    if ($logResults) {
        $logResults | Format-List
    } else {
        Write-Host "No AXM log information found." -ForegroundColor Yellow
    }
}

if ($Software) {
    Write-Host "\nInstalled AXM software..." -ForegroundColor Cyan
    $softwareResults = Get-AXMSoftwareInfo
    if ($softwareResults) {
        $softwareResults | Select-Object DisplayName, DisplayVersion, Publisher, InstallLocation | Format-Table -AutoSize
    } else {
        Write-Host "No AXM-related software entries found in installed programs." -ForegroundColor Yellow
    }
}

if ($Services) {
    Write-Host "\nAXM services..." -ForegroundColor Cyan
    $serviceResults = Get-AXMServiceInfo
    if ($serviceResults) {
        $serviceResults | Format-Table -AutoSize
    } else {
        Write-Host "No AXM services found." -ForegroundColor Yellow
    }
}

if ($Repository) {
    Write-Host "\nRepository scan under ProgramData\SimonsVoss..." -ForegroundColor Cyan
    $repoResults = Get-LockSysMgrRepositoryInfo
    if ($repoResults) {
        $repoResults | Select-Object Repository, RepositorySize, SubfolderName, SubfolderSize, Status | Format-Table -AutoSize
    } else {
        Write-Host "No Repository-* folders found under ProgramData\SimonsVoss." -ForegroundColor Yellow
    }
}

if ($SQL) {
    Write-Host "\nDatabase instances..." -ForegroundColor Cyan
    $sqlResults = Get-SQLInstanceInfo
    if ($sqlResults) {
        $sqlResults | Select-Object InstanceName, InstanceType, Edition, Version, ServiceName, ServiceStatus | Format-Table -AutoSize
    } else {
        Write-Host "No SQL Server or LocalDB instances detected." -ForegroundColor Yellow
    }
}

if ($transcribing) {
    try {
        Stop-Transcript | Out-Null
        Write-Host "\nDump saved to: $outfileFull" -ForegroundColor Green
    } catch {
        Write-Warning "Failed to stop transcript: $($_.Exception.Message)"
    }
}
