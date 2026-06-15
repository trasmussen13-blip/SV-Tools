<#
.NAME
    Launcher
.VERSION
    1.0.0
.SYNOPSIS
    Scans ./scripts and presents an interactive menu for running PS tools.
#>

#region ── Helpers ──────────────────────────────────────────────────────────────

function Parse-ScriptHeader {
    param([string]$Path)

    $meta = [ordered]@{
        Name        = [System.IO.Path]::GetFileNameWithoutExtension($Path)
        Version     = ''
        Category    = ''
        Synopsis    = ''
        Description = ''
        Admin       = $false
        File        = $Path
    }

    $content = Get-Content -Path $Path -Raw -ErrorAction SilentlyContinue
    if (-not $content) { return $meta }

    # Pull everything inside <#' ... #>
    if ($content -match "(?s)<#'?(.*?)#>") {
        $block = $Matches[1]

        $fields = @{
            Name        = 'NAME'
            Version     = 'VERSION'
            Category    = 'CATEGORY'
            Synopsis    = 'SYNOPSIS'
            Description = 'DESCRIPTION'
            AdminRaw    = 'ADMIN'
        }

        foreach ($prop in $fields.Keys) {
            $tag = $fields[$prop]
            if ($block -match "(?im)^\s*\.$tag\s*[\r
]+((?:[ \t]+[^\r
]*[\r
]?)+)") {
                $value = $Matches[1].Trim()
                if ($prop -eq 'AdminRaw') {
                    $meta['Admin'] = ($value -ieq 'YES')
                } else {
                    $meta[$prop] = $value
                }
            }
        }
    }

    return $meta
}

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-Elevated {
    param([string]$ScriptPath)
    Start-Process -FilePath 'powershell.exe' `
                  -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`"" `
                  -Verb RunAs
}

function Invoke-Normal {
    param([string]$ScriptPath)
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$ScriptPath"
}

#endregion

#region ── UI helpers ───────────────────────────────────────────────────────────

function Write-Header {
    $width = 60
    $title = ' PS Tool Launcher '
    $pad   = [math]::Floor(($width - $title.Length) / 2)
    Clear-Host
    Write-Host ('═' * $width)                       -ForegroundColor Cyan
    Write-Host ((' ' * $pad) + $title)              -ForegroundColor Cyan
    Write-Host ('═' * $width)                       -ForegroundColor Cyan
    Write-Host ''
}

function Write-Menu {
    param([array]$Scripts)

    Write-Header
    Write-Host '  Available tools' -ForegroundColor Yellow
    Write-Host ''

    for ($i = 0; $i -lt $Scripts.Count; $i++) {
        $s     = $Scripts[$i]
        $num   = "$($i + 1)".PadLeft(3)
        $name  = $s.Name.PadRight(30)
        $ver   = if ($s.Version)  { "v$($s.Version)" } else { '' }
        $cat   = if ($s.Category) { " [$($s.Category.Trim())]" } else { '' }
        $admin = if ($s.Admin)    { ' [ADMIN]' } else { '' }

        Write-Host "  $num. " -NoNewline -ForegroundColor White
        Write-Host $name      -NoNewline -ForegroundColor Green
        Write-Host "$ver$cat$admin"                 -ForegroundColor DarkGray
    }

    Write-Host ''
    Write-Host ('─' * 60) -ForegroundColor DarkGray
    Write-Host '  [Q] Quit'  -ForegroundColor DarkGray
    Write-Host ''
}

function Write-ScriptDetail {
    param([System.Collections.Specialized.OrderedDictionary]$Script)

    Write-Header
    Write-Host "  $($Script.Name)"                      -ForegroundColor Green
    if ($Script.Version)  { Write-Host "  Version  : $($Script.Version)"         -ForegroundColor DarkGray }
    if ($Script.Category) { Write-Host "  Category : $($Script.Category.Trim())" -ForegroundColor DarkGray }
    if ($Script.Admin)    { Write-Host "  Requires : ADMINISTRATOR"               -ForegroundColor Yellow   }

    Write-Host ''
    Write-Host '  Synopsis' -ForegroundColor Cyan
    Write-Host "  $($Script.Synopsis)" -ForegroundColor White

    if ($Script.Description) {
        Write-Host ''
        Write-Host '  Description' -ForegroundColor Cyan
        # Simple word-wrap at 56 chars
        $words = $Script.Description -split '\s+'
        $line  = '  '
        foreach ($w in $words) {
            if (($line + $w).Length -gt 58) {
                Write-Host $line
                $line = "  $w "
            } else {
                $line += "$w "
            }
        }
        if ($line.Trim()) { Write-Host $line }
    }

    Write-Host ''
    Write-Host ('─' * 60)              -ForegroundColor DarkGray
    Write-Host '  [R] Run   [B] Back'  -ForegroundColor Yellow
    Write-Host ''
}

#endregion

#region ── Main loop ────────────────────────────────────────────────────────────

$scriptsFolder = Join-Path $PSScriptRoot 'scripts'

if (-not (Test-Path $scriptsFolder)) {
    Write-Warning "Scripts folder not found: $scriptsFolder"
    exit 1
}

$scriptFiles = Get-ChildItem -Path $scriptsFolder -Filter '*.ps1' -File |
               Sort-Object Name

if ($scriptFiles.Count -eq 0) {
    Write-Warning "No .ps1 files found in $scriptsFolder"
    exit 0
}

# Parse headers once at startup
[array]$tools = $scriptFiles | ForEach-Object { Parse-ScriptHeader -Path $_.FullName }

:main while ($true) {

    Write-Menu -Scripts $tools

    $choice = Read-Host '  Select tool #'

    # Quit
    if ($choice -match '^[qQ]$') {
        Write-Host "`n  Goodbye.`n" -ForegroundColor Cyan
        break main
    }

    # Validate number
    if ($choice -notmatch '^\d+$') { continue }

    $idx = [int]$choice - 1
    if ($idx -lt 0 -or $idx -ge $tools.Count) {
        Write-Host '  Invalid selection.' -ForegroundColor Red
        Start-Sleep -Seconds 1
        continue
    }

    $tool = $tools[$idx]

    # ── Detail / run loop ────────────────────────────────────────────────────
    :detail while ($true) {

        Write-ScriptDetail -Script $tool

        $action = (Read-Host '  Choice').Trim()

        switch -Regex ($action) {

            '^[bB]$' {
                break detail
            }

            '^[rR]$' {
                if ($tool.Admin -and -not (Test-IsAdmin)) {
                    Write-Host ''
                    Write-Host '  Script requires elevation – launching as Administrator...' `
                               -ForegroundColor Yellow
                    Start-Sleep -Seconds 1
                    Invoke-Elevated -ScriptPath $tool.File
                } else {
                    Write-Host ''
                    Write-Host '  Running...' -ForegroundColor Green
                    Write-Host ''
                    Invoke-Normal -ScriptPath $tool.File
                    Write-Host ''
                    Write-Host '  Done. Press any key to return to menu.' `
                               -ForegroundColor DarkGray
                    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
                }
                break detail
            }

            default {
                Write-Host '  Press R to run or B to go back.' -ForegroundColor Red
                Start-Sleep -Seconds 1
            }
        }
    }
}

#endregion