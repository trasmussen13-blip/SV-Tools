<#
.NAME
    AXM Log Condenser
.VERSION
    3.1.0
.CATEGORY
    AXM Diagnostics
.SYNOPSIS
    Analyses AXM logs and creates condensed diagnostic reports.
.DESCRIPTION
    Parses AXM Plus logs, groups repeated errors,
    extracts timestamps, components and stack traces.

    WORKS ONLY WITH AXM LOGS!
.ADMIN
    NO
#>
param(
    [Parameter(Position=0)]
    [string]$Path,
    [switch]$Save,
    [string]$LogDir =
    (Join-Path $env:USERPROFILE 'AppData\Local\SimonsVoss\LockSysMgr\log')
)
# ============================================================
# LOG SELECTOR
# ============================================================
function Select-LogFromFolder {
param(
[string]$LogDirectory
)
if(-not(Test-Path $LogDirectory)){
    throw "Log directory not found: $LogDirectory"
}
$files = @(
    Get-ChildItem $LogDirectory -File |
    Where-Object {
        $_.Extension -in '.txt','.log'
    } |
    Sort-Object LastWriteTime -Descending
)
if($files.Count -eq 0){
    throw "No log files found."
}
Write-Host ""
Write-Host "Log files found:" -ForegroundColor Cyan
Write-Host ('-' * 75) -ForegroundColor DarkGray
for($i=0;$i -lt $files.Count;$i++){
    $f=$files[$i]
    Write-Host (
        "[{0,2}] {1,-50} {2,8} KB {3}" -f
        ($i+1),
        $f.Name,
        ([math]::Round($f.Length/1KB,1)),
        $f.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
    )
}
Write-Host ('-' * 75) -ForegroundColor DarkGray
$selection = Read-Host "Select log (Enter = 1)"
if([string]::IsNullOrWhiteSpace($selection)){
    $selection = 1
}
if($selection -match '^\d+$'){
    $index=[int]$selection
    if($index -ge 1 -and $index -le $files.Count){
        return $files[$index-1].FullName
    }
}
throw "Invalid selection."
}
# ============================================================
# PARSER
# ============================================================
function Parse-PrimaryLine {
param(
[string]$Line
)
$regex =
'^(?<Timestamp>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3})\s+(?<Offset>[+-]\d{2}:\d{2})\s+\|(?<Level>[A-Z])\|:\s+(?<Message>.+?)(?:\s+<s:(?<Component>[^>]+)>)?\s*$'
$m=[regex]::Match($Line,$regex)
if(-not $m.Success){
    return $null
}
$ts=[datetimeoffset]::ParseExact(
    "$($m.Groups['Timestamp'].Value) $($m.Groups['Offset'].Value)",
    'yyyy-MM-dd HH:mm:ss.fff zzz',
    [cultureinfo]::InvariantCulture
)
[PSCustomObject]@{
    Timestamp =
    $ts.LocalDateTime
    Level =
    $m.Groups['Level'].Value
    Message =
    $m.Groups['Message'].Value.Trim()
    Component =
    if($m.Groups['Component'].Success){
        $m.Groups['Component'].Value.Trim()
    }
    else{
        ''
    }
    StackTrace =
    [System.Collections.Generic.List[string]]::new()
}
}
function Get-AXMLogEntries {
param(
[string]$LogPath
)
if(-not(Test-Path $LogPath)){
    throw "Log file not found: $LogPath"
}
$entries =
[System.Collections.Generic.List[object]]::new()
$current=$null
foreach($line in Get-Content $LogPath -Encoding UTF8){
    if($line -match
    '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3}') {
        $parsed =
        Parse-PrimaryLine $line
        if($parsed){
            if($null -ne $current){
                $entries.Add($current)
            }
            $current=$parsed
            continue
        }
    }
    if($null -ne $current -and $line.Trim()){
        $current.StackTrace.Add($line)
    }
}
if($null -ne $current){
    $entries.Add($current)
}
if($entries.Count -eq 0){
    throw "No valid AXM log entries found."
}
return ,$entries
}
# ============================================================
# ANALYSIS
# ============================================================
function Get-InfoBlock {
param(
[object]$Entries,
[string]$LogPath
)
$file = Get-Item $LogPath
$first = $Entries | Select-Object -First 1
$last  = $Entries | Select-Object -Last 1
$levels=@{
    F=0
    E=0
    W=0
    I=0
    D=0
}
foreach($entry in $Entries){
    if($levels.ContainsKey($entry.Level)){
        $levels[$entry.Level]++
    }
}
$services =
$Entries |
Where-Object {
    $_.Component
} |
Select-Object -ExpandProperty Component |
Sort-Object -Unique
[PSCustomObject]@{
    FileName =
    $file.Name
    FilePath =
    $file.FullName
    FileSizeKB =
    [math]::Round($file.Length/1KB,1)
    LogDate =
    $first.Timestamp.ToString("yyyy-MM-dd")
    TimeStart =
    $first.Timestamp.ToString("HH:mm:ss")
    TimeEnd =
    $last.Timestamp.ToString("HH:mm:ss")
    TotalEntries =
    $Entries.Count
    LevelCounts =
    $levels
    Services =
    $services
}
}
function Get-ErrorSignature {
param(
[string]$Message
)
$sig=$Message
$sig =
$sig -replace
'[0-9a-fA-F]{8}-[0-9a-fA-F-]{27}',
'{guid}'
$sig =
$sig -replace
'\bid\s*[:=]?\s*\d+',
'id {n}'
$sig =
$sig -replace
'Linenumber:\s*\d+',
'Linenumber {n}'
return $sig.Trim()
}
function Group-Errors {
param(
[object]$Entries
)
$groups=@{}
foreach($entry in
$Entries | Where-Object {
    $_.Level -in 'W','E','F'
}
){
$key =
Get-ErrorSignature $entry.Message
if(!$groups.ContainsKey($key)){
    $groups[$key]=[PSCustomObject]@{
        Signature=$key
        Level=$entry.Level
        Count=0
        FirstSeen=$entry.Timestamp
        LastSeen=$entry.Timestamp
        FullMessage=$entry.Message
        Component=$entry.Component
        LatestStackTrace=$entry.StackTrace
    }
}
$item=$groups[$key]
$item.Count++
if($entry.Timestamp -gt $item.LastSeen){
    $item.LastSeen=$entry.Timestamp
    $item.LatestStackTrace=$entry.StackTrace
}
$rank=@{
    W=1
    E=2
    F=3
}
if($rank[$entry.Level] -gt $rank[$item.Level]){
    $item.Level=$entry.Level
}
}
$order=@{
F=0
E=1
W=2
}
@(
    $groups.Values |
    Sort-Object `
    {$order[$_.Level]},
    {- $_.Count}
)
}
# ============================================================
# TEXT FORMAT HELPERS
# ============================================================
function Get-Abbreviation {
param(
[string]$Message,
[int]$MaxLength=65
)
$text=$Message
$text =
$text -replace
'at [A-Za-z]:\\[^\s]+',
''
$text =
$text -replace
'\s+',
' '
$text=$text.Trim()
if($text.Length -le $MaxLength){
    return $text
}
return $text.Substring(0,$MaxLength-3)+"..."
}
# ============================================================
# REPORT FORMAT
# ============================================================
function Format-InfoBlock {
param(
[object]$Info
)
$lines=@()
$lines += ""
$lines += ('=' * 70)
$lines += "  AXM LOG ANALYSIS REPORT"
$lines += ('=' * 70)
$lines += ""
$lines += "  FILE INFORMATION"
$lines += ('  ' + ('-' * 40))
$lines += "  File       : $($Info.FileName)"
$lines += "  Path       : $($Info.FilePath)"
$lines += "  Size       : $($Info.FileSizeKB) KB"
$lines += "  Log date   : $($Info.LogDate)"
$lines += "  Time range : $($Info.TimeStart) -> $($Info.TimeEnd)"
$lines += ""
$lines += "  ENTRY COUNTS"
$lines += ('  ' + ('-' * 40))
$lines += "  Total entries : $($Info.TotalEntries)"
$levelNames=@{
F="Fatal"
E="Error"
W="Warning"
I="Info"
D="Debug"
}
foreach($lvl in 'F','E','W','I','D'){
    if($Info.LevelCounts[$lvl] -gt 0){
        $lines += (
            "  {0,-10}: {1}" -f
            $levelNames[$lvl],
            $Info.LevelCounts[$lvl]
        )
    }
}
if($Info.Services){
    $lines += ""
    $lines += "  COMPONENTS"
    $lines += ('  ' + ('-' * 40))
    foreach($service in $Info.Services | Select-Object -First 10){
        $lines += "  - $service"
    }
}
return $lines
}
function Format-ErrorTable {
param(
[object[]]$Groups
)
$lines=@()
$lines += ""
$lines += "  ERROR / WARNING SUMMARY"
$lines += ('  ' + ('-' * 40))
$lines += ""
if(!$Groups){
    $lines += "  No errors or warnings."
    return $lines
}
$lines += (
"  {0,-5}{1,-10}{2,-55}{3,-10}{4}" -f
"#",
"Level",
"Message",
"Last",
"Count"
)
$lines += ('-' * 100)
$i=0
foreach($g in $Groups){
$i++
$label=switch($g.Level){
    F {"[FATAL]"}
    E {"[ERROR]"}
    W {"[WARN] "}
}
$lines += (
"{0,-5}{1,-10}{2,-55}{3,-10}{4}" -f
$i,
$label,
(Get-Abbreviation $g.FullMessage),
$g.LastSeen.ToString("HH:mm:ss"),
$g.Count
)
}
return $lines
}
# ============================================================
# COLORED OUTPUT
# ============================================================
function Write-AXMHeader {
Write-Host ""
Write-Host ('=' * 70) -ForegroundColor DarkGray
Write-Host "                 AXM LOG CONDENSER" -ForegroundColor Cyan
Write-Host "                       v3.1.0" -ForegroundColor DarkCyan
Write-Host ('=' * 70) -ForegroundColor DarkGray
Write-Host ""
Write-Host " AXM Diagnostics Tool" -ForegroundColor Yellow
Write-Host " Parses AXM Plus logs and condenses errors, warnings and traces."
Write-Host ""
}
function Write-AXMReport {
param(
[string[]]$Lines
)
foreach($line in $Lines){
switch -Regex ($line){
"AXM LOG ANALYSIS REPORT" {
    Write-Host $line -ForegroundColor Cyan
    break
}
"FILE INFORMATION|ENTRY COUNTS|COMPONENTS|ERROR / WARNING SUMMARY" {
    Write-Host $line -ForegroundColor Cyan
    break
}
"\[FATAL\]|Fatal" {
    Write-Host $line -ForegroundColor Red
    break
}
"\[ERROR\]|Error" {
    Write-Host $line -ForegroundColor Red
    break
}
"\[WARN|Warning" {
    Write-Host $line -ForegroundColor Yellow
    break
}
"^=+|^-+" {
    Write-Host $line -ForegroundColor DarkGray
    break
}
default {
    Write-Host $line -ForegroundColor Gray
}
}
}
}
# ============================================================
# STACK TRACE VIEWER
# ============================================================
function Format-StackTraceBlock {
param(
[object[]]$Groups,
[int]$Selection
)
$g=$Groups[$Selection-1]
$lines=@()
$lines += ""
$lines += ('=' * 70)
$lines += " STACK TRACE #$Selection"
$lines += ('-' * 40)
$lines += " Level     : $($g.Level)"
$lines += " Component : $($g.Component)"
$lines += " Count     : $($g.Count)"
$lines += " First     : $($g.FirstSeen)"
$lines += " Last      : $($g.LastSeen)"
$lines += ""
$lines += " Message:"
$lines += $g.FullMessage
$lines += ""
if($g.LatestStackTrace.Count -gt 0){
    $lines += " Stack trace:"
    $lines += ('-' * 40)
    foreach($trace in $g.LatestStackTrace){
        $lines += $trace
    }
}
else{
    $lines += " No stack trace available."
}
$lines += ('=' * 70)
return $lines
}
# ============================================================
# SAVE REPORT
# ============================================================
function Save-Report {
param(
[string[]]$ReportLines,
[string]$LogPath,
[string]$ScriptDir
)
$name =
[IO.Path]::GetFileNameWithoutExtension($LogPath)
$out =
Join-Path $ScriptDir (
"$name`_report_$(Get-Date -Format yyyyMMdd_HHmmss).txt"
)
$ReportLines |
Set-Content $out -Encoding UTF8
Write-Host ""
Write-Host "Report saved:" -ForegroundColor Green
Write-Host $out -ForegroundColor Cyan
Write-Host ""
}
# ============================================================
# INTERACTIVE VIEWER
# ============================================================
function Start-InteractiveViewer {
param(
[object[]]$Groups,
[string[]]$ReportLines,
[string]$LogPath,
[string]$ScriptDir
)
$savedStack=@()
while($true){
Write-Host ""
Write-Host "Commands" -ForegroundColor Cyan
Write-Host ('-' * 32) -ForegroundColor DarkGray
Write-Host "(1-n) View stack trace" -ForegroundColor Gray
Write-Host "S     Save report" -ForegroundColor Green
Write-Host "Enter Exit" -ForegroundColor DarkGray
Write-Host ""
$cmd =
Read-Host "Command"
if([string]::IsNullOrWhiteSpace($cmd)){
    Write-Host "Exiting." -ForegroundColor DarkGray
    break
}
if($cmd -ieq "S"){
    Save-Report `
    -ReportLines ($ReportLines + $savedStack) `
    -LogPath $LogPath `
    -ScriptDir $ScriptDir
    continue
}
if($cmd -match '^\d+$'){
    $index=[int]$cmd
    if($index -ge 1 -and $index -le $Groups.Count){
        $trace =
        Format-StackTraceBlock `
        -Groups $Groups `
        -Selection $index
        Write-AXMReport -Lines $trace
        $savedStack += $trace
    }
    else{
        Write-Host (
        "Invalid selection. Choose 1-{0}" -f $Groups.Count
        ) -ForegroundColor Yellow
    }
    continue
}
Write-Host "Unknown command." -ForegroundColor Yellow
}
}
# ============================================================
# MAIN EXECUTION
# ============================================================
try{
if(-not $Path){
    $Path =
    Select-LogFromFolder `
    -LogDirectory $LogDir
}
Write-Host ""
Write-Host "Loading log..." -ForegroundColor Cyan
$entries =
Get-AXMLogEntries `
-LogPath $Path
Write-Host (
"{0} entries loaded." -f $entries.Count
) -ForegroundColor Green
Write-Host ""s +=
$info =
Get-InfoBlock `
-Entries $entries `
-LogPath $Path
$errors =
@(Group-Errors $entries)
$report =
@(
    Format-InfoBlock $info
    Format-ErrorTable $errors
)
Write-AXMHeader
Write-AXMReport `
-Lines $report
$scriptDir =
Split-Path `
-Parent `
$MyInvocation.MyCommand.Path
if($Save){
    Save-Report `
    -ReportLines $report `
    -LogPath $Path `
    -ScriptDir $scriptDir
}
Start-InteractiveViewer `
-Groups $errors `
-ReportLines $report `
-LogPath $Path `
-ScriptDir $scriptDir
}
catch{
Write-Host ""
Write-Host "AXM Log Condenser failed:" -ForegroundColor Red
Write-Host $_.Exception.Message -ForegroundColor Yellow
Write-Host ""
Write-Host "Press Enter to close."
Read-Host
exit 1
}