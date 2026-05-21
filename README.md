# PrintCleaner

PrintCleaner ist ein interaktives PowerShell-Script zum Bereinigen der Druckerumgebung auf Windows-11-Clients.

Das Script entfernt lokale Drucker, verbundene Netzwerkdrucker, nicht mehr benoetigte Druckertreiber und unbenutzte Druckerports. Vor jeder Aenderung wird ein vollstaendiges Backup/Inventar erstellt und jede Aktion wird protokolliert.

## Zielsystem

- Windows 11 Client, vorgesehen fuer Windows 11 25H2
- PowerShell 5.1 oder PowerShell 7
- lokale Administratorrechte

Das Script ist nicht fuer den Einsatz auf einem Windows Print Server gedacht.

## Was wird entfernt?

PrintCleaner entfernt standardmaessig:

- lokale Drucker
- verbundene Netzwerkdrucker
- nicht geschuetzte Druckertreiber
- eindeutig zugehoerige Drittanbieter-Treiberpakete aus dem Driver Store, sofern sie als `oem*.inf` erkannt werden
- unbenutzte Drittanbieter-Ports, zum Beispiel `IP_`, `WSD-`, `USB`, `COMx:` und `LPTx:`

## Was bleibt bestehen?

Folgende Windows-/Office-Standarddrucker werden geschuetzt und bleiben bestehen:

- `Microsoft Print to PDF`
- `Microsoft XPS Document Writer`
- `Fax`
- OneNote-Drucker

Auch zugehoerige geschuetzte Treiber und Ports werden nicht entfernt.

## Backup und Log

Alle Sicherungen und Logs werden unter folgendem Pfad erstellt:

```powershell
C:\temp\PrintCleaner
```

Pro Ausfuehrung erstellt das Script einen neuen Unterordner mit Zeitstempel, zum Beispiel:

```powershell
C:\temp\PrintCleaner\20260521-143000
```

Darin liegen unter anderem:

- `PrintCleaner.log`
- `transcript.log`
- `printers.csv`
- `drivers.csv`
- `ports.csv`
- `win32_printer.csv`
- `win32_printerdriver.csv`
- `pnputil_enum-drivers.txt`
- `after\` mit dem Inventar nach der Bereinigung

## Ausfuehrung

PowerShell als Administrator starten und in den Ordner wechseln, in dem `PrinterCleaner.ps1` liegt.

Falls die Ausfuehrungsrichtlinie das Script blockiert, kann sie nur fuer die aktuelle PowerShell-Sitzung gelockert werden:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
```

Script interaktiv starten:

```powershell
.\PrinterCleaner.ps1
```

Das Script zeigt vor dem Entfernen an:

- welche Drucker geschuetzt bleiben
- welche Drucker entfernt werden
- wo Backup und Log gespeichert werden

Zum Fortfahren muss exakt folgender Text eingegeben werden:

```text
ENTFERNEN
```

Jede andere Eingabe bricht den Vorgang ab.

## Testlauf mit WhatIf

Ein Testlauf ohne echte Aenderungen ist moeglich:

```powershell
.\PrinterCleaner.ps1 -WhatIf
```

Dabei wird angezeigt, welche Aktionen ausgefuehrt wuerden. Inventar und Logs werden trotzdem erstellt.

## Automatischer Modus

Mit `-Force` wird die interaktive Texteingabe uebersprungen:

```powershell
.\PrinterCleaner.ps1 -Force
```

Dieser Modus sollte nur verwendet werden, wenn der Ablauf vorher mit `-WhatIf` geprueft wurde.

## Ablauf im Detail

1. Adminrechte pruefen
2. Backup- und Logordner erstellen
3. aktuelles Drucker-, Treiber- und Port-Inventar exportieren
4. geschuetzte und zu entfernende Drucker anzeigen
5. interaktive Bestaetigung abfragen
6. nicht geschuetzte Drucker entfernen
7. Print Spooler stoppen und starten
8. nicht geschuetzte Druckertreiber entfernen
9. zugehoerige Drittanbieter-Treiberpakete aus dem Driver Store entfernen
10. unbenutzte Drittanbieter-Ports entfernen
11. Print Spooler erneut stoppen und starten
12. Nachher-Inventar exportieren

## Wichtige Hinweise

- Das Script muss mit administrativen Rechten ausgefuehrt werden.
- Entfernte Drucker muessen bei Bedarf neu installiert oder erneut verbunden werden.
- Das Script schuetzt Windows-/Office-Standarddrucker anhand ihrer Namen.
- Treiberpakete aus dem Driver Store werden nur entfernt, wenn sie eindeutig als Drittanbieter-`oem*.inf` erkannt werden.
- Wenn ein Treiber noch durch Windows blockiert ist, wird der Fehler geloggt und das Script laeuft weiter.
- Vor dem produktiven Einsatz sollte immer ein Testlauf mit `-WhatIf` durchgefuehrt werden.

## Dateien

- `PrinterCleaner.ps1` - Hauptscript
- `README.md` - diese Anleitung
