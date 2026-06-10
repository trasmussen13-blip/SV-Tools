# ----------------------------------------
# Log funktion
# ----------------------------------------
$logFile = "filter_log_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').txt"

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] $Message"
    Write-Host $logMessage
    Add-Content -Path $logFile -Value $logMessage -Encoding UTF8
}

# ----------------------------------------
# Start log
# ----------------------------------------
Write-Log "========================================"
Write-Log " CSV Filter og Delta Compare Tool"
Write-Log " Leveret AS IS af SimonsVoss"
Write-Log "========================================"

# ----------------------------------------
# STEP 1 - Filter Users_export.csv
# ----------------------------------------
Write-Log ""
Write-Log "----------------------------------------"
Write-Log " STEP 1: Filtrerer Users_export.csv"
Write-Log "----------------------------------------"

$usersInputFile  = "Users_export.csv"
$usersOutputFile = "Users_export_filtered.csv"
$allowedValues   = @("Elever m/sk:hjem", "Elever")

# Tjek om filen eksisterer
if (-not (Test-Path $usersInputFile)) {
    Write-Log "FEJL: $usersInputFile ikke fundet - afbryder!"
    exit 1
}

$usersData = Import-Csv -Path $usersInputFile -Delimiter ";" -Encoding UTF8

$usersFiltered = $usersData | Where-Object { $allowedValues -contains $_.UserGroupText }

# Erstat alle "." med ":" i alle felter
$usersModified = $usersFiltered | ForEach-Object {
    $row = $_
    $row.PSObject.Properties | ForEach-Object {
        $_.Value = $_.Value -replace '\.', ':'
    }
    $row
}

$usersModified | Export-Csv -Path $usersOutputFile -Delimiter ";" -Encoding UTF8 -NoTypeInformation

Write-Log "Original antal rækker:  $($usersData.Count)"
Write-Log "Beholdte rækker:        $($usersModified.Count)"
Write-Log "Slettede rækker:        $($usersData.Count - $usersModified.Count)"
Write-Log "Alle '.' erstattet med ':'"
Write-Log "Gemt som:               $usersOutputFile"

# ----------------------------------------
# STEP 2 - Filter LSM_export.csv
# ----------------------------------------
Write-Log ""
Write-Log "----------------------------------------"
Write-Log " STEP 2: Filtrerer LSM_export.csv"
Write-Log "----------------------------------------"

$lsmInputFile = "LSM_export.csv"

# Tjek om filen eksisterer
if (-not (Test-Path $lsmInputFile)) {
    Write-Log "FEJL: $lsmInputFile ikke fundet - afbryder!"
    exit 1
}

$lsmData     = Import-Csv -Path $lsmInputFile -Delimiter ";" -Encoding UTF8
$lsmFiltered = $lsmData | Where-Object { $allowedValues -contains $_."TransponderGroup.Name" }

Write-Log "Original antal rækker:  $($lsmData.Count)"
Write-Log "Beholdte rækker:        $($lsmFiltered.Count)"
Write-Log "Slettede rækker:        $($lsmData.Count - $lsmFiltered.Count)"
Write-Log "Ingen dot replacement - LSM data er gyldigt som det er"

# ----------------------------------------
# STEP 3 - Delta sammenligning
# ----------------------------------------
Write-Log ""
Write-Log "----------------------------------------"
Write-Log " STEP 3: Delta sammenligning"
Write-Log "----------------------------------------"

$deltaFile = "delta_export.csv"

# Udpak UserId fra den filtrerede Users liste
$userIds = $usersModified | Select-Object -ExpandProperty "UserId"

# Find rækker i LSM der IKKE findes i Users
$deltaData = $lsmFiltered | Where-Object {
    $_."Person.PersonalNumber" -notin $userIds
}

$deltaData | Export-Csv -Path $deltaFile -Delimiter ";" -Encoding UTF8 -NoTypeInformation

Write-Log "LSM rækker total:          $($lsmFiltered.Count)"
Write-Log "Users rækker total:        $($usersModified.Count)"
Write-Log "Delta rækker (kun i LSM):  $($deltaData.Count)"
Write-Log "Gemt som:                  $deltaFile"

# ----------------------------------------
# Afslut log
# ----------------------------------------
Write-Log ""
Write-Log "========================================"
Write-Log " Alle steps fuldfoert!"
Write-Log " Log gemt som: $logFile"
Write-Log "========================================"