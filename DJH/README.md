#                                                                               
                                                                                
   ██████╗ ██╗███╗   ███╗ ██████╗ ███╗   ██╗███████╗                          
   ██╔════╝ ██║████╗ ████║██╔═══██╗████╗  ██║██╔════╝                          
   ███████╗ ██║██╔████╔██║██║   ██║██╔██╗ ██║███████╗                          
   ╚════██║ ██║██║╚██╔╝██║██║   ██║██║╚██╗██║╚════██║                          
   ███████║ ██║██║ ╚═╝ ██║╚██████╔╝██║ ╚████║███████║                          
   ╚══════╝ ╚═╝╚═╝     ╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚══════╝                          
                                                                                
  ════════════════════════════════════════════════════════                      
  ════════════════════════════════════════════════════════                      
  ════════════════════════════════════════════════════════                      
                                                                                
        ██╗   ██╗ ██████╗ ███████╗███████╗                                     
        ██║   ██║██╔═══██╗██╔════╝██╔════╝                                     
        ██║   ██║██║   ██║███████╗███████╗                                     
        ╚██╗ ██╔╝██║   ██║╚════██║╚════██║                                     
         ╚████╔╝ ╚██████╔╝███████║███████║                                     
          ╚═══╝   ╚═════╝ ╚══════╝╚══════╝                                     
                                                                                
      t e c h n o l o g i e s                                                  
                                                                                                                                
#                                                                               
```markdown
# CSV Filter & Delta Compare Tool

Delivered AS IS by SimonsVoss.
This is not a standard product and is therefore not covered by normal support terms.
SimonsVoss takes no responsibility for any issues, data loss, or other consequences
that may arise from the use of this tool. Use at your own risk.

---

## Requirements

- Windows OS
- PowerShell 5.0 or higher
- Input files must be placed in the same folder as the scripts

---

## File Structure

```
Your Folder
 ├── run.bat
 ├── master_filter.ps1
 ├── Users_export.csv
 └── LSM_export.csv
```

---

## How To Use

1. Place all files in the same folder
2. Double-click `run.bat` to run the tool
3. Output files will be saved in the same folder

Note: Always run the tool via `run.bat` - never run the `.ps1` file directly.

---

## Workflow

The tool runs three steps in sequence.

### Step 1 - Filter Users_export.csv

Reads `Users_export.csv` and removes all rows where the `UserGroupText` column
does not contain one of the following values:

```
Elever m/sk:hjem
Elever
```

After filtering the following operations are performed on the remaining rows:

**Name correction**
If the lastname column is empty but the firstname column has a value,
the firstname value is moved to the lastname column and firstname is cleared.
This handles vendors and other users who may only have a single name registered.
The number of corrected rows is written to the log.

**Dot replacement**
All `.` (dots) are replaced with `:` (colons) across all columns in the
remaining rows.

Output: `Users_export_filtered.csv`

### Step 2 - Filter LSM_export.csv

Reads `LSM_export.csv` and removes all rows where the `TransponderGroup.Name`
column does not contain one of the following values:

```
Elever m/sk:hjem
Elever
```

No dot replacement is performed on LSM data as it is considered valid as-is.

Output: Used internally for Step 3 only - not saved to disk.

### Step 3 - Delta Comparison

Compares `Person.PersonalNumber` from the filtered LSM data against `UserId`
from `Users_export_filtered.csv`.

Returns only rows from LSM where `Person.PersonalNumber` does not exist
as a `UserId` in the filtered Users data.

**Blast Radius Safety**
Before saving the delta file, the tool calculates the delta row count as a
percentage of the filtered LSM row count. If this percentage exceeds the
configured threshold (default 20%), the process stops immediately, no delta
file is saved, and an error is written to the log.

This safety check exists because the delta file is used to mark users for
deletion in LSM. An unexpectedly large delta could indicate a data issue
and should be reviewed manually before proceeding.

Output: `delta_export.csv` (only saved if blast radius check passes)

---

## Output Files

```
Your Folder
 ├── Users_export_filtered.csv    <- Step 1 output
 ├── delta_export.csv             <- Step 3 output (if blast radius check passes)
 └── filter_log.txt               <- Appended log file
```

---

## Logging

All runs are appended to a single `filter_log.txt` file.
The log contains timestamped entries for all steps including row counts,
name corrections, dot replacements, blast radius calculations and file paths.
Previous runs are never overwritten.

Each log entry follows this format:
```
[yyyy-MM-dd HH:mm:ss][LEVEL] Message
```

Log levels:

| Level | Usage                                    |
|-------|------------------------------------------|
| INFO  | Normal process messages                  |
| ERROR | Failures, missing files, blast radius trigger |

Example log output - normal run:
```
[2024-01-15 08:30:00][INFO] ========================================
[2024-01-15 08:30:00][INFO]  CSV Filter og Delta Compare Tool
[2024-01-15 08:30:00][INFO]  Leveret AS IS af SimonsVoss
[2024-01-15 08:30:00][INFO] ========================================
[2024-01-15 08:30:01][INFO] Original antal rækker:  1500
[2024-01-15 08:30:01][INFO] Beholdte rækker:        342
[2024-01-15 08:30:01][INFO] Slettede rækker:        1158
[2024-01-15 08:30:01][INFO] Rækker hvor firstname flyttet til lastname: 5
[2024-01-15 08:30:01][INFO] Alle '.' erstattet med ':'
[2024-01-15 08:30:02][INFO] Delta procent af LSM:      8%
[2024-01-15 08:30:02][INFO] Blast radius kontrol OK - delta er inden for graensen
```

Example log output - blast radius triggered:
```
[2024-01-15 08:30:02][INFO]  Delta procent af LSM:      24%
[2024-01-15 08:30:02][INFO]  Blast radius graense:      20%
[2024-01-15 08:30:02][ERROR] ========================================
[2024-01-15 08:30:02][ERROR]  BLAST RADIUS SIKKERHED UDLOST!
[2024-01-15 08:30:02][ERROR]  Delta (24%) overstiger den maksimale graense paa 20% af LSM data!
[2024-01-15 08:30:02][ERROR]  delta_export.csv er IKKE blevet gemt!
[2024-01-15 08:30:02][ERROR]  Gennemgaa data manuelt foer fortsaettelse!
[2024-01-15 08:30:02][ERROR] ========================================
```

---

## Configuration

All configuration is located at the top of `master_filter.ps1`.
Do not edit anything below the configuration block unless you know what you are doing.

| Variable         | Default                      | Description                                                             |
|------------------|------------------------------|-------------------------------------------------------------------------|
| `$usersInputFile`  | `Users_export.csv`           | Input file exported from the Users system                               |
| `$usersOutputFile` | `Users_export_filtered.csv`  | Output file after filtering and dot replacement                         |
| `$lsmInputFile`    | `LSM_export.csv`             | Input file exported from the LSM system                                 |
| `$deltaFile`       | `delta_export.csv`           | Output file for records present in LSM but not in Users                 |
| `$logFile`         | `filter_log.txt`             | Log file - all runs are appended                                        |
| `$allowedValues`   | `Elever m/sk:hjem, Elever`   | Allowed values in filter columns - all other rows are removed           |
| `$blastRadiusPct`  | `20`                         | Max allowed delta as a percentage of filtered LSM rows                  |
| `$delimiter`       | `;`                          | CSV delimiter - use `;` or `,` depending on your files                  |
| `$encoding`        | `UTF8`                       | Character encoding for all CSV files                                    |
| `$colFirstName`    | `Firstname`                  | Firstname column name in Users_export.csv                               |
| `$colLastName`     | `Lastname`                   | Lastname column name - if empty, firstname value is moved here          |

---

## Troubleshooting

| Problem                  | Solution                                                                   |
|--------------------------|----------------------------------------------------------------------------|
| Script won't run         | Run via `run.bat` - never run the `.ps1` file directly                     |
| File not found error     | Make sure input CSV files are in the same folder as the scripts            |
| Wrong delimiter error    | Check if your CSV uses `;` or `,` and update `$delimiter` in config        |
| Output file is empty     | Verify that column names in the CSV match the column names in config       |
| Encoding issues          | Make sure input CSV files are saved as UTF-8                               |
| Blast radius triggered   | Review input data manually - if the delta looks correct increase `$blastRadiusPct` |
| Name fix not working     | Verify `$colFirstName` and `$colLastName` match the exact column names in the CSV |

---

## License

Copyright SimonsVoss. This project is delivered AS IS and is not a standard product.
It is not covered by normal SimonsVoss support terms.
No warranties or guarantees of any kind are provided.
```