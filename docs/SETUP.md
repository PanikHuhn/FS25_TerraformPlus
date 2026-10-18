# Erste Schritte: Git, LS25 und Terraform Plus

## 1. Repository lokal entpacken

Das `FS25_TerraformPlus`-Verzeichnis ist der **Quellcodeordner**. Darin liegen `modDesc.xml`, `icon.png` und `scripts/` direkt.

## 2. Mod testen

PowerShell im Projektordner:

```powershell
.\tools\install.ps1
```

Wenn die PowerShell-Skriptausführung deaktiviert ist, **manuell** nur `modDesc.xml`, `icon.png` und `scripts` in `Dokumente/My Games/FarmingSimulator2025/mods/FS25_TerraformPlus/` kopieren.

## 3. Spiel starten und aktivieren

Im Modauswahlfenster **Terraform Plus** für einen separaten Testspielstand aktivieren. Die frühe Version verändert noch nichts.

## 4. Debugging

In der `log.txt` (neben dem `mods`-Ordner) nach `Terraform Plus` suchen. Wenn der Mod nicht geladen wird, nach `Error` und `Warning` suchen. Spielversion mit `descVersion` vergleichen; für den Starter ist `105` gewählt, nicht als Behauptung über die neueste Schema-Version.

## 5. GitHub

Git verwaltet Quellcode, GitHub speichert das Repository. Keine Savegames, Spiel-Assets, Lizenzschlüssel oder Log-Dateien hochladen. `.gitignore` schützt vor versehentlichen Uploads, `git status` vor jedem Commit kontrollieren.

## 6. Nächstes Feature

Zunächst nur **lesenden** Geländehöhen-Test erstellen. Die dokumentierte Funktion heißt `getTerrainHeightAtWorldPos` und benötigt die gültige Terrain-ID sowie X/Y/Z-Koordinaten. Änderungen via `setTerrainHeightAtWorldPos` erst auf einer Testkarte, nachdem der Savegame-Backup- und Undo-Plan steht.
