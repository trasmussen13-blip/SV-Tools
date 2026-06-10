# Indlæs CSV filen
$inputFile = "LSM_export.csv"
$outputFile = "LSM_export_filtered.csv"

# Definer de tilladte værdier i TransponderGroup.Name kolonnen
$allowedValues = @("Elever m/sk:hjem", "Elever")

# Indlæs og filtrer CSV
$csvData = Import-Csv -Path $inputFile -Delimiter ";" -Encoding UTF8

# Brug $_."TransponderGroup.Name" pga. punktum i kolonnenavnet
$filteredData = $csvData | Where-Object { $allowedValues -contains $_."TransponderGroup.Name" }

# Erstat alle "." med ":" i alle felter
$modifiedData = $filteredData | ForEach-Object {
    $row = $_
    $row.PSObject.Properties | ForEach-Object {
        $_.Value = $_.Value -replace '\.', ':'
    }
    $row
}

# Gem den filtrerede og modificerede data til en ny CSV fil
$modifiedData | Export-Csv -Path $outputFile -Delimiter ";" -Encoding UTF8 -NoTypeInformation

# Vis statistik
$originalCount = $csvData.Count
$filteredCount = $modifiedData.Count
$removedCount = $originalCount - $filteredCount

Write-Host "----------------------------------------"
Write-Host "Original antal rækker:  $originalCount"
Write-Host "Beholdte rækker:        $filteredCount"
Write-Host "Slettede rækker:        $removedCount"
Write-Host "Alle '.' er erstattet med ':'"
Write-Host "----------------------------------------"
Write-Host "Filtreret fil gemt som: $outputFile"