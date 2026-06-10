# ----------------------------------------
# CONFIGURATION
# ----------------------------------------

# Input file exported from the Users system
$usersInputFile  = "Users_export.csv"

# Output file after filtering and dot replacement from Users system
$usersOutputFile = "Users_export_filtered.csv"

# Input file exported from the LSM system
$lsmInputFile    = "LSM_export.csv"

# Output file containing records present in LSM but not in Users (used for deletion in LSM)
$deltaFile       = "delta_export.csv"

# Log file - all runs are appended to this file
$logFile         = "filter_log.txt"

# Allowed values in UserGroupText (Users) and TransponderGroup.Name (LSM)
# Only rows matching these values will be kept - all other rows will be removed
$allowedValues   = @("Elever m/sk:hjem", "Elever")

# Maximum allowed delta size as a percentage of filtered LSM row count
# If delta exceeds this threshold the process will stop and no delta file will be saved
# Example: 20 means delta cannot exceed 20% of LSM filtered rows
$blastRadiusPct  = 20

# CSV delimiter used in all input and output files
# Use ";" for semicolon separated files or "," for comma separated files
$delimiter       = ";"

# Character encoding used when reading and writing all CSV files
$encoding        = "UTF8"

#
#  ██████╗  ██████╗     ███╗   ██╗ ██████╗ ████████╗    ███████╗██████╗ ██╗████████╗
#  ██╔══██╗██╔═══██╗    ████╗  ██║██╔═══██╗╚══██╔══╝    ██╔════╝██╔══██╗██║╚══██╔══╝
#  ██║  ██║██║   ██║    ██╔██╗ ██║██║   ██║   ██║       █████╗  ██║  ██║██║   ██║
#  ██║  ██║██║   ██║    ██║╚██╗██║██║   ██║   ██║       ██╔══╝  ██║  ██║██║   ██║
#  ██████╔╝╚██████╔╝    ██║ ╚████║╚██████╔╝   ██║       ███████╗██████╔╝██║   ██║
#  ╚═════╝  ╚═════╝     ╚═╝  ╚═══╝ ╚═════╝    ╚═╝       ╚══════╝╚═════╝ ╚═╝   ╚═╝
#
#   █████╗ ███╗   ██╗██╗   ██╗████████╗██╗  ██╗██╗███╗   ██╗ ██████╗
#  ██╔══██╗████╗  ██║╚██╗ ██╔╝╚══██╔══╝██║  ██║██║████╗  ██║██╔════╝
#  ███████║██╔██╗ ██║ ╚████╔╝    ██║   ███████║██║██╔██╗ ██║██║  ███╗
#  ██╔══██║██║╚██╗██║  ╚██╔╝     ██║   ██╔══██║██║██║╚██╗██║██║   ██║
#  ██║  ██║██║ ╚████║   ██║      ██║   ██║  ██║██║██║ ╚████║╚██████╔╝
#  ╚═╝  ╚═╝╚═╝  ╚═══╝   ╚═╝      ╚═╝   ╚═╝  ╚═╝╚═╝╚═╝  ╚═══╝ ╚═════╝
#
#  ██████╗ ███████╗██╗      ██████╗ ██╗    ██╗    ████████╗██╗  ██╗██╗███████╗
#  ██╔══██╗██╔════╝██║     ██╔═══██╗██║    ██║    ╚══██╔══╝██║  ██║██║██╔════╝
#  ██████╔╝█████╗  ██║     ██║   ██║██║ █╗ ██║       ██║   ███████║██║███████╗
#  ██╔══██╗██╔══╝  ██║     ██║   ██║██║███╗██║       ██║   ██╔══██║██║╚════██║
#  ██████╔╝███████╗███████╗╚██████╔╝╚███╔███╔╝       ██║   ██║  ██║██║███████║
#  ╚═════╝ ╚══════╝╚══════╝ ╚═════╝  ╚══╝╚══╝        ╚═╝   ╚═╝  ╚═╝╚═╝╚══════╝
#
#  ██╗     ██╗███╗   ██╗███████╗    ██╗
#  ██║     ██║████╗  ██║██╔════╝    ██║
#  ██║     ██║██╔██╗ ██║█████╗      ██║
#  ██║     ██║██║╚██╗██║██╔══╝      ╚═╝
#  ███████╗██║██║ ╚████║███████╗    ██╗
#  ╚══════╝╚═╝╚═╝  ╚═══╝╚══════╝    ╚═╝
#


# ----------------------------------------
# Log funktion - single append log file
# ----------------------------------------
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp][$Level] $Message"
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
Write-Log ""
Write-Log "Konfiguration:"
Write-Log "  Users input:      $usersInputFile"
Write-Log "  Users output:     $usersOutputFile"
Write-Log "  LSM input:        $lsmInputFile"
Write-Log "  Delta output:     $deltaFile"
Write-Log "  Log fil:          $logFile"
Write-Log "  Delimiter:        $delimiter"
Write-Log "  Encoding:         $encoding"
Write-Log "  Blast radius:     $blastRadiusPct%"
Write-Log "  Tilladte værdier: $($allowedValues -join ', ')"

# ----------------------------------------
# STEP 1 - Filter Users_export.csv
# ----------------------------------------
Write-Log ""
Write-Log "----------------------------------------"
Write-Log " STEP 1: Filtrerer $usersInputFile"
Write-Log "----------------------------------------"

if (-not (Test-Path $usersInputFile)) {
    Write-Log "FEJL: $usersInputFile ikke fundet - afbryder!" "ERROR"
    exit 1
}

$usersData = Import-Csv -Path $usersInputFile -Delimiter $delimiter -Encoding $encoding

$usersFiltered = $usersData | Where-Object { $allowedValues -contains $_.UserGroupText }

# Erstat alle "." med ":" i alle felter
$usersModified = $usersFiltered | ForEach-Object {
    $row = $_
    $row.PSObject.Properties | ForEach-Object {
        $_.Value = $_.Value -replace '\.', ':'
    }
    $row
}

$usersModified | Export-Csv -Path $usersOutputFile -Delimiter $delimiter -Encoding $encoding -NoTypeInformation

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
Write-Log " STEP 2: Filtrerer $lsmInputFile"
Write-Log "----------------------------------------"

if (-not (Test-Path $lsmInputFile)) {
    Write-Log "FEJL: $lsmInputFile ikke fundet - afbryder!" "ERROR"
    exit 1
}

$lsmData     = Import-Csv -Path $lsmInputFile -Delimiter $delimiter -Encoding $encoding
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

$userIds    = $usersModified | Select-Object -ExpandProperty "UserId"
$deltaData  = $lsmFiltered | Where-Object { $_."Person.PersonalNumber" -notin $userIds }
$lsmCount   = $lsmFiltered.Count
$deltaCount = $deltaData.Count

if ($lsmCount -gt 0) {
    $deltaPercent = [math]::Round(($deltaCount / $lsmCount) * 100, 2)
} else {
    $deltaPercent = 0
}

Write-Log "LSM rækker total:          $lsmCount"
Write-Log "Users rækker total:        $($usersModified.Count)"
Write-Log "Delta rækker (kun i LSM):  $deltaCount"
Write-Log "Delta procent af LSM:      $deltaPercent%"
Write-Log "Blast radius graense:      $blastRadiusPct%"

# ----------------------------------------
# Blast radius kontrol
# ----------------------------------------
if ($deltaPercent -gt $blastRadiusPct) {
    Write-Log ""
    Write-Log "========================================" "ERROR"
    Write-Log " BLAST RADIUS SIKKERHED UDLOST!"        "ERROR"
    Write-Log " Delta ($deltaPercent%) overstiger den maksimale graense paa $blastRadiusPct% af LSM data!" "ERROR"
    Write-Log " delta_export.csv er IKKE blevet gemt!" "ERROR"
    Write-Log " Gennemgaa data manuelt foer fortsaettelse!" "ERROR"
    Write-Log "========================================" "ERROR"
    exit 1
}

$deltaData | Export-Csv -Path $deltaFile -Delimiter $delimiter -Encoding $encoding -NoTypeInformation

Write-Log "Blast radius kontrol OK - delta er inden for graensen"
Write-Log "Gemt som: $deltaFile"

# ----------------------------------------
# Afslut log
# ----------------------------------------
Write-Log ""
Write-Log "========================================"
Write-Log " Alle steps fuldfoert!"
Write-Log "========================================"
Write-Log ""