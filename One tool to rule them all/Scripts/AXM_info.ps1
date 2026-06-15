<#'
.NAME
    AXM_info
.VERSION
    1.2.0
.CATEGORY
    AXM Diagnostics       
.SYNOPSIS
    Checks the local machine for installed AXM services and AXM-related software.
.DESCRIPTION
    Scans Windows services, installed applications, SQL Server/LocalDB instances,
    LockSysMgr config, repository folders, and parses the latest AXM log for
    license info. Self-elevating. Transcript saved to script folder.
.ADMIN
    YES
.EXAMPLE
    .\AXM_info.ps1
.EXAMPLE
    .\AXM_info.ps1 -All -Dump
.EXAMPLE
    .\AXM_info.ps1 -Services -Software
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
    [switch]$NonInteractive,
    [string]$OutFile = "$env:COMPUTERNAME - AXM-info.txt"
)

# ------------------------------------------------------------------
# Self-elevation
# ------------------------------------------------------------------
function Convert-BoundParamsToArgList {
    param([hashtable]$BoundParams)
    $list = @()
    foreach ($k in $BoundParams.Keys) {
        $v = $BoundParams[$k]
        if ($v -is [System.Management.Automation.SwitchParameter]) {
            if ($v.IsPresent) { $list += "-$k" }
        } elseif ($null -ne $v -and $v -ne '') {
            $list += "-$k"
            $list += "$v"
        }
    }
    return ,$list
}

$currentIdentity  = [Security.Principal.WindowsIdentity]::GetCurrent()
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
$isAdmin          = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    try {
        $argList  = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
        $argList += Convert-BoundParamsToArgList -BoundParams $PSBoundParameters
        Start-Process -FilePath (Get-Command powershell.exe).Source -ArgumentList $argList -Verb RunAs -WindowStyle Normal
    } catch {
        Write-Error "Failed to relaunch elevated: $($_.Exception.Message)"
    }
    exit
}

# ------------------------------------------------------------------
# Resolve OutFile to script folder (avoids System32 on elevation)
# ------------------------------------------------------------------
function Get-AbsoluteOutFile {
    param([string]$Out)
    if ([string]::IsNullOrWhiteSpace($Out)) { return $null }
    if (-not [System.IO.Path]::IsPathRooted($Out)) {
        $base = if ($PSScriptRoot) { $PSScriptRoot } else {
            Split-Path -Parent $MyInvocation.MyCommand.Path
        }
        $Out = Join-Path -Path $base -ChildPath $Out
    }
    try {
        $dir     = [System.IO.Path]::GetDirectoryName($Out)
        $file    = [System.IO.Path]::GetFileName($Out)
        $invalid = [System.IO.Path]::GetInvalidFileNameChars()
        $clean   = -join ($file.ToCharArray() | ForEach-Object {
            if ($invalid -contains $_) { '_' } else { $_ }
        })
        if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -LiteralPath $dir)) {
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
        }
        return Join-Path -Path $dir -ChildPath $clean
    } catch {
        return $Out
    }
}

# ------------------------------------------------------------------
# Output helpers — prevent truncation in transcript
# ------------------------------------------------------------------
function Write-Table {
    param(
        [Parameter(Mandatory,ValueFromPipeline)]$InputObject,
        [string[]]$Properties
    )
    begin   { $all = @() }
    process { $all += $InputObject }
    end {
        if (-not $all) { return }
        $sel = if ($Properties) { $all | Select-Object $Properties } else { $all }
        $sel | Format-Table -AutoSize | Out-String -Width 4096 | Write-Host
    }
}

function Write-Detail {
    param([Parameter(Mandatory,ValueFromPipeline)]$InputObject)
    process {
        $InputObject | Format-List * | Out-String -Width 4096 | Write-Host
        Write-Host ('-' * 60)
    }
}

# ------------------------------------------------------------------
# Port lookup with netstat fallback
# ------------------------------------------------------------------
function Get-ServiceListeningPorts {
    [OutputType([string])]
    param([int]$ProcessId)
    if (-not $ProcessId -or $ProcessId -eq 0) { return $null }
    $ports = @()
    try {
        $tcpPorts = Get-NetTCPConnection -State Listen -ErrorAction Stop |
            Where-Object { $_.OwningProcess -eq $ProcessId } |
            Select-Object -ExpandProperty LocalPort -Unique
        $udpPorts = Get-NetUDPEndpoint -ErrorAction Stop |
            Where-Object { $_.OwningProcess -eq $ProcessId } |
            Select-Object -ExpandProperty LocalPort -Unique
        if ($tcpPorts) { $ports += ($tcpPorts | Sort-Object | ForEach-Object { "TCP:$_" }) }
        if ($udpPorts) { $ports += ($udpPorts | Sort-Object | ForEach-Object { "UDP:$_" }) }
    } catch {
        try {
            $netstat = & netstat -ano 2>$null
            foreach ($line in $netstat) {
                if ($line -match '^\s*TCP\s+\S+:(?<port>\d+)\s+\S+\s+LISTENING\s+(?<pid>\d+)') {
                    if ([int]$Matches['pid'] -eq $ProcessId) { $ports += "TCP:$($Matches['port'])" }
                }
                if ($line -match '^\s*UDP\s+\S+:(?<port>\d+)\s+\*:\*\s+(?<pid>\d+)') {
                    if ([int]$Matches['pid'] -eq $ProcessId) { $ports += "UDP:$($Matches['port'])" }
                }
            }
            $ports = $ports | Select-Object -Unique
        } catch {}
    }
    if ($ports.Count -gt 0) { return ($ports -join ', ') }
    return $null
}

# ------------------------------------------------------------------
# Dependency tree
# ------------------------------------------------------------------
function Get-ServiceDependencyTree {
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$ServiceName)
    $visited = @{}
    function BuildTree {
        param([string]$Name,[int]$Level)
        if ($visited.ContainsKey($Name)) {
            return (" " * ($Level * 2)) + "- $Name (circular)"
        }
        $visited[$Name] = $true
        $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
        if (-not $svc) { return (" " * ($Level * 2)) + "- $Name (not found)" }
        $indent = " " * ($Level * 2)
        $line   = "$indent- $($svc.Name) [$($svc.Status)]"
        if ($svc.ServicesDependedOn) {
            foreach ($d in $svc.ServicesDependedOn) {
                $line += "`n" + (BuildTree -Name $d.Name -Level ($Level + 1))
            }
        }
        return $line
    }
    return BuildTree -Name $ServiceName -Level 0
}

# ------------------------------------------------------------------
# AXM services — full info
# ------------------------------------------------------------------
function Get-AXMServiceInfo {
    [OutputType([PSCustomObject])]
    param()
    $matchPattern = '(?i)(axm|SimonsVoss)'
    Get-CimInstance -ClassName Win32_Service |
        Where-Object { $_.Name -match $matchPattern -or $_.DisplayName -match $matchPattern } |
        ForEach-Object {
            $cim = $_
            $svc = Get-Service -Name $cim.Name -ErrorAction SilentlyContinue

            $dependencies = $null
            if ($svc -and $svc.ServicesDependedOn) {
                $d = @($svc.ServicesDependedOn |
                    ForEach-Object { "$($_.Name) [$($_.Status)]" } | Sort-Object)
                if ($d.Count -gt 0) { $dependencies = $d -join ', ' }
            }

            $dependents = $null
            if ($svc -and $svc.DependentServices) {
                $d2 = @($svc.DependentServices |
                    ForEach-Object { "$($_.Name) [$($_.Status)]" } | Sort-Object)
                if ($d2.Count -gt 0) { $dependents = $d2 -join ', ' }
            }

            $procStartTime = $null
            if ($cim.ProcessId -and $cim.ProcessId -ne 0) {
                try {
                    $proc = Get-Process -Id $cim.ProcessId -ErrorAction Stop
                    $procStartTime = $proc.StartTime
                } catch {}
            }

            $exitCode           = $cim.ExitCode
            $svcSpecificCode    = $cim.ServiceSpecificExitCode
            $exitCodeHex        = if ($null -ne $exitCode)        { '0x{0:X}' -f [uint32]$exitCode }        else { $null }
            $svcSpecificCodeHex = if ($null -ne $svcSpecificCode) { '0x{0:X}' -f [uint32]$svcSpecificCode } else { $null }

            [PSCustomObject]@{
                Name                       = $cim.Name
                DisplayName                = $cim.DisplayName
                State                      = $cim.State
                Status                     = $cim.Status
                StartMode                  = $cim.StartMode
                PathName                   = $cim.PathName
                StartName                  = $cim.StartName
                ProcessId                  = $cim.ProcessId
                ProcessStartTime           = $procStartTime
                Ports                      = (Get-ServiceListeningPorts -ProcessId $cim.ProcessId)
                ExitCode                   = $exitCode
                ExitCodeHex                = $exitCodeHex
                ServiceSpecificExitCode    = $svcSpecificCode
                ServiceSpecificExitCodeHex = $svcSpecificCodeHex
                Dependencies               = $dependencies
                Dependents                 = $dependents
                DependencyTree             = (Get-ServiceDependencyTree -ServiceName $cim.Name)
            }
        }
}
# ------------------------------------------------------------------
# AXM software registry scan
# ------------------------------------------------------------------
function Get-AXMSoftwareInfo {
    [OutputType([PSCustomObject])]
    param()

    $matchPattern  = '(?i)(axm|SimonsVoss)'
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
            } catch {}
        }
    }

    $software |
        Where-Object {
            ($_.DisplayName -and $_.DisplayName -match $matchPattern) -or
            ($_.Publisher   -and $_.Publisher   -match $matchPattern)
        } |
        Sort-Object DisplayName
}

# ------------------------------------------------------------------
# LockSysMgr Main DB config scan
# ------------------------------------------------------------------
function Get-LockSysMgrMainInfo {
    [OutputType([PSCustomObject])]
    param()

    $configRoot = Join-Path $env:ProgramData 'SimonsVoss\LockSysMgr\config'
    if (-not (Test-Path $configRoot)) { return @() }

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
        Where-Object { $_.Extension -in '.xml','.json','.ini','.cfg','.conf','.txt' }
    foreach ($file in $configFiles) {
        $contentMatches = Select-String -Path $file.FullName -Pattern '(?i)main_' -ErrorAction SilentlyContinue
        foreach ($m in $contentMatches) {
            $results += [PSCustomObject]@{
                Path       = $file.FullName
                ObjectType = 'File'
                MatchType  = 'Content'
                Details    = $m.Line.Trim()
            }
        }
    }

    if ($results.Count -eq 0) {
        $results += [PSCustomObject]@{
            Path       = $configRoot
            ObjectType = 'Directory'
            MatchType  = 'ConfigFolderExists'
            Details    = 'Config directory exists but no main_* entries were found.'
        }
    }

    $results
}

# ------------------------------------------------------------------
# LockSysMgr Repository scan
# ------------------------------------------------------------------
function Get-LockSysMgrRepositoryInfo {
    [OutputType([PSCustomObject])]
    param()

    $repoRoot = Join-Path $env:ProgramData 'SimonsVoss'
    if (-not (Test-Path $repoRoot)) { return @() }

    $results  = @()
    $repoDirs = Get-ChildItem -Path $repoRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like 'Repository-*' }

    foreach ($repo in $repoDirs) {
        $repoSizeBytes = (Get-ChildItem -Path $repo.FullName -Recurse -File -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum).Sum
        $repoSizeText  = '{0:N2} MB' -f [math]::Round(($repoSizeBytes / 1MB), 2)

        $subfolders = Get-ChildItem -Path $repo.FullName -Directory -ErrorAction SilentlyContinue
        foreach ($subfolder in $subfolders) {
            $relativeName  = $subfolder.FullName.Substring($repo.FullName.Length + 1)
            $subSizeBytes  = (Get-ChildItem -Path $subfolder.FullName -Recurse -File -ErrorAction SilentlyContinue |
                Measure-Object -Property Length -Sum).Sum
            $subSizeText   = '{0:N2} MB' -f [math]::Round(($subSizeBytes / 1MB), 2)
            $mdfPath       = Join-Path $subfolder.FullName 'lsmax.mdf'
            $logPath       = Join-Path $subfolder.FullName 'lsmax_log.ldf'
            $hasMdf        = Test-Path $mdfPath
            $hasLog        = Test-Path $logPath
            $mdfInfo       = if ($hasMdf) { Get-Item -Path $mdfPath -ErrorAction SilentlyContinue } else { $null }

            $results += [PSCustomObject]@{
                Repository           = $repo.Name
                RepositorySize       = $repoSizeText
                SubfolderName        = $relativeName
                SubfolderSize        = $subSizeText
                FullPath             = $subfolder.FullName
                Status               = if ($hasMdf -and $hasLog) { 'OK' } else { 'Missing' }
                LsmaxMdf             = $hasMdf
                LsmaxMdfName         = if ($mdfInfo) { $mdfInfo.Name }         else { $null }
                LsmaxMdfLength       = if ($mdfInfo) { $mdfInfo.Length }        else { $null }
                LsmaxMdfCreationTime = if ($mdfInfo) { $mdfInfo.CreationTime }  else { $null }
                LsmaxMdfLastWrite    = if ($mdfInfo) { $mdfInfo.LastWriteTime } else { $null }
                LsmaxLogMdf          = $hasLog
            }
        }
    }

    $results
}

# ------------------------------------------------------------------
# LockSysMgr log — license JSON extraction
# ------------------------------------------------------------------
function Get-LockSysMgrLogInfo {
    [OutputType([PSCustomObject])]
    param()

    $logRoot = Join-Path $env:LOCALAPPDATA 'SimonsVoss\LockSysMgr\log'
    if (-not (Test-Path $logRoot)) { return @() }

    $logFile = Get-ChildItem -Path $logRoot -File -Filter 'AXM*' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (-not $logFile) { return @() }

    $lines       = Get-Content -Path $logFile.FullName -ErrorAction SilentlyContinue
    $licenseLine = $lines |
        Where-Object { $_ -match 'Query \{"\$type":"GetLicense"\} done; Response:' } |
        Select-Object -Last 1

    if (-not $licenseLine) {
        return [PSCustomObject]@{
            LogFile      = $logFile.FullName
            FoundLicense = $false
            Error        = 'No GetLicense response found in latest AXM log.'
        }
    }

    $responseIndex = $licenseLine.IndexOf('Response:')
    $jsonText      = if ($responseIndex -ge 0) { $licenseLine.Substring($responseIndex + 9).Trim() } else { $null }

    if (-not $jsonText) {
        return [PSCustomObject]@{
            LogFile      = $logFile.FullName
            FoundLicense = $true
            Error        = 'Response JSON section could not be extracted.'
        }
    }

    if ($jsonText -match '^(.*\})(?:\s*<s:.*)?$') { $jsonText = $Matches[1].Trim() }

    try {
        $licenseData = $jsonText | ConvertFrom-Json -ErrorAction Stop
        $reg         = $licenseData.RegistrationDetails
        $sub         = $licenseData.SubscriptionInfo
        return [PSCustomObject]@{
            LogFile                  = $logFile.FullName
            FoundLicense             = $true
            LicenseType              = $licenseData.Type
            SoftwareEdition          = $licenseData.SoftwareEdition
            StartDate                = $licenseData.StartDate
            ExpirationDate           = $licenseData.ExpirationDate
            CompanyName              = $reg.CompanyName
            City                     = $reg.City
            Country                  = $reg.Country
            Email                    = $reg.Email
            LicenseKey               = $reg.LicenseKey
            CommissionNumber         = $reg.CommissionNumber
            SubscriptionExpiryDate   = $sub.ExpiryDate
            PaymentApproved          = $sub.PaymentApproved
            AreOnlineFeaturesAllowed = $licenseData.AreOnlineFeaturesAllowed
            IsDeactivated            = $licenseData.IsDeactivated
        }
    } catch {
        return [PSCustomObject]@{
            LogFile      = $logFile.FullName
            FoundLicense = $true
            Error        = "Failed to parse license JSON: $($_.Exception.Message)"
            RawResponse  = $jsonText
        }
    }
}

# ------------------------------------------------------------------
# SQL Server instances (from registry)
# ------------------------------------------------------------------
function Get-SQLServerInstanceInfo {
    [OutputType([PSCustomObject])]
    param()

    $instances     = @()
    $registryPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Microsoft SQL Server\Instance Names\SQL'
    )

    foreach ($path in $registryPaths) {
        if (-not (Test-Path $path)) { continue }
        $props = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue
        foreach ($property in $props.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' }) {
            $instanceName = $property.Name
            $instanceId   = $property.Value
            $setupPath    = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$instanceId\Setup"
            if (-not (Test-Path $setupPath)) {
                $setupPath = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Microsoft SQL Server\$instanceId\Setup"
            }

            $setupProps   = if (Test-Path $setupPath) {
                Get-ItemProperty -Path $setupPath -ErrorAction SilentlyContinue
            } else { $null }

            # Handle default instance naming
            $serviceName  = if ($instanceName -ieq 'MSSQLSERVER') { 'MSSQLSERVER' } else { "MSSQL`$$instanceName" }
            $service      = Get-Service -Name $serviceName -ErrorAction SilentlyContinue

            $instances += [PSCustomObject]@{
                InstanceName  = $instanceName
                InstanceType  = 'Database Engine'
                InstanceId    = $instanceId
                Edition       = $setupProps.Edition
                Version       = $setupProps.Version
                ServiceName   = $serviceName
                ServiceStatus = if ($service) { $service.Status } else { 'Not found' }
                RegistryPath  = $path
            }
        }
    }

    $instances
}

# ------------------------------------------------------------------
# SQL LocalDB instances
# ------------------------------------------------------------------
function Get-SQLLocalDBInstanceInfo {
    [OutputType([PSCustomObject])]
    param()

    $instances   = @()
    $localDbCmd  = Get-Command sqllocaldb -ErrorAction SilentlyContinue

    if ($localDbCmd) {
        $instanceNames = & sqllocaldb i 2>$null
        foreach ($name in $instanceNames) {
            $name = $name.Trim()
            if ([string]::IsNullOrWhiteSpace($name)) { continue }

            $infoLines = & sqllocaldb i $name 2>$null
            $info      = @{}
            foreach ($line in $infoLines) {
                if ($line -match '^(?<k>[^:]+)\s*:\s*(?<v>.+)$') {
                    $info[$Matches['k'].Trim()] = $Matches['v'].Trim()
                }
            }

            $instances += [PSCustomObject]@{
                InstanceName  = $name
                InstanceType  = 'LocalDB'
                Edition       = $info['Edition']
                Version       = $info['Version']
                State         = $info['State']
                LastStartTime = $info['Last start time']
                CreationTime  = $info['Creation time']
                RegistryPath  = 'sqllocaldb'
            }
        }
    } else {
        $localDbReg = 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server Local DB\Installed Versions'
        if (Test-Path $localDbReg) {
            Get-ChildItem -Path $localDbReg -ErrorAction SilentlyContinue | ForEach-Object {
                $props = Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue
                $instances += [PSCustomObject]@{
                    InstanceName  = $_.PSChildName
                    InstanceType  = 'LocalDB Version'
                    Edition       = $null
                    Version       = $props.Version
                    State         = 'Installed'
                    LastStartTime = $null
                    CreationTime  = $null
                    RegistryPath  = $_.PSPath
                }
            }
        }
    }

    $instances
}

# ------------------------------------------------------------------
# Combined SQL info
# ------------------------------------------------------------------
function Get-SQLInstanceInfo {
    [OutputType([PSCustomObject])]
    param()
    $instances  = @()
    $instances += Get-SQLServerInstanceInfo
    $instances += Get-SQLLocalDBInstanceInfo
    $instances
}
# ------------------------------------------------------------------
# Usage helper
# ------------------------------------------------------------------
function Show-Usage {
    Write-Host ""
    Write-Host "Usage: .\AXM_info.ps1 [-Services] [-Software] [-SQL] [-MainDB] [-Repository] [-Log] [-All] [-Dump] [-NonInteractive]" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  -Services        Scan AXM/SimonsVoss Windows services" -ForegroundColor Yellow
    Write-Host "  -Software        Scan installed AXM/SimonsVoss software" -ForegroundColor Yellow
    Write-Host "  -SQL             Scan SQL Server and LocalDB instances" -ForegroundColor Yellow
    Write-Host "  -MainDB          Scan LockSysMgr main DB config folder" -ForegroundColor Yellow
    Write-Host "  -Repository      Scan LockSysMgr repository folders" -ForegroundColor Yellow
    Write-Host "  -Log             Parse latest AXM log for license info" -ForegroundColor Yellow
    Write-Host "  -All             Run all checks" -ForegroundColor Yellow
    Write-Host "  -Dump            Save report to file (next to script)" -ForegroundColor Yellow
    Write-Host "  -OutFile         Output filename (default: COMPUTERNAME - AXM-info.txt)" -ForegroundColor Yellow
    Write-Host "  -NonInteractive  Skip all Read-Host prompts" -ForegroundColor Yellow
    Write-Host ""
}

# ------------------------------------------------------------------
# Interactive selection (skipped if -NonInteractive or any switch set)
# ------------------------------------------------------------------
$noArgs = -not ($Services -or $Software -or $SQL -or $MainDB -or $Repository -or $Log -or $All)

if ($noArgs -and -not $NonInteractive) {
    try {
        $runAllAnswer = Read-Host "No checks selected. Run all checks? (Y/N) [Y]"
        if ($runAllAnswer -and $runAllAnswer -match '^(?i:n|no)$') {

            $svcAns  = Read-Host "Run Services check? (Y/N) [Y]"
            $Services = -not ($svcAns -and $svcAns -match '^(?i:n|no)$')

            $softAns  = Read-Host "Run Software scan? (Y/N) [Y]"
            $Software = -not ($softAns -and $softAns -match '^(?i:n|no)$')

            $sqlAns   = Read-Host "Run SQL instance scan? (Y/N) [Y]"
            $SQL      = -not ($sqlAns -and $sqlAns -match '^(?i:n|no)$')

            $mainAns  = Read-Host "Run Main DB config scan? (Y/N) [Y]"
            $MainDB   = -not ($mainAns -and $mainAns -match '^(?i:n|no)$')

            $repoAns  = Read-Host "Run Repository scan? (Y/N) [Y]"
            $Repository = -not ($repoAns -and $repoAns -match '^(?i:n|no)$')

            $logAns   = Read-Host "Run AXM log lookup? (Y/N) [Y]"
            $Log      = -not ($logAns -and $logAns -match '^(?i:n|no)$')

        } else {
            $Services   = $true
            $Software   = $true
            $SQL        = $true
            $MainDB     = $true
            $Repository = $true
            $Log        = $true
        }
    } catch {
        # Non-interactive host — enable all checks
        $Services   = $true
        $Software   = $true
        $SQL        = $true
        $MainDB     = $true
        $Repository = $true
        $Log        = $true
    }
}

if ($All) {
    $Services   = $true
    $Software   = $true
    $SQL        = $true
    $MainDB     = $true
    $Repository = $true
    $Log        = $true
}

# ------------------------------------------------------------------
# Prompt for Dump if not already set
# ------------------------------------------------------------------
if (-not $Dump -and -not $NonInteractive) {
    try {
        $dumpAns = Read-Host "Save report to file? (Y/N) [N]"
        if ($dumpAns -and $dumpAns -match '^(?i:y|yes)$') {
            $Dump = $true
            $customOut = Read-Host "Output filename (Enter for default: $OutFile)"
            if ($customOut) { $OutFile = $customOut }
        }
    } catch {}
}

# ------------------------------------------------------------------
# Validate at least one check is selected
# ------------------------------------------------------------------
if (-not ($Services -or $Software -or $SQL -or $MainDB -or $Repository -or $Log)) {
    Show-Usage
    exit 1
}

# ------------------------------------------------------------------
# Start transcript if Dump requested
# ------------------------------------------------------------------
$transcribing = $false
$outfileFull  = $null

if ($Dump) {
    $outfileFull = Get-AbsoluteOutFile -Out $OutFile
    if (-not $outfileFull) {
        Write-Warning "Dump requested but OutFile could not be resolved. Skipping transcript."
    } else {
        try {
            Write-Host "Report will be saved to: $outfileFull" -ForegroundColor Cyan
            Start-Transcript -Path $outfileFull -Force -ErrorAction Stop
            $transcribing = $true
            Write-Host "=== AXM Info Report ===" -ForegroundColor White
            Write-Host "Computer  : $env:COMPUTERNAME"
            Write-Host "Timestamp : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
            Write-Host "User      : $env:USERDOMAIN\$env:USERNAME"
            Write-Host ""
        } catch {
            Write-Warning "Failed to start transcript: $($_.Exception.Message)"
        }
    }
}

# ------------------------------------------------------------------
# Run checks
# ------------------------------------------------------------------
if ($Log) {
    Write-Host "`n=== AXM License (from AppData log) ===" -ForegroundColor Cyan
    $logResults = Get-LockSysMgrLogInfo
    if ($logResults) {
        $logResults | Write-Detail
    } else {
        Write-Host "No AXM log information found." -ForegroundColor Yellow
    }
}

if ($Software) {
    Write-Host "`n=== Installed AXM Software ===" -ForegroundColor Cyan
    $softwareResults = Get-AXMSoftwareInfo
    if ($softwareResults) {
        $softwareResults | Write-Table -Properties DisplayName, DisplayVersion, Publisher, InstallDate, InstallLocation
    } else {
        Write-Host "No AXM-related software found." -ForegroundColor Yellow
    }
}

if ($Services) {
    Write-Host "`n=== AXM Services (Summary) ===" -ForegroundColor Cyan
    $serviceResults = Get-AXMServiceInfo
    if ($serviceResults) {
        # Summary table
        $serviceResults | Write-Table -Properties Name, DisplayName, State, StartMode, ProcessId, ProcessStartTime, Ports, ExitCode, ExitCodeHex, ServiceSpecificExitCode

        # Detail block per service (dependencies, dependents, full path, tree)
        Write-Host "`n=== AXM Services (Detail) ===" -ForegroundColor Cyan
        foreach ($svc in $serviceResults) {
            Write-Host ""
            Write-Host "--- $($svc.DisplayName) ---" -ForegroundColor White
            Write-Host "  Name              : $($svc.Name)"
            Write-Host "  State             : $($svc.State)"
            Write-Host "  Status            : $($svc.Status)"
            Write-Host "  StartMode         : $($svc.StartMode)"
            Write-Host "  PathName          : $($svc.PathName)"
            Write-Host "  StartName         : $($svc.StartName)"
            Write-Host "  ProcessId         : $($svc.ProcessId)"
            Write-Host "  ProcessStartTime  : $($svc.ProcessStartTime)"
            Write-Host "  Ports             : $($svc.Ports)"
            Write-Host "  ExitCode          : $($svc.ExitCode) ($($svc.ExitCodeHex))"
            Write-Host "  SvcSpecificCode   : $($svc.ServiceSpecificExitCode) ($($svc.ServiceSpecificExitCodeHex))"
            Write-Host "  Dependencies      : $($svc.Dependencies)"
            Write-Host "  Dependents        : $($svc.Dependents)"
            Write-Host "  Dependency Tree   :"
            if ($svc.DependencyTree) {
                $svc.DependencyTree -split "`n" | ForEach-Object { Write-Host "    $_" }
            }
        }
    } else {
        Write-Host "No AXM services found." -ForegroundColor Yellow
    }
}

if ($Repository) {
    Write-Host "`n=== LockSysMgr Repositories ===" -ForegroundColor Cyan
    $repoResults = Get-LockSysMgrRepositoryInfo
    if ($repoResults) {
        $repoResults | Write-Table -Properties Repository, RepositorySize, SubfolderName, SubfolderSize, Status, LsmaxMdf, LsmaxLogMdf, LsmaxMdfLength, LsmaxMdfLastWrite
    } else {
        Write-Host "No Repository-* folders found under ProgramData\SimonsVoss." -ForegroundColor Yellow
    }
}

if ($MainDB) {
    Write-Host "`n=== LockSysMgr Main DB Config ===" -ForegroundColor Cyan
    $mainResults = Get-LockSysMgrMainInfo
    if ($mainResults) {
        $mainResults | Write-Table -Properties Path, ObjectType, MatchType, Details
    } else {
        Write-Host "No main DB config entries found." -ForegroundColor Yellow
    }
}

if ($SQL) {
    Write-Host "`n=== SQL Server / LocalDB Instances ===" -ForegroundColor Cyan
    $sqlResults = Get-SQLInstanceInfo
    if ($sqlResults) {
        $sqlResults | Write-Table -Properties InstanceName, InstanceType, Edition, Version, ServiceName, ServiceStatus
    } else {
        Write-Host "No SQL Server or LocalDB instances detected." -ForegroundColor Yellow
    }
}

# ------------------------------------------------------------------
# Stop transcript
# ------------------------------------------------------------------
if ($transcribing) {
    try {
        Stop-Transcript -ErrorAction Stop | Out-Null
        Write-Host "`nReport saved to: $outfileFull" -ForegroundColor Green
    } catch {
        Write-Warning "Failed to stop transcript: $($_.Exception.Message)"
    }
}

Write-Host ""
Write-Host "Done." -ForegroundColor Green