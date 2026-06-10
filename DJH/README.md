The user wants an updated README.md that covers all the scripts we've built, without emojis or fancy formatting, just clean Git-ready markdown.
```markdown # CSV Filter & Delta Compare Tool

Delivered AS IS by SimonsVoss. This is not a standard product and is therefore not covered by normal support terms. SimonsVoss takes no responsibility for any issues, data loss, or other consequences that may arise from the use of this tool. Use at your own risk.
Requirements

    Windows OS
    PowerShell 5.0 or higher
    Input files must be placed in the same folder as the scripts

File Structure

Your Folder
 ├── run.bat
 ├── master_filter.ps1
 ├── Users_export.csv
 └── LSM_export.csv

How To Use

    Place all files in the same folder
    Double-click run.bat to run the tool
    Output files will be saved in the same folder

Note: Always run the tool via run.bat - never run the .ps1 file directly.
Workflow

The tool runs three steps in sequence.
Step 1 - Filter Users_export.csv

Reads Users_export.csv and removes all rows where the UserGroupText column does not contain one of the following values:

Elever m/sk:hjem
Elever

All . (dots) are replaced with : (colons) across all columns in the remaining rows.

Output: Users_export_filtered.csv
Step 2 - Filter LSM_export.csv

Reads LSM_export.csv and removes all rows where the TransponderGroup.Name column does not contain one of the following values:

Elever m/sk:hjem
Elever

No dot replacement is performed on LSM data as it is considered valid as-is.

Output: Used internally for Step 3 only - not saved to disk.
Step 3 - Delta Comparison

Compares Person.PersonalNumber from the filtered LSM data against UserId from Users_export_filtered.csv.

Returns only rows from LSM where Person.PersonalNumber does not exist as a UserId in the filtered Users data.

Output: delta_export.csv
Output Files

Your Folder
 ├── Users_export_filtered.csv         <- Step 1 output
 ├── delta_export.csv                  <- Step 3 output
 └── filter_log_yyyy-MM-dd_HH-mm-ss.txt <- Log file per run

Logging

Each run generates a new log file with a timestamp in the filename. The log contains timestamped entries for all steps including row counts and file paths.

Example log entry:

[2024-01-15 08:30:01] Original antal rækker:  1500
[2024-01-15 08:30:01] Beholdte rækker:        342
[2024-01-15 08:30:01] Slettede rækker:        1158

Previous logs are never overwritten.
Configuration
Change Delimiter

If your CSV uses , instead of ;, open master_filter.ps1 and change:

Import-Csv -Path $inputFile -Delimiter ";"
# To:
Import-Csv -Path $inputFile -Delimiter ","

Change Allowed Filter Values

To add or remove allowed values, open master_filter.ps1 and edit:

$allowedValues = @("Elever m/sk:hjem", "Elever")

Troubleshooting
Problem	Solution
Script won't run	Run via run.bat - never run the .ps1 file directly
File not found error	Make sure input CSV files are in the same folder as the scripts
Wrong delimiter error	Check if your CSV uses ; or , and update master_filter.ps1
Output file is empty	Verify that column names in the CSV match exactly what the script expects
Encoding issues	Make sure input CSV files are saved as UTF-8
License

Copyright SimonsVoss. This project is delivered AS IS and is not a standard product. It is not covered by normal SimonsVoss support terms. No warranties or guarantees of any kind are provided.