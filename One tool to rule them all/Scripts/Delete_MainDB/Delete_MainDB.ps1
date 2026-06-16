<#'
.NAME
    Delete_MainDB
.VERSION
    1.0.0
.CATEGORY
    Tools
.SYNOPSIS
    Deletes LockSysMgr database files and the LocalDB instance directory for a selected edition.
.DESCRIPTION
    Checks for Administrator rights before execution. Prompts the user to select one of
    the supported software editions: Lite, Classic, or Plus. Based on the selected edition,
    the script deletes the corresponding LockSysMgr database files from
    C:\ProgramData\SimonsVoss\LockSysMgr\config.

    It then checks for the MSSqlLocalDB instance directory in the expected SysWOW64 or
    System32 systemprofile paths and attempts to delete the directory recursively.

    If the directory cannot be deleted, the script tries to stop sqlserver.exe and repeats
    the deletion attempt. The script is intended for cleanup/reset tasks and permanently
    removes files and directories.
.ADMIN #admin rights needed
    YES
#>
# 1. Pr�fen auf Administratorrechte
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Dieses Skript muss als Administrator ausgef�hrt werden." -ForegroundColor Red
    Read-Host "Bitte mit Administratorrechten neu starten. Dr�cken Sie Enter zum Beenden."
    exit 1
}

# 2. Edition abfragen
$validEditions = @("Lite", "Classic", "Plus")
do {
    $edition = Read-Host "Welche Software Edition soll bearbeitet werden? (Lite, Classic, Plus)"
} until ($validEditions -contains $edition)

$editionLower = $edition.ToLower()

# 3. Dateien l�schen
$configPath = "C:\ProgramData\SimonsVoss\LockSysMgr\config"
$mdfFile = Join-Path $configPath "main_${editionLower}.mdf"
$ldfFile = Join-Path $configPath "main_${editionLower}_log.ldf"

foreach ($file in @($mdfFile, $ldfFile)) {
    if (Test-Path $file) {
        try {
            Remove-Item $file -Force
            Write-Host "Datei gel�scht: $file"
        } catch {
            Write-Host "Fehler beim L�schen von: $file" -ForegroundColor Yellow
        }
    } else {
        Write-Host "Datei nicht gefunden: $file"
    }
}

# 4. Verzeichnis pr�fen
$dir1 = "C:\Windows\SysWOW64\config\systemprofile\AppData\Local\Microsoft\Microsoft SQL Server Local DB\Instances\MSSqlLocalDB\"
$dir2 = "C:\Windows\System32\config\systemprofile\AppData\Local\Microsoft\Microsoft SQL Server Local DB\Instances\MSSqlLocalDB\"
$targetDir = $null

if (Test-Path $dir1) {
    $targetDir = $dir1
} elseif (Test-Path $dir2) {
    $targetDir = $dir2
} else {
    Write-Host "Kein passendes Verzeichnis gefunden. Skript wird beendet." -ForegroundColor Red
    exit 1
}

# 5. Verzeichnis l�schen
function Try-DeleteDirectory {
    param($dir)
    try {
        Remove-Item $dir -Recurse -Force
        Write-Host "Verzeichnis gel�scht: $dir"
        return $true
    } catch {
        Write-Host "Fehler beim L�schen des Verzeichnisses: $dir" -ForegroundColor Yellow
        return $false
    }
}

$deleted = Try-DeleteDirectory $targetDir

# 6. Falls Fehler, sqlserver.exe beenden
if (-not $deleted) {
    $sqlProc = Get-Process -Name "sqlserver" -ErrorAction SilentlyContinue
    if ($sqlProc) {
        Write-Host "sqlserver.exe wird beendet..."
        try {
            $sqlProc | Stop-Process -Force
            Start-Sleep -Seconds 2
        } catch {
            Write-Host "Fehler beim Beenden von sqlserver.exe: $_" -ForegroundColor Yellow
        }
    } else {
        Write-Host "sqlserver.exe l�uft nicht."
    }

    # 7. Erneuter L�schversuch
    if (Try-DeleteDirectory $targetDir) {
        Write-Host "Verzeichnis nach Beenden von sqlserver.exe erfolgreich gel�scht."
    } else {
        Write-Host "Verzeichnis konnte nicht gel�scht werden." -ForegroundColor Red
    }
}