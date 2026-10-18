# Terraform Plus (FS25)

Ein geplanter Terrain- und Landschaftseditor für **Farming Simulator 25**, inspiriert von der Bedienung in *Cities: Skylines II*.

> **Status: v0.0.1.0 – Bootstrap.** Dieser Stand meldet nur das Laden im `log.txt`. Er verändert **kein** Gelände.

## Geplanter Funktionsumfang

- Terraforming: Anheben, Absenken, Planieren, Glätten und Gefälle
- Multi-Texture-Painting und Vegetationsmischer (Gras, Blumen, Bäume)
- Exakte Höhen, Böschungen, intelligente Straßen und Vorschau / Undo

## Voraussetzungen

- Farming Simulator 25 für Windows (PC)
- Visual Studio Code und Git
- Optional: GIANTS Editor 10, GIANTS Farming Simulator IDE Support

## Installation für den ersten Test

1. Repository als Arbeitsordner `FS25_TerraformPlus` entpacken oder klonen.
2. In `modDesc.xml` `YOUR_GITHUB_NAME` durch deinen Autorennamen ersetzen.
3. PowerShell im Projektordner öffnen und ausführen:

   ```powershell
   .\tools\install.ps1
   ```

   Falls Windows das Ausführen von Skripten blockiert, nicht dauerhaft die Sicherheitsrichtlinien ändern. Stattdessen die drei Mod-Bestandteile `modDesc.xml`, `icon.png` und `scripts` manuell nach `Dokumente\My Games\FarmingSimulator2025\mods\FS25_TerraformPlus` kopieren.
4. LS25 neu starten, Testspielstand öffnen und **Terraform Plus** bei der Modauswahl aktivieren.
5. Nach dem Laden in `Dokumente\My Games\FarmingSimulator2025\log.txt` suchen nach:

   ```text
   [Terraform Plus] loadMap: Mod erfolgreich geladen (v0.0.1.0)
   ```

Der korrekte Dokumente-Ordner kann durch OneDrive umgeleitet sein. `install.ps1` fragt den Windows-Dokumentepfad ab. Bei Microsoft-Store-Editionen oder geändertem Mods-Verzeichnis manuell anpassen.

## Release ZIP erzeugen

```powershell
.\tools\package.ps1
```

Ausgabe: `dist/FS25_TerraformPlus.zip` (der ZIP-Stamm enthält direkt `modDesc.xml`). Die ZIP ist **nicht** das GitHub-Quellcodepaket.

## GitHub-Workflow

Vor dem ersten Push ein leeres Repository namens `FS25_TerraformPlus` auf GitHub anlegen (ohne initiales README, `.gitignore` oder Lizenz). Danach im Projektordner:

```powershell
git init -b main
git add .
git commit -m "chore: initialize Terraform Plus mod"
git remote add origin https://github.com/DEIN_USERNAME/FS25_TerraformPlus.git
git push -u origin main
```

`DEIN_USERNAME` ersetzen. Falls Git noch keinen Commit-Namen kennt: `git config --global user.name "DEIN NAME"` und `git config --global user.email "DEINE_GITHUB_EMAIL"` setzen. Anmeldung erfolgt über Git Credential Manager / Browser, **kein** Passwort oder Token im Code speichern.

## Architekturprinzipien

- GIANTS-API-Zugriffe später in dedizierten Adaptern statt überall verstreut.
- Alle Geländeoperationen erst berechnen, dann prüfen, danach schreiben.
- Änderungen nur auf einer Testkarte und mit Sicherung bearbeiten.
- Multiplayer erst nach einer getesteten Singleplayer-Version angeben.

## Rechte

Bis zu einer bewussten Lizenzentscheidung ist diesem Repository **keine** Open-Source-Lizenz beigelegt. Bitte keine GIANTS-Spielassets oder fremden Mod-Code ohne die erforderlichen Rechte einchecken.

## Dokumentation

Siehe [`docs/ROADMAP.md`](docs/ROADMAP.md) und [`docs/SETUP.md`](docs/SETUP.md).
