<#
.SYNOPSIS
    Creates and seats AXM service user across all AXM services

.DESCRIPTION
    Creates a local service account named svcaxm_usr and configures it to run all
    services matching the "axm*" wildcard. Generates a random password and saves
    it to a file named [hostname]-password.txt in the script folder.

    Uses CIM first to set service credentials and falls back to sc.exe if needed.
    Stops services before reconfiguration, restarts them afterwards, and validates
    the final result.

.AUTHOR
    Thomas Krogager Rasmusen
    SimonsVoss

.VERSION
    1.0.6

.NOTES
    Requires administrator privileges to execute.
#>

#Requires -RunAsAdministrator

$accountName = "svcaxm_usr"
$fullName = "Service AXM User"
$description = "Service account for AXM services"

Write-Host "Starting AXM service user setup..." -ForegroundColor Cyan

function Get-CimErrorDescription {
    param([int]$ReturnCode)

    $errorMap = @{
        0  = 'Success'
        1  = 'Not Supported'
        2  = 'Access Denied'
        3  = 'Dependent Services Running'
        4  = 'Invalid Service Control'
        5  = 'Service Cannot Accept Control'
        6  = 'Service Not Active'
        7  = 'Service Request Timeout'
        8  = 'Unknown Failure'
        9  = 'Path Not Found'
        10 = 'Service Already Running'
        11 = 'Service Database Locked'
        12 = 'Service Dependency Deleted'
        13 = 'Service Dependency Failed'
        14 = 'Service Disabled'
        15 = 'Service Logon Failed'
        16 = 'Service Marked for Deletion'
        17 = 'Service No Thread'
        18 = 'Status Circular Dependency'
        19 = 'Status Duplicate Name'
        20 = 'Status Invalid Name'
        21 = 'Status Invalid Parameter'
        22 = 'Status Invalid Service Account'
        23 = 'Status Service Exists'
        24 = 'Status Shutdown in Progress'
    }

    return $errorMap[$ReturnCode] -or "Unknown error code $ReturnCode"
}

# PowerShell
function Set-ServiceAccount {
    param(
        [Parameter(Mandatory = $true)][string]$ServiceName,
        [Parameter(Mandatory = $true)][string]$AccountName,
        [Parameter(Mandatory = $true)][string]$Password
    )

    # Prøv begge konto-formater i denne rækkefølge: lokal form først, så maskin\brugernavn
    $attempts = @(".\$AccountName", "$env:COMPUTERNAME\$AccountName")

    foreach ($serviceAccount in $attempts) {
        Write-Host "Prøver CIM Change med StartName='$serviceAccount' for service '$ServiceName'" -ForegroundColor Cyan

        try {
            $svc = Get-CimInstance -ClassName Win32_Service -Filter "Name='$ServiceName'" -ErrorAction Stop
            $changeResult = Invoke-CimMethod -InputObject $svc -MethodName Change -Arguments @{
                StartName     = $serviceAccount
                StartPassword = $Password
            } -ErrorAction Stop

            if ($changeResult -ne $null) {
                Write-Host "CIM: Change() ReturnValue = $($changeResult.ReturnValue) ($(Get-CimErrorDescription $changeResult.ReturnValue))" -ForegroundColor Yellow
            }

        } catch {
            Write-Host "CIM: Invoke-CimMethod-fejl for $ServiceName med $serviceAccount : $_" -ForegroundColor Yellow
        }

        # Re-query
        $svcRef = Get-CimInstance -ClassName Win32_Service -Filter "Name='$ServiceName'" -ErrorAction SilentlyContinue
        if ($svcRef -and $svcRef.StartName -ieq $serviceAccount) {
            Write-Host "Bekræftet StartName='$($svcRef.StartName)'" -ForegroundColor Green
            return $true
        } else {
            Write-Host "CIM satte ikke StartName til '$serviceAccount' (er: '$($svcRef.StartName)')" -ForegroundColor Yellow
        }
    }

    # CIM lykkedes ikke til at bekræfte konto/pass; fallback til sc.exe (samme ordre)
    foreach ($serviceAccount in $attempts) {
        Write-Host "Prøver sc.exe config med obj= $serviceAccount for $ServiceName" -ForegroundColor Cyan
        $scArgs = @('config', $ServiceName, "obj= $serviceAccount", "password= $Password")
        $scOutput = & sc.exe @scArgs 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "sc.exe returnerede success for $serviceAccount" -ForegroundColor Green
        } else {
            Write-Host "sc.exe fejlede for $serviceAccount : $scOutput" -ForegroundColor Red
        }

        $svcRef2 = Get-CimInstance -ClassName Win32_Service -Filter "Name='$ServiceName'" -ErrorAction SilentlyContinue
        if ($svcRef2 -and $svcRef2.StartName -ieq $serviceAccount) {
            Write-Host "Bekræftet via sc.exe at StartName = '$($svcRef2.StartName)'" -ForegroundColor Green
            return $true
        } else {
            Write-Host "sc.exe ændrede ikke StartName til '$serviceAccount' (er: '$($svcRef2.StartName)')" -ForegroundColor Yellow
        }
    }

    Write-Host "Kunne ikke sætte konto for $ServiceName med hverken CIM eller sc.exe" -ForegroundColor Red
    return $false
}

function Validate-AXMServices {
    param(
        [Parameter(Mandatory = $true)][array]$Services,
        [Parameter(Mandatory = $true)][string]$ExpectedAccount
    )

    $validatedCount = 0

    foreach ($service in $Services) {
        $svc = Get-CimInstance -ClassName Win32_Service -Filter "Name='$($service.Name)'" -ErrorAction SilentlyContinue
        if (-not $svc) {
            Write-Host "Validation: Service '$($service.Name)' not found." -ForegroundColor Red
            continue
        }

        $expectedAccounts = @(
            "$env:COMPUTERNAME\$ExpectedAccount"
            ".\$ExpectedAccount"
            $ExpectedAccount
        )

        $accountMatches = $expectedAccounts -contains $svc.StartName
        $statusOk = $svc.State -eq 'Running'

        if ($statusOk -and $accountMatches) {
            $color = 'Green'
            $validatedCount++
        } elseif ($statusOk) {
            $color = 'Yellow'
        } else {
            $color = 'Red'
        }

        Write-Host "Validation: $($svc.Name) => State=$($svc.State), StartName=$($svc.StartName)" -ForegroundColor $color
    }

    Write-Host ""
    Write-Host "Validated $validatedCount of $($Services.Count) configured services." -ForegroundColor Cyan
    return ($validatedCount -eq $Services.Count)
}

function Start-ServiceWithDependencies {
    param(
        [Parameter(Mandatory = $true)][string]$ServiceName,
        [Parameter(Mandatory = $true)][hashtable]$StartedServices
    )

    if ($StartedServices.ContainsKey($ServiceName)) {
        return
    }

    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if (-not $svc) {
        Write-Host "Service $ServiceName not found." -ForegroundColor Red
        $StartedServices[$ServiceName] = $false
        return
    }

    foreach ($dep in $svc.ServicesDependedOn) {
        if (-not $StartedServices.ContainsKey($dep.Name)) {
            Start-ServiceWithDependencies -ServiceName $dep.Name -StartedServices $StartedServices
            Start-Sleep -Seconds 2
        }
    }

    try {
        if ($svc.Status -ne 'Running') {
            Write-Host "Attempting to start: $ServiceName" -ForegroundColor Yellow
            Start-Service -Name $ServiceName -ErrorAction Stop
            Start-Sleep -Seconds 2

            $svcStatus = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
            if ($svcStatus -and $svcStatus.Status -eq 'Running') {
                Write-Host "Started service: $ServiceName" -ForegroundColor Green
                $StartedServices[$ServiceName] = $true
            } else {
                Write-Host "Service $ServiceName did not stay running. Status: $($svcStatus.Status)" -ForegroundColor Red
                $StartedServices[$ServiceName] = $false
            }
        } else {
            Write-Host "Service already running: $ServiceName" -ForegroundColor Cyan
            $StartedServices[$ServiceName] = $true
        }
    } catch {
        Write-Host "Error starting service $ServiceName : $_" -ForegroundColor Red
        $StartedServices[$ServiceName] = $false
    }
}

# Generate random password
$passwordLength = 32
$characters = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
$password = -join ((1..$passwordLength) | ForEach-Object { Get-Random -InputObject $characters.ToCharArray() })
$pw = ConvertTo-SecureString $password -AsPlainText -Force

# Create or reset local service user
try {
    $localUser = Get-LocalUser -Name $accountName -ErrorAction Stop
    $localUserExists = $true
    Write-Host "Local user '$accountName' exists. Resetting password..." -ForegroundColor Yellow
} catch {
    $localUserExists = $false
    Write-Host "Local user '$accountName' does not exist. Creating..." -ForegroundColor Yellow
}

try {
    if ($localUserExists) {
        Set-LocalUser -Name $accountName -Password $pw -ErrorAction Stop
        Write-Host "Password reset for '$accountName'." -ForegroundColor Green
    } else {
        New-LocalUser -Name $accountName -Password $pw -FullName $fullName -Description $description -ErrorAction Stop
        Write-Host "User '$accountName' created." -ForegroundColor Green
    }

    Set-LocalUser -Name $accountName -PasswordNeverExpires $true -ErrorAction Stop
    Write-Host "Set password to never expire for '$accountName'." -ForegroundColor Green
} catch {
    Write-Host "Error creating/updating local user: $_" -ForegroundColor Red
    throw
}

# Add user to Administrators (localized group by SID)
try {
    $adminGroup = Get-LocalGroup | Where-Object { $_.SID.Value -eq 'S-1-5-32-544' }
    if (-not $adminGroup) { throw "Administrators group not found by SID." }
    Add-LocalGroupMember -Group $adminGroup.Name -Member $accountName -ErrorAction Stop
    Write-Host "Added '$accountName' to '$($adminGroup.Name)' group." -ForegroundColor Green
} catch {
    Write-Host "Add-LocalGroupMember warning: $_" -ForegroundColor Yellow
}
# Grant "Log On As A Service" (SeServiceLogonRight) using secedit export/modify/import
Write-Host "Granting 'Log On As A Service' right to '$accountName'..." -ForegroundColor Cyan
try {
    $tempFile = [System.IO.Path]::GetTempFileName()
    $accountSID = (Get-LocalUser -Name $accountName -ErrorAction Stop).SID.Value

    & secedit.exe /export /cfg $tempFile /quiet 2>&1 | Out-Null

    $content = Get-Content -Path $tempFile -ErrorAction Stop

    # Find index of SeServiceLogonRight line
    $idx = -1
    for ($i = 0; $i -lt $content.Count; $i++) {
        if ($content[$i] -match '^\s*SeServiceLogonRight\s*=') {
            $idx = $i
            break
        }
    }

    if ($idx -ge 0) {
        $line = $content[$idx]
        $parts = $line -split '='
        $existing = @()
        if ($parts.Count -gt 1) {
            $existing = ($parts[1] -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
        }
        if ($existing -notcontains $accountSID) {
            $existing += $accountSID
        }
        $content[$idx] = 'SeServiceLogonRight = ' + ($existing -join ',')
    } else {
        $content += "SeServiceLogonRight = $accountSID"
    }

    $content | Set-Content -Path $tempFile -Force

    & secedit.exe /configure /db secedit.sdb /cfg $tempFile /quiet 2>&1 | Out-Null

    Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue
    Write-Host "Granted 'Log On As A Service' privilege." -ForegroundColor Green
} catch {
    Write-Host "Warning: Could not grant 'Log On As A Service' privilege: $_" -ForegroundColor Yellow
}
Write-Host "`nSeating user '$accountName' to AXM services only (excluding VnHostSrv and CommNodeSrv)..." -ForegroundColor Cyan

# Discover AXM services that WILL be configured
$axmServices = @(Get-Service -Name "axm*" -ErrorAction SilentlyContinue) | Sort-Object -Property Name -Unique

# Services to exclude from account seating, but still include in stop/restart
$excludeForSeating = @('VnHostSrv', 'CommNodeSrv')

# Final list of services to configure
$configTargets = $axmServices | Where-Object {
    $_.Name -notin $excludeForSeating -and
    $_.DisplayName -notin $excludeForSeating
}

Write-Host "Services to configure: $($configTargets.Name -join ', ')" -ForegroundColor Cyan
Write-Host "Excluded from seating, but still handled for restart if present: $($excludeForSeating -join ', ')" -ForegroundColor Cyan

if ($configTargets.Count -eq 0) {
    Write-Host "No AXM services found to configure." -ForegroundColor Yellow
} else {
    # Build list of services to stop/restart:
    # - configured AXM services
    # - their dependent services
    # - excluded services (VnHostSrv / CommNodeSrv) if present
    # - dependents of excluded services
    $servicesToStop = @()

    foreach ($s in $configTargets) {
        $servicesToStop += $s
        if ($s.DependentServices) {
            $servicesToStop += $s.DependentServices
        }
    }

    foreach ($name in $excludeForSeating) {
        $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
        if ($svc) {
            $servicesToStop += $svc
            if ($svc.DependentServices) {
                $servicesToStop += $svc.DependentServices
            }
        }
    }

    $servicesToStop = $servicesToStop | Sort-Object -Property Name -Unique

    Write-Host "Services that will be stopped/restarted: $($servicesToStop.Name -join ', ')" -ForegroundColor Cyan

    Write-Host "`nStopping all targeted services and dependents..." -ForegroundColor Yellow
    foreach ($svc in $servicesToStop) {
        try {
            if ($svc.Status -eq 'Running') {
                Stop-Service -Name $svc.Name -Force -ErrorAction Stop
                Write-Host "Stopped: $($svc.Name)" -ForegroundColor Yellow
            } else {
                Write-Host "Not running: $($svc.Name)" -ForegroundColor Cyan
            }
        } catch {
            Write-Host "Warning: Could not stop $($svc.Name): $_" -ForegroundColor Yellow
        }
    }

    Start-Sleep -Seconds 2

    # Seat the user to each AXM service only
    $successCount = 0
    foreach ($svc in $configTargets) {
        Write-Host "`nConfiguring $($svc.Name) ..." -ForegroundColor Cyan
        $ok = $false
        try {
            $ok = Set-ServiceAccount -ServiceName $svc.Name -AccountName $accountName -Password $password
            if ($ok) {
                Write-Host "Seated $($svc.Name) -> $accountName" -ForegroundColor Green
                $successCount++
            } else {
                Write-Host "Failed to seat $($svc.Name)" -ForegroundColor Red
            }
        } catch {
            Write-Host "Error seating $($svc.Name): $_" -ForegroundColor Red
        }

        # Optional: grant filesystem and registry permissions to service binary and HKLM key
        try {
            $svcDetails = Get-CimInstance -ClassName Win32_Service -Filter "Name='$($svc.Name)'" -ErrorAction SilentlyContinue
            if ($svcDetails -and $svcDetails.PathName) {
                $binaryPath = $svcDetails.PathName -replace '^"([^"]+)".*', '$1'
                $binaryDir = Split-Path -Parent $binaryPath

                if (Test-Path $binaryDir) {
                    try {
                        $acl = Get-Acl -Path $binaryDir
                        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                            "$env:COMPUTERNAME\$accountName",
                            "Modify",
                            "ContainerInherit, ObjectInherit",
                            "None",
                            "Allow"
                        )
                        $acl.SetAccessRule($rule)
                        Set-Acl -Path $binaryDir -AclObject $acl
                        Write-Host "Granted Modify on: $binaryDir" -ForegroundColor Green
                    } catch {
                        Write-Host ("Warning: Could not set filesystem ACL on {0}: {1}" -f $binaryDir, $_) -ForegroundColor Yellow
                    }
                }

                $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$($svc.Name)"
                if (Test-Path $regPath) {
                    try {
                        $regAcl = Get-Acl -Path $regPath
                        $regRule = New-Object System.Security.AccessControl.RegistryAccessRule(
                            "$env:COMPUTERNAME\$accountName",
                            "FullControl",
                            "ContainerInherit, ObjectInherit",
                            "None",
                            "Allow"
                        )
                        $regAcl.SetAccessRule($regRule)
                        Set-Acl -Path $regPath -AclObject $regAcl
                        Write-Host "Granted registry FullControl for: $($svc.Name)" -ForegroundColor Green
                    } catch {
                        Write-Host "Warning: Could not set registry ACL for $($svc.Name): $_" -ForegroundColor Yellow
                    }
                }
            }
        } catch {
            Write-Host "Permission assignment warning for $($svc.Name): $_" -ForegroundColor Yellow
        }

        Start-Sleep -Seconds 1
    }

    Write-Host "`nConfigured $successCount of $($configTargets.Count) services." -ForegroundColor Cyan
    if ($successCount -gt 0) {
        Write-Host "Waiting for service account configuration to settle..." -ForegroundColor Cyan
        Start-Sleep -Seconds 3
    }
}


if ($servicesToStop -and $servicesToStop.Count -gt 0) {
    Write-Host "`nStarting all configured services in dependency order..." -ForegroundColor Cyan
    Write-Host "Waiting 15 seconds before starting to allow system to stabilize..." -ForegroundColor Yellow
    Start-Sleep -Seconds 15

    $startedServices = @{}
    $servicesToRestart = $servicesToStop | Sort-Object -Property Name -Unique

    foreach ($s in $servicesToRestart) {
        Start-ServiceWithDependencies -ServiceName $s.Name -StartedServices $startedServices
        Start-Sleep -Seconds 3
    }

    $restartCount = ($startedServices.Values | Where-Object { $_ -eq $true }).Count
    Write-Host "`nSuccessfully started $restartCount of $($servicesToRestart.Count) touched services." -ForegroundColor Cyan

    # Validate configured services
    Write-Host "`nValidating configured AXM services..." -ForegroundColor Cyan
    $validationSuccess = Validate-AXMServices -Services $configTargets -ExpectedAccount $accountName
    if (-not $validationSuccess) {
        Write-Host "One or more AXM services did not validate successfully. Review StartName and service state above, and check the System event log for logon failures (e.g., EventID 1069)." -ForegroundColor Yellow
    } else {
        Write-Host "All configured services validated successfully." -ForegroundColor Green
    }
} else {
    Write-Host "No services were configured; nothing to start." -ForegroundColor Yellow
}

Write-Host "`nService user seating complete!" -ForegroundColor Green
Read-Host -Prompt 'Press Enter to exit'