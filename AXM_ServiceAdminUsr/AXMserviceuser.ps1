<#
.SYNOPSIS
    Creates and seats AXM service user across all AXM services

.DESCRIPTION
    Creates a local service account named svcaxm_usr and configures it to run all
    services matching the "axm*" wildcard. Generates a random password and saves
    it to a file named [hostname]-password.txt in the script folder.

.AUTHOR
    Thomas Krogager Rasmusen
    SimonsVoss

.VERSION
    1.0.5

.NOTES
    Requires administrator privileges to execute.
#>

# Requires administrator privileges
#Requires -RunAsAdministrator

$accountName = "svcaxm_usr"
$fullName = "Service AXM User"
$description = "Service account for AXM services"

Write-Host "Starting AXM service user setup..." -ForegroundColor Cyan

# Function to map WMI error codes to descriptions
function Get-CimErrorDescription {
    param([int]$ReturnCode)
    
    $errorMap = @{
        0 = 'Success'
        1 = 'Not Supported'
        2 = 'Access Denied'
        3 = 'Dependent Services Running'
        4 = 'Invalid Service Control'
        5 = 'Service Cannot Accept Control'
        6 = 'Service Not Active'
        7 = 'Service Request Timeout'
        8 = 'Unknown Failure'
        9 = 'Path Not Found'
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

# Generate random password
$passwordLength = 32
# Use only safe characters that won't cause parsing issues in service configuration
$characters = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
$password = -join ((1..$passwordLength) | ForEach-Object { Get-Random -InputObject $characters.ToCharArray() })
$pw = ConvertTo-SecureString $password -AsPlainText -Force

# Save password to file with hostname
$hostname = $env:COMPUTERNAME
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$passwordFile = Join-Path $scriptPath "${hostname}-password.txt"
try {
    $password | Out-File -FilePath $passwordFile -Encoding UTF8 -Force
    Write-Host "Password saved to: $passwordFile" -ForegroundColor Green
} catch {
    Write-Host "Error saving password file: $_" -ForegroundColor Red
    exit 1
}

# Get or create the service user
$localUserExists = $false
try {
    Get-LocalUser -Name $accountName -ErrorAction Stop | Out-Null
    $localUserExists = $true
    Write-Host "Service user '$accountName' already exists." -ForegroundColor Green
} catch {
    Write-Host "Creating new service user '$accountName'..." -ForegroundColor Yellow
}

try {
    if ($localUserExists) {
        Set-LocalUser -Name $accountName -Password $pw -ErrorAction Stop
        Write-Host "Password for existing user '$accountName' was reset." -ForegroundColor Green
    } else {
        New-LocalUser -Name $accountName -Password $pw -FullName $fullName -Description $description -ErrorAction Stop
        Write-Host "Service user created successfully." -ForegroundColor Green
    }
    
    # Set password to never expire
    Set-LocalUser -Name $accountName -PasswordNeverExpires $true -ErrorAction Stop
    Write-Host "Set password to never expire." -ForegroundColor Green
    
} catch {
    Write-Host "Error creating or updating service user: $_" -ForegroundColor Red
    exit 1
}

# Assign admin rights using localized Administrators group
try {
    $adminGroup = Get-LocalGroup | Where-Object { $_.SID.Value -eq 'S-1-5-32-544' }
    if (-not $adminGroup) {
        throw "Administrators group not found by SID."
    }
    Add-LocalGroupMember -Group $adminGroup.Name -Member $accountName -ErrorAction Stop
    Write-Host "Added '$accountName' to '$($adminGroup.Name)' group." -ForegroundColor Green
} catch {
    Write-Host "User already in Administrators group or admin assignment issue: $_" -ForegroundColor Yellow
}

# Grant "Log On As A Service" right to the service account
Write-Host "`nGranting 'Log On As A Service' privilege to '$accountName'..." -ForegroundColor Cyan
try {
    $tempFile = [System.IO.Path]::GetTempFileName()
    $accountSID = (Get-LocalUser -Name $accountName).SID.Value
    
    # Export current security policy
    & secedit.exe /export /cfg $tempFile /quiet 2>&1 | Out-Null
    
    # Add the Log On As A Service privilege
    $content = Get-Content $tempFile
    if ($content -match 'SeServiceLogonRight') {
        $content = $content -replace 'SeServiceLogonRight = (.*)', "SeServiceLogonRight = `$1,$accountSID"
    } else {
        $content += "`nSeServiceLogonRight = $accountSID"
    }
    $content | Set-Content $tempFile
    
    # Apply the updated security policy
    & secedit.exe /configure /db secedit.sdb /cfg $tempFile /quiet 2>&1 | Out-Null
    
    Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
    Write-Host "Granted 'Log On As A Service' privilege." -ForegroundColor Green
} catch {
    Write-Host "Warning: Could not grant 'Log On As A Service' privilege: $_" -ForegroundColor Yellow
}

# Seat the user across all AXM services
Write-Host "`nSeating user '$accountName' to all AXM services..." -ForegroundColor Cyan

# Find all services matching axm* wildcard
$axmServices = @()
try {
    $axmServices = @(Get-Service -Name "axm*" -ErrorAction SilentlyContinue)
} catch {
    $axmServices = @()
}

if ($axmServices.Count -eq 0) {
    Write-Host "No AXM services found matching pattern 'axm*'." -ForegroundColor Yellow
} else {
    # Stop all services first (including dependent services)
    Write-Host "`nStopping all AXM services and their dependents before reconfiguration..." -ForegroundColor Yellow
    $servicesToStop = @()
    
    # Gather all services and their dependents
    foreach ($service in $axmServices) {
        $servicesToStop += $service
        # Get dependent services
        $dependents = Get-Service | Where-Object { $_.DependentServices -contains $service }
        if ($dependents) {
            $servicesToStop += $dependents
        }
    }
    
    # Remove duplicates
    $servicesToStop = $servicesToStop | Sort-Object -Property Name -Unique
    
    # Stop all services
    foreach ($service in $servicesToStop) {
        try {
            if ($service.Status -eq 'Running') {
                Stop-Service -Name $service.Name -Force -ErrorAction Stop
                Write-Host "Stopped service: $($service.Name)" -ForegroundColor Yellow
            }
        } catch {
            Write-Host "Warning: Could not stop service $($service.Name): $_" -ForegroundColor Yellow
        }
    }
    
    # Add a small delay to ensure services are stopped
    Start-Sleep -Seconds 2
    
    # Seat the user to all AXM services only
    $successCount = 0
    foreach ($service in $axmServices) {
        try {
            $serviceName = $service.Name
            $scUser = ".\$accountName"
            
            Write-Host "Configuring service account for: $serviceName" -ForegroundColor Yellow
            Write-Host "Resolved service account: $scUser" -ForegroundColor Cyan
            
            # Get service details before configuration
            $serviceDetails = Get-CimInstance -ClassName Win32_Service -Filter "Name='$serviceName'"
            if ($serviceDetails) {
                $binaryPath = $serviceDetails.PathName
                Write-Host "Service binary: $binaryPath" -ForegroundColor Cyan
            }
            
            # Try to set the service account with CIM/WMI first
            Write-Host "Attempting service account change via CIM for: $serviceName" -ForegroundColor Yellow
            $changeResult = $null
            try {
                $changeResult = $serviceDetails | Invoke-CimMethod -MethodName Change -Arguments @{ StartName = $scUser; StartPassword = $password }
            } catch {
                Write-Host "CIM service change threw an error: $_" -ForegroundColor Yellow
            }
            
            if ($changeResult -and $changeResult.ReturnValue -eq 0) {
                Write-Host "Successfully seated '$accountName' to service: $serviceName via CIM" -ForegroundColor Green
            } else {
                if ($changeResult) {
                    Write-Host "CIM seating failed with ReturnValue=$($changeResult.ReturnValue) for service: $serviceName" -ForegroundColor Yellow
                }
                Write-Host "Falling back to sc.exe configuration." -ForegroundColor Yellow
                
                $scArgs = @(
                    'config',
                    $serviceName,
                    "obj= $scUser",
                    "password= $password"
                )
                Write-Host "sc.exe args: $($scArgs -join ' | ')" -ForegroundColor Cyan
                $scOutput = & sc.exe @scArgs 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "Successfully seated '$accountName' to service: $serviceName via sc.exe" -ForegroundColor Green
                } else {
                    throw "sc.exe seating failed: $scOutput"
                }
            }
            
            # Grant permissions to service binary directory
            if ($serviceDetails -and $serviceDetails.PathName) {
                try {
                    $binaryPath = $serviceDetails.PathName -replace '^"([^"]+)".*', '$1' # Extract path from quotes
                    $binaryDir = Split-Path -Parent $binaryPath
                    
                    if (Test-Path $binaryDir) {
                        # Grant Modify permissions to the service account
                        $acl = Get-Acl $binaryDir
                        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                            ".\$accountName",
                            "Modify",
                            "ContainerInherit,ObjectInherit",
                            "None",
                            "Allow"
                        )
                        $acl.SetAccessRule($rule)
                        Set-Acl -Path $binaryDir -AclObject $acl
                        Write-Host "Granted permissions on: $binaryDir" -ForegroundColor Green
                    }
                } catch {
                    Write-Host "Warning: Could not set folder permissions: $_" -ForegroundColor Yellow
                }
            }
            
            # Grant service registry key permissions
            try {
                $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$serviceName"
                if (Test-Path $regPath) {
                    $acl = Get-Acl $regPath
                    $rule = New-Object System.Security.AccessControl.RegistryAccessRule(
                        ".\$accountName",
                        "FullControl",
                        "ContainerInherit,ObjectInherit",
                        "None",
                        "Allow"
                    )
                    $acl.SetAccessRule($rule)
                    Set-Acl -Path $regPath -AclObject $acl
                    Write-Host "Granted registry permissions for: $serviceName" -ForegroundColor Green
                }
            } catch {
                Write-Host "Warning: Could not set registry permissions: $_" -ForegroundColor Yellow
            }
            
            $successCount++
            
            # Add small delay between configurations
            Start-Sleep -Seconds 1
            
        } catch {
            Write-Host "Error seating user to $($service.Name): $_" -ForegroundColor Red
        }
    }
    Write-Host "`nSuccessfully configured $successCount of $($axmServices.Count) services." -ForegroundColor Cyan
    
    # Wait longer before restarting to allow service account privileges to take effect
    if ($successCount -gt 0) {
        Write-Host "`nWaiting for service account configuration to settle..." -ForegroundColor Cyan
        Start-Sleep -Seconds 3
    }
}

# Restart all configured AXM services and their dependents
if ($axmServices.Count -gt 0) {
    Write-Host "`nStarting all configured AXM services..." -ForegroundColor Cyan
    
    # Add a longer delay before starting services to allow system to settle and permissions to take effect
    Write-Host "Waiting for system to stabilize (15 seconds)..." -ForegroundColor Yellow
    Start-Sleep -Seconds 15
    
    $restartCount = 0
    
    # Create a function to recursively start services and their dependencies
    function Start-ServiceWithDependencies {
        param(
            [string]$ServiceName,
            [hashtable]$StartedServices
        )
        
        # Skip if already started
        if ($StartedServices.ContainsKey($ServiceName)) {
            return
        }
        
        # Get the service
        $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        if (-not $svc) {
            Write-Host "Service $ServiceName not found." -ForegroundColor Red
            return
        }
        
        # Start service dependencies first
        foreach ($dep in $svc.ServicesDependedOn) {
            if (-not $StartedServices.ContainsKey($dep.Name)) {
                Start-ServiceWithDependencies -ServiceName $dep.Name -StartedServices $StartedServices
                Start-Sleep -Seconds 3
            }
        }
        
        # Now start the service itself
        try {
            if ($svc.Status -ne 'Running') {
                Write-Host "Attempting to start: $ServiceName" -ForegroundColor Yellow
                Start-Service -Name $ServiceName -ErrorAction Stop
                
                # Wait a bit and verify it's actually running
                Start-Sleep -Seconds 2
                $svcStatus = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
                
                if ($svcStatus.Status -eq 'Running') {
                    Write-Host "Started service: $ServiceName" -ForegroundColor Green
                    $StartedServices[$ServiceName] = $true
                } else {
                    Write-Host "Service $ServiceName started but not running. Status: $($svcStatus.Status)" -ForegroundColor Red
                    $StartedServices[$ServiceName] = $false
                    
                    # Check Event Viewer for errors
                    try {
                        $lastError = Get-WinEvent -LogName System -FilterXPath "*[System[EventID=7000 or EventID=7001 or EventID=7024 or EventID=7032 or EventID=7034 or EventID=7039 or EventID=7045] and System[Provider[@Name='Service Control Manager']]]" -MaxEvents 1 -ErrorAction SilentlyContinue
                        if ($lastError) {
                            Write-Host "Event Log: $($lastError.Message)" -ForegroundColor Red
                        }
                    } catch {}
                }
            } else {
                Write-Host "Service already running: $ServiceName" -ForegroundColor Cyan
                $StartedServices[$ServiceName] = $true
            }
        } catch {
            Write-Host "Error starting service $ServiceName : $_" -ForegroundColor Red
            $StartedServices[$ServiceName] = $false
            
            # Try to get more info from Event Viewer
            try {
                $lastError = Get-WinEvent -LogName System -FilterXPath "*[System[EventID=7000 or EventID=7001 or EventID=7024 or EventID=7032 or EventID=7034 or EventID=7039 or EventID=7045] and System[Provider[@Name='Service Control Manager']]]" -MaxEvents 1 -ErrorAction SilentlyContinue
                if ($lastError) {
                    Write-Host "Event Log: $($lastError.Message)" -ForegroundColor Red
                }
            } catch {}
        }
    }
    
    $startedServices = @{}
    
    # Start all AXM services in dependency order
    foreach ($service in $axmServices) {
        Start-ServiceWithDependencies -ServiceName $service.Name -StartedServices $startedServices
        Start-Sleep -Seconds 5
    }
    
    # Count successful starts
    $restartCount = ($startedServices.Values | Where-Object { $_ -eq $true }).Count
    
    Write-Host "`nSuccessfully started $restartCount of $($axmServices.Count) AXM services." -ForegroundColor Cyan
}

Write-Host "`nService user seating complete!" -ForegroundColor Green
Read-Host -Prompt 'Press Enter to exit'