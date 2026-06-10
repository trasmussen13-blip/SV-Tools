# Indlæs de filtrerede CSV filer
$lsmFile    = "LSM_export_filtered.csv"
$usersFile  = "Users_export_filtered.csv"
$deltaFile  = "delta_export.csv"

# Indlæs begge CSV filer
$lsmData   = Import-Csv -Path $lsmFile   -Delimiter ";" -Encoding UTF8
$usersData = Import-Csv -Path $usersFile -Delimiter ";" -Encoding UTF8

# Udpak UserId fra Users filen til sammenligning
$userIds = $usersData | Select-Object -ExpandProperty "UserId"

# Find rækker i LSM der IKKE findes i Users (baseret på PersonalNumber vs UserId)
$deltaData = $lsmData | Where-Object {
    $_."Person.PersonalNumber" -notin $userIds
}

# Gem delta til ny CSV
$deltaData | Export-Csv -Path $deltaFile -Delimiter ";" -Encoding UTF8 -NoTypeInformation

# Vis statistik
Write-Host "----------------------------------------"
Write-Host "LSM rækker total:          $($lsmData.Count)"
Write-Host "Users rækker total:        $($usersData.Count)"
Write-Host "----------------------------------------"
Write-Host "Delta rækker (kun i LSM):  $($deltaData.Count)"
Write-Host "----------------------------------------"
Write-Host "Delta fil gemt som:        $deltaFile"