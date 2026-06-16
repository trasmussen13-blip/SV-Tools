# README.md

## Beschreibung

Dieses PowerShell-Skript löscht bestimmte LockSysMgr-Datenbankdateien sowie ein zugehöriges SQL Server LocalDB-Instanzverzeichnis. Es ist für die Ausführung mit Administratorrechten vorgesehen und fragt vor dem Löschen ab, welche Software-Edition bearbeitet werden soll.

Unterstützte Editionen:

- Lite
- Classic
- Plus

## Funktionen

Das Skript führt die folgenden Schritte aus:

1. Prüft, ob es mit Administratorrechten gestartet wurde.
2. Fragt die gewünschte Software-Edition ab.
3. Löscht die zur Edition gehörenden Datenbankdateien:
   - `main_<edition>.mdf`
   - `main_<edition>_log.ldf`
4. Prüft, welches SQL Server LocalDB-Verzeichnis vorhanden ist:
   - `C:\Windows\SysWOW64\config\systemprofile\AppData\Local\Microsoft\Microsoft SQL Server Local DB\Instances\MSSqlLocalDB\`
   - `C:\Windows\System32\config\systemprofile\AppData\Local\Microsoft\Microsoft SQL Server Local DB\Instances\MSSqlLocalDB\`
5. Versucht, das gefundene Verzeichnis zu löschen.
6. Falls das Löschen fehlschlägt, wird versucht, `sqlserver.exe` zu beenden.
7. Danach wird das Löschen des Verzeichnisses erneut versucht.

## Voraussetzungen

- Windows
- PowerShell
- Administratorrechte

## Wichtige Hinweise

- Das Skript löscht Dateien und Verzeichnisse dauerhaft.
- Vor der Ausführung sollte sichergestellt werden, dass keine wichtigen Daten mehr benötigt werden.
- Das Skript ist nur für Systeme geeignet, auf denen die genannten Pfade und Dateien tatsächlich verwendet werden.
- Falls Prozesse oder Dienste auf die Dateien zugreifen, kann das Löschen zunächst fehlschlagen.

## Verwendete Pfade

Datenbankdateien:

`C:\ProgramData\SimonsVoss\LockSysMgr\config`

Mögliche LocalDB-Verzeichnisse:

`C:\Windows\SysWOW64\config\systemprofile\AppData\Local\Microsoft\Microsoft SQL Server Local DB\Instances\MSSqlLocalDB\`

`C:\Windows\System32\config\systemprofile\AppData\Local\Microsoft\Microsoft SQL Server Local DB\Instances\MSSqlLocalDB\`

## Verwendung

1. PowerShell als Administrator öffnen.
2. Das Skript ausführen.
3. Bei der Abfrage eine der folgenden Editionen eingeben:
   - `Lite`
   - `Classic`
   - `Plus`
4. Das Skript verarbeitet anschließend die zugehörigen Dateien und Verzeichnisse.

## Beispielablauf

- Start mit Administratorrechten
- Eingabe der Edition, zum Beispiel `Classic`
- Löschen von:
  - `C:\ProgramData\SimonsVoss\LockSysMgr\config\main_classic.mdf`
  - `C:\ProgramData\SimonsVoss\LockSysMgr\config\main_classic_log.ldf`
- Ermitteln des vorhandenen LocalDB-Verzeichnisses
- Löschen des Verzeichnisses
- Falls notwendig: Beenden von `sqlserver.exe` und erneuter Löschversuch

## Mögliche Fehlermeldungen

- "Dieses Skript muss als Administrator ausgeführt werden."
  - Das Skript wurde ohne erhöhte Rechte gestartet.

- "Datei nicht gefunden"
  - Die erwartete Datei existiert nicht im Zielpfad.

- "Kein passendes Verzeichnis gefunden. Skript wird beendet."
  - Keines der beiden vorgesehenen LocalDB-Verzeichnisse wurde gefunden.

- "Fehler beim Löschen des Verzeichnisses"
  - Das Verzeichnis ist möglicherweise gesperrt oder wird noch verwendet.

- "Verzeichnis konnte nicht gelöscht werden."
  - Auch nach dem Beenden von `sqlserver.exe` war das Löschen nicht erfolgreich.

## Sicherheit

Vor der Verwendung sollte geprüft werden, ob:

- die richtigen Dateien betroffen sind
- keine Sicherung benötigt wird
- keine produktiven Daten versehentlich entfernt werden

## Lizenz

Bei Bedarf ergänzen.