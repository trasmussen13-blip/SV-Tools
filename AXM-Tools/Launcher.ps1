<#
.NAME
    Launcher
.VERSION
    1.2.1
.CATEGORY
    Utility / Script Launcher
.SYNOPSIS
    Scans ./scripts subfolders and presents an interactive menu for running tools.
.DESCRIPTION
    This launcher scans the ./scripts directory for subfolders containing one tool each.
    Supported tool types are PowerShell scripts (.ps1) and batch files (.bat, .cmd).
    Features:
    - Detects one tool per subfolder
    - Prefers .ps1 over .bat/.cmd
    - Reads metadata from headers
    - Groups tools by category
    - Opens readme.md
    - Runs elevated when required
.ADMIN
    YES
#>
#region Helpers
function Parse-ScriptHeader {
param(
[string]$Path
)
$meta = [ordered]@{
Name =
[System.IO.Path]::GetFileNameWithoutExtension($Path)
Version = ''
Category = ''
Synopsis = ''
Description = ''
Admin = $false
File = $Path
Readme = $null
}
# ------------------------------------------------------------
# README
# ------------------------------------------------------------
$readmePath =
Join-Path `
([System.IO.Path]::GetDirectoryName($Path)) `
'readme.md'
if(Test-Path $readmePath){
$meta.Readme = $readmePath
}
$ext =
[System.IO.Path]::GetExtension($Path).ToLowerInvariant()
# ============================================================
# POWERSHELL SCRIPT PARSER
# ============================================================
if($ext -eq '.ps1'){
$content =
Get-Content `
-Path $Path `
-Raw `
-ErrorAction SilentlyContinue
if(!$content){
return $meta
}
if($content -match "(?s)<#(.*?)#>"){
$block=$Matches[1]
$fields=@{
Name        = 'NAME'
Version     = 'VERSION'
Category    = 'CATEGORY'
Synopsis    = 'SYNOPSIS'
Description = 'DESCRIPTION'
AdminRaw    = 'ADMIN'
}
foreach($prop in $fields.Keys){
$tag=$fields[$prop]
$pattern =
"(?ms)^\s*\.$tag\s*(?:\r?\n)(.*?)(?=^\s*\.[A-Z]+|\z)"
if($block -match $pattern){
$value =
$Matches[1].Trim()
if($prop -eq 'AdminRaw'){
$meta.Admin =
($value -ieq 'YES')
}
else{
$meta[$prop]=$value
}
}
}
}
return $meta
}
# ============================================================
# BAT / CMD PARSER
# ============================================================
elseif($ext -in '.bat','.cmd'){
$lines =
Get-Content `
-Path $Path `
-TotalCount 200 `
-ErrorAction SilentlyContinue
if(!$lines){
return $meta
}
$inDesc=$false
$descLines=@()
foreach($line in $lines){
$trim=$line.Trim()
# HEADER TAG
if(
$trim -match
'^(?i:(?:rem\s+|::))\s*\.(NAME|VERSION|CATEGORY|SYNOPSIS|DESCRIPTION|ADMIN)\b\s*(.*)$'
){
$tag=$Matches[1].ToUpper()
$val=$Matches[2].Trim()
switch($tag){
'NAME' {
if($val){
$meta.Name=$val
}
}
'VERSION' {
$meta.Version=$val
}
'CATEGORY' {
$meta.Category=$val
}
'SYNOPSIS' {
$meta.Synopsis=$val
}
'ADMIN' {
$meta.Admin =
($val -ieq 'YES')
}
'DESCRIPTION' {
$inDesc=$true
if($val){
$descLines += $val
}
}
}
continue
}
# DESCRIPTION CONTINUATION
if(
$inDesc -and
$trim -match
'^(?i:(?:rem\s+|::))(.*)$'
){
$descLines += $Matches[1].Trim()
continue
}
# STOP DESCRIPTION
if($inDesc){
$inDesc=$false
}
}
if($descLines.Count -gt 0){
$meta.Description =
($descLines -join "`n").Trim()
}
return $meta
}
return $meta
}
function Test-IsAdmin {
$id =
[Security.Principal.WindowsIdentity]::GetCurrent()
$p =
New-Object Security.Principal.WindowsPrincipal($id)
return $p.IsInRole(
[Security.Principal.WindowsBuiltInRole]::Administrator
)
}
function Invoke-Elevated {
param(
[string]$ScriptPath
)
$extension =
[System.IO.Path]::GetExtension($ScriptPath)
if($extension -ieq '.ps1'){
Start-Process `
-FilePath 'powershell.exe' `
-ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`"" `
-Verb RunAs
}
elseif($extension -in '.bat','.cmd'){
Start-Process `
-FilePath 'cmd.exe' `
-ArgumentList "/c `"$ScriptPath`"" `
-Verb RunAs
}
else{
throw "Unsupported script type: $ScriptPath"
}
}
function Invoke-Normal {
param(
[string]$ScriptPath
)
$extension =
[System.IO.Path]::GetExtension($ScriptPath)
if($extension -ieq '.ps1'){
& powershell.exe `
-NoProfile `
-ExecutionPolicy Bypass `
-File "$ScriptPath"
}
elseif($extension -in '.bat','.cmd'){
& cmd.exe /c "`"$ScriptPath`""
}
else{
throw "Unsupported script type: $ScriptPath"
}
}
function Open-Readme {
param(
[string]$ReadmePath
)
try{
Start-Process `
-FilePath $ReadmePath
}
catch{
Write-Host `
"  Could not open readme: $_" `
-ForegroundColor Red
Start-Sleep 2
}
}
#endregion
#region UI
function Write-Banner {
$bannerPath =
Join-Path $PSScriptRoot 'banner.txt'
if(!(Test-Path $bannerPath)){
Write-Host `
'[banner.txt not found]' `
-ForegroundColor DarkGray
return
}
foreach($line in Get-Content $bannerPath){
if($line -match '[#\+\*=\.\:\-]'){
Write-Host `
$line `
-ForegroundColor Cyan
}
else{
Write-Host `
$line `
-ForegroundColor DarkGray
}
}
}
function Write-Header {
Clear-Host
Write-Banner
Write-Host ''
Write-Host ('-'*80) `
-ForegroundColor DarkGray
Write-Host ''
}
function Write-Menu {
param(
[array]$Scripts
)
Write-Header
Write-Host `
'  Available tools' `
-ForegroundColor Yellow
Write-Host ''
$script:DisplayTools=@()
Write-Host '       ' -NoNewline
Write-Host `
'Name'.PadRight(32) `
-NoNewline `
-ForegroundColor DarkGray
Write-Host `
'Version'.PadRight(10) `
-NoNewline `
-ForegroundColor DarkGray
Write-Host `
'Category'.PadRight(24) `
-NoNewline `
-ForegroundColor DarkGray
Write-Host `
'Flags' `
-ForegroundColor DarkGray
Write-Host ('-'*80) `
-ForegroundColor DarkGray
$groups =
$Scripts |
Group-Object {
$c =
($_.Category -as [string]).Trim()
if($c){
$c
}
else{
'(Uncategorized)'
}
} |
Sort-Object Name
$index=0
foreach($g in $groups){
Write-Host ''
Write-Host `
"  $($g.Name)" `
-ForegroundColor Cyan
foreach($s in ($g.Group | Sort-Object Name)){
$script:DisplayTools += $s
$index++
$num =
"$index".PadLeft(3)
$ver =
if($s.Version){
"v$($s.Version)"
}
else{
'-'
}
$flags=@()
if($s.Admin){
$flags+='ADMIN'
}
if($s.Readme){
$flags+='README'
}
$flagText =
if($flags.Count){
"[$($flags -join '] [')]"
}
else{
''
}
Write-Host `
"  $num. " `
-NoNewline `
-ForegroundColor White
Write-Host `
$s.Name.PadRight(32) `
-NoNewline `
-ForegroundColor Green
Write-Host `
$ver.PadRight(10) `
-NoNewline `
-ForegroundColor DarkGray
Write-Host `
$($s.Category).PadRight(24) `
-NoNewline `
-ForegroundColor DarkGray
Write-Host `
$flagText `
-ForegroundColor Yellow
}
}
Write-Host ''
Write-Host ('-'*80) `
-ForegroundColor DarkGray
Write-Host `
'  [Q] Quit' `
-ForegroundColor DarkGray
}
function Write-ScriptDetail {
param(
[object]$Script
)
Write-Header
Write-Host `
"  $($Script.Name)" `
-ForegroundColor Green
Write-Host ''
if($Script.Version){
Write-Host `
"  Version : $($Script.Version)"
}
if($Script.Category){
Write-Host `
"  Category : $($Script.Category)"
}
if($Script.Admin){
Write-Host `
"  Requires : ADMINISTRATOR" `
-ForegroundColor Yellow
}
if($Script.Readme){
Write-Host `
"  Readme : $($Script.Readme)" `
-ForegroundColor DarkGray
}
Write-Host ''
Write-Host ('-'*80)
Write-Host ''
Write-Host `
'  SYNOPSIS' `
-ForegroundColor Cyan
Write-Host `
"  $($Script.Synopsis)"
if($Script.Description){
Write-Host ''
Write-Host `
'  DESCRIPTION' `
-ForegroundColor Cyan
Write-Host `
$Script.Description
}
Write-Host ''
Write-Host `
'[R] Run   [H] Help   [B] Back'
}
#endregion
#region MAIN LOOP
$scriptsFolder =
Join-Path $PSScriptRoot 'scripts'
if(!(Test-Path $scriptsFolder)){
Write-Warning `
"Scripts folder not found: $scriptsFolder"
exit 1
}
# FIND TOOLS
# PS1 gets priority over BAT/CMD
$scriptFiles =
Get-ChildItem `
-Path $scriptsFolder `
-Directory |
ForEach-Object {
    Get-ChildItem `
    -Path $_.FullName `
    -File |
    Where-Object {
        $_.Extension -in '.ps1','.bat','.cmd'
    } |
    Sort-Object @{
        Expression = {
            if($_.Extension -eq '.ps1'){
                0
            }
            else{
                1
            }
        }
    } |
    Select-Object -First 1
} |
Where-Object {
    $_ -ne $null
} |
Sort-Object Name
if(!$scriptFiles -or $scriptFiles.Count -eq 0){
Write-Warning `
"No scripts found under $scriptsFolder"
exit 0
}
[array]$tools =
$scriptFiles |
ForEach-Object {
    Parse-ScriptHeader $_.FullName
}
$script:DisplayTools=@()
:main while($true){
Write-Menu -Scripts $tools
$choice =
Read-Host `
'  Select tool #'
if($choice -match '^[qQ]$'){
Write-Host ''
Write-Host `
' Goodbye.' `
-ForegroundColor Cyan
break main
}
if($choice -notmatch '^\d+$'){
continue
}
$index =
([int]$choice)-1
if(
$index -lt 0 -or
$index -ge $script:DisplayTools.Count
){
Write-Host `
' Invalid selection.' `
-ForegroundColor Red
Start-Sleep 1
continue
}
$tool =
$script:DisplayTools[$index]
:detail while($true){
Write-ScriptDetail `
$tool
$action =
(Read-Host '  Choice').Trim()
switch -Regex ($action){
'^[bB]$' {
break detail
}
'^[hH]$' {
if($tool.Readme){
Open-Readme `
$tool.Readme
}
else{
Write-Host `
' No readme available.' `
-ForegroundColor Red
Start-Sleep 1
}
}
'^[rR]$' {
if(
$tool.Admin -and
-not(Test-IsAdmin)
){
Write-Host ''
Write-Host `
' Requires administrator - launching elevated...' `
-ForegroundColor Yellow
Start-Sleep 1
Invoke-Elevated `
$tool.File
}
else{
Write-Host ''
Write-Host `
' Running...' `
-ForegroundColor Green
Invoke-Normal `
$tool.File
Write-Host ''
Write-Host `
' Done. Press any key to return.' `
-ForegroundColor DarkGray
$null =
$Host.UI.RawUI.ReadKey(
'NoEcho,IncludeKeyDown'
)
}
break detail
}
default{
Write-Host `
' Invalid key. Use R, H or B.' `
-ForegroundColor Red
Start-Sleep 1
}
}
}
}
#endregion