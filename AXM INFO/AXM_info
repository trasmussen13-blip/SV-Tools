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
    [switch]$All
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

function Get-AXMServiceInfo {
    [OutputType([PSCustomObject])]
    param()

    $matchPattern = '(?i)(axm|SimonsVoss)'

    Get-CimInstance -ClassName Win32_Service |
        Where-Object {
            $_.Name -match $matchPattern -or $_.DisplayName -match $matchPattern
        } |
        Select-Object -Property Name, DisplayName, State, StartMode, Status, PathName, StartName,
            @{Name='Ports';Expression={ Get-ServiceListeningPorts -ProcessId $_.ProcessId }}
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

        $subfolders = Get-ChildItem -Path $repo.FullName -Directory -Recurse -ErrorAction SilentlyContinue
        foreach ($subfolder in $subfolders) {
            $relativeName = $subfolder.FullName.Substring($repo.FullName.Length + 1)
            $subfolderSizeBytes = (Get-ChildItem -Path $subfolder.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
            $subfolderSizeMB = if ($subfolderSizeBytes) { [math]::Round($subfolderSizeBytes / 1MB, 2) } else { 0 }
            $subfolderSizeText = "{0:N2} MB" -f $subfolderSizeMB
            $hasMdf = Test-Path (Join-Path $subfolder.FullName 'lsmax.mdf')
            $hasLog = Test-Path (Join-Path $subfolder.FullName 'lsmax_log.ldf')
            $status = if ($hasMdf -and $hasLog) { 'OK' } else { 'Missing' }

            $results += [PSCustomObject]@{
                Repository      = $repo.Name
                RepositorySize  = $repoSizeText
                SubfolderName   = $relativeName
                SubfolderSize   = $subfolderSizeText
                FullPath        = $subfolder.FullName
                Status          = $status
                LsmaxMdf        = $hasMdf
                LsmaxLogMdf     = $hasLog
            }
        }
    }

    $results
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
    Write-Host "Usage: .\Check-AXMInstances.ps1 [-Services] [-Software] [-SQL] [-MainDB] [-Repository] [-All]" -ForegroundColor Yellow
    Write-Host "If no switch is provided, the script runs Services, Software, SQL, MainDB, and Repository checks." -ForegroundColor Yellow
}

if (-not ($Services -or $Software -or $SQL -or $MainDB -or $Repository -or $All)) {
    $Services = $true
    $Software = $true
    $SQL = $true
    $MainDB = $true
    $Repository = $true
}

if ($All) {
    $Services = $true
    $Software = $true
    $SQL = $true
    $MainDB = $true
    $Repository = $true
}

if (-not ($Services) -and -not ($Software) -and -not ($SQL) -and -not ($MainDB) -and -not ($Repository)) {
    Show-Usage
    exit 1
}

if ($Services) {
    Write-Host "\nScanning for AXM services..." -ForegroundColor Cyan
    $serviceResults = Get-AXMServiceInfo
    if ($serviceResults) {
        $serviceResults | Format-Table -AutoSize
    } else {
        Write-Host "No AXM services found." -ForegroundColor Yellow
    }
}

if ($Software) {
    Write-Host "\nScanning for installed AXM software..." -ForegroundColor Cyan
    $softwareResults = Get-AXMSoftwareInfo
    if ($softwareResults) {
        $softwareResults | Select-Object DisplayName, DisplayVersion, Publisher, InstallLocation | Format-Table -AutoSize
    } else {
        Write-Host "No AXM-related software entries found in installed programs." -ForegroundColor Yellow
    }
}

if ($MainDB) {
    Write-Host "\nScanning for main_* configuration under ProgramData\SimonsVoss\LockSysMgr\config..." -ForegroundColor Cyan
    $mainResults = Get-LockSysMgrMainInfo
    if ($mainResults) {
        $mainResults | Format-Table -AutoSize
    } else {
        Write-Host "No LockSysMgr config directory found." -ForegroundColor Yellow
    }
}

if ($Repository) {
    Write-Host "\nScanning for repository subfolders under ProgramData\SimonsVoss\Repository-*..." -ForegroundColor Cyan
    $repoResults = Get-LockSysMgrRepositoryInfo
    if ($repoResults) {
        $repoResults | Select-Object Repository, RepositorySize, SubfolderName, SubfolderSize, Status | Format-Table -AutoSize
    } else {
        Write-Host "No Repository-* folders found under ProgramData\SimonsVoss." -ForegroundColor Yellow
    }
}

if ($SQL) {
    Write-Host "\nScanning for installed SQL Server instances..." -ForegroundColor Cyan
    $sqlResults = Get-SQLInstanceInfo
    if ($sqlResults) {
        $sqlResults | Select-Object InstanceName, InstanceType, Edition, Version, ServiceName, ServiceStatus | Format-Table -AutoSize
    } else {
        Write-Host "No SQL Server or LocalDB instances detected." -ForegroundColor Yellow
    }
}
