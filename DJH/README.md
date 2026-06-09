
```markdown
# CSV Filter Tool

A simple tool that filters a CSV file based on specific values in the `UserGroupText` 
column, and replaces all `.` with `:` in the remaining data.

---

## ⚠️ Disclaimer

> **This project is delivered AS IS by SimonsVoss.**
> 
> This is not a standard product and is therefore **not covered by normal support terms.**
> SimonsVoss takes no responsibility for any issues, data loss, or other consequences
> that may arise from the use of this tool. Use at your own risk.

---

## 📋 Requirements

- Windows OS
- PowerShell 5.0 or higher
- The `Users_export.csv` file must be in the same folder as the scripts

---

## 📁 File Structure

```
📁 Your Folder
 ├── run.bat
 ├── filter_csv.ps1
 └── Users_export.csv
```

---

## 🚀 How To Use

1. Place all files in the **same folder**
2. Double-click **`run.bat`** to run the tool
3. The filtered file will be saved as **`Users_export_filtered.csv`** in the same folder

---

## ⚙️ What It Does

### Filtering
Scans `Users_export.csv` and **removes all rows** that do not have one of the 
following values in the `UserGroupText` column:

| Kept Values        |
|--------------------|
| `Elever m/sk:hjem` |
| `Elever`           |

### Text Replacement
Replaces **all** `.` (dots) with `:` (colons) across **all columns** in the 
remaining rows.

### Output
Saves the filtered and modified data to a new file:
```
Users_export_filtered.csv
```
The original `Users_export.csv` file is **not modified**.

---

## 📊 Output Example

When the script runs, it will display statistics like this:

```
----------------------------------------
Original antal rækker:  1500
Beholdte rækker:        342
Slettede rækker:        1158
Alle '.' er erstattet med ':'
----------------------------------------
Filtreret fil gemt som: Users_export_filtered.csv
```

---

## 🔧 Configuration

### Change Delimiter
If your CSV uses `,` instead of `;`, open `filter_csv.ps1` and change:
```powershell
Import-Csv -Path $inputFile -Delimiter ";"
# To:
Import-Csv -Path $inputFile -Delimiter ","
```

### Change Allowed Values
To add or remove allowed values in `UserGroupText`, open `filter_csv.ps1` and edit:
```powershell
$allowedValues = @("Elever m/sk:hjem", "Elever")
```

### Replace in Specific Column Only
To only replace `.` with `:` in a specific column, open `filter_csv.ps1` and 
replace the replacement block with:
```powershell
$row.UserGroupText = $row.UserGroupText -replace '\.', ':'
```

### Overwrite Original File
To overwrite the original file instead of creating a new one, open `filter_csv.ps1` 
and change:
```powershell
$outputFile = "Users_export_filtered.csv"
# To:
$outputFile = "Users_export.csv"
```

---

## ❗ Troubleshooting

| Problem | Solution |
|--------|----------|
| Script won't run | Make sure all files are in the same folder |
| "File not found" error | Make sure `Users_export.csv` is in the same folder |
| Wrong delimiter error | Check if your CSV uses `;` or `,` and update `filter_csv.ps1` |
| Output file is empty | Check that `UserGroupText` column name matches exactly in your CSV |
| Encoding issues | Make sure the CSV is saved as `UTF-8` |

---

## 📄 License

&copy; SimonsVoss. This project is delivered **AS IS** and is not a standard product.
It is not covered by normal SimonsVoss support terms. No warranties or guarantees 
of any kind are provided.
```