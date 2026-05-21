<#
.SYNOPSIS
    Entfernt nicht geschuetzte Drucker, Druckertreiber und unbenutzte Ports auf Windows 11 Clients.

.DESCRIPTION
    Dieses Script ist als interaktiver Cleaner fuer Windows 11 Clients gedacht.
    Es erstellt vorab ein vollstaendiges Inventar unter C:\temp\PrintCleaner,
    protokolliert alle Aktionen und entfernt anschliessend:

    - alle lokalen und verbundenen Netzwerkdrucker, ausser Windows-/Office-Standarddrucker
    - alle nicht geschuetzten Druckertreiber
    - unbenutzte Drittanbieter-Ports

    Geschuetzt bleiben standardmaessig:
    - Microsoft Print to PDF
    - Microsoft XPS Document Writer
    - Fax
    - OneNote-Drucker

.NOTES
    Muss mit administrativen Rechten ausgefuehrt werden.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
param(
    [string]$BackupRoot = 'C:\temp\PrintCleaner',

    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:ShouldProcessContext = $PSCmdlet

$protectedPrinterNamePatterns = @(
    '^Microsoft Print to PDF$',
    '^Microsoft XPS Document Writer$',
    '^Fax$',
    'OneNote'
)

$protectedDriverNamePatterns = @(
    '^Microsoft Print To PDF$',
    '^Microsoft XPS Document Writer',
    '^Fax$',
    'OneNote',
    '^Microsoft enhanced Point and Print',
    '^Remote Desktop Easy Print'
)

$protectedPortNamePatterns = @(
    '^PORTPROMPT:$',
    '^FILE:$',
    '^nul:$',
    '^SHRFAX:$',
    '^TS\d+:',
    '^Microsoft\.Office\.OneNote',
    '^OneNote'
)

function Test-IsAdministrator {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($currentIdentity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-NameMatchesPattern {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string[]]$Patterns
    )

    foreach ($pattern in $Patterns) {
        if ($Name -match $pattern) {
            return $true
        }
    }

    return $false
}

function New-OutputFolder {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root
    )

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $folder = Join-Path -Path $Root -ChildPath $timestamp
    New-Item -Path $folder -ItemType Directory -Force | Out-Null
    return $folder
}

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet('INFO', 'WARN', 'ERROR', 'OK')]
        [string]$Level = 'INFO'
    )

    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Write-Host $line
    Add-Content -Path $script:LogFile -Value $line -Encoding UTF8
}

function Export-Inventory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OutputFolder
    )

    Write-Log "Erstelle Backup/Inventar in '$OutputFolder'."
    New-Item -Path $OutputFolder -ItemType Directory -Force | Out-Null

    $printers = Get-Printer -ErrorAction SilentlyContinue
    $drivers = Get-PrinterDriver -ErrorAction SilentlyContinue
    $ports = Get-PrinterPort -ErrorAction SilentlyContinue
    $printerWmi = Get-CimInstance -ClassName Win32_Printer -ErrorAction SilentlyContinue
    $driverWmi = Get-CimInstance -ClassName Win32_PrinterDriver -ErrorAction SilentlyContinue

    $printers | Export-Csv -Path (Join-Path $OutputFolder 'printers.csv') -NoTypeInformation -Encoding UTF8
    $drivers | Export-Csv -Path (Join-Path $OutputFolder 'drivers.csv') -NoTypeInformation -Encoding UTF8
    $ports | Export-Csv -Path (Join-Path $OutputFolder 'ports.csv') -NoTypeInformation -Encoding UTF8
    $printerWmi | Export-Csv -Path (Join-Path $OutputFolder 'win32_printer.csv') -NoTypeInformation -Encoding UTF8
    $driverWmi | Export-Csv -Path (Join-Path $OutputFolder 'win32_printerdriver.csv') -NoTypeInformation -Encoding UTF8

    $printers | Export-Clixml -Path (Join-Path $OutputFolder 'printers.xml')
    $drivers | Export-Clixml -Path (Join-Path $OutputFolder 'drivers.xml')
    $ports | Export-Clixml -Path (Join-Path $OutputFolder 'ports.xml')

    pnputil.exe /enum-drivers | Out-File -FilePath (Join-Path $OutputFolder 'pnputil_enum-drivers.txt') -Encoding UTF8
    Get-Service -Name Spooler | Export-Clixml -Path (Join-Path $OutputFolder 'spooler_service.xml')

    Write-Log 'Backup/Inventar abgeschlossen.' 'OK'
}

function Restart-PrintSpooler {
    Write-Log 'Stoppe Print Spooler.'
    Stop-Service -Name Spooler -Force -ErrorAction Stop
    Start-Sleep -Seconds 3

    Write-Log 'Starte Print Spooler.'
    Start-Service -Name Spooler -ErrorAction Stop

    $service = Get-Service -Name Spooler
    Write-Log "Print Spooler Status: $($service.Status)" 'OK'
}

function Remove-TargetPrinters {
    $printers = @(Get-Printer | Sort-Object -Property Name)
    $targets = @($printers | Where-Object {
            -not (Test-NameMatchesPattern -Name $_.Name -Patterns $protectedPrinterNamePatterns)
        })

    if ($targets.Count -eq 0) {
        Write-Log 'Keine zu entfernenden Drucker gefunden.' 'OK'
        return
    }

    Write-Log "Entferne $($targets.Count) Drucker."

    foreach ($printer in $targets) {
        try {
            if ($script:ShouldProcessContext.ShouldProcess($printer.Name, 'Drucker entfernen')) {
                Remove-Printer -Name $printer.Name -ErrorAction Stop
                Write-Log "Drucker entfernt: $($printer.Name)" 'OK'
            }
        }
        catch {
            Write-Log "Drucker konnte nicht entfernt werden: $($printer.Name) - $($_.Exception.Message)" 'ERROR'
        }
    }
}

function Remove-TargetDrivers {
    $protectedPrinterDrivers = @(
        Get-Printer |
            Where-Object { Test-NameMatchesPattern -Name $_.Name -Patterns $protectedPrinterNamePatterns } |
            Select-Object -ExpandProperty DriverName -Unique
    )

    $driverDetails = @(Get-CimInstance -ClassName Win32_PrinterDriver -ErrorAction SilentlyContinue)
    $drivers = @(Get-PrinterDriver | Sort-Object -Property Name)
    $targets = @($drivers | Where-Object {
            $isProtectedByName = Test-NameMatchesPattern -Name $_.Name -Patterns $protectedDriverNamePatterns
            $isUsedByProtectedPrinter = $protectedPrinterDrivers -contains $_.Name
            -not ($isProtectedByName -or $isUsedByProtectedPrinter)
        })
    $targetDriverNames = @($targets | Select-Object -ExpandProperty Name)
    $targetInfNames = @(
        $driverDetails |
            Where-Object {
                $printerDriverName = ($_.Name -split ',')[0]
                ($targetDriverNames -contains $printerDriverName) -and
                $_.InfName -and
                ($_.InfName -match '^oem\d+\.inf$')
            } |
            Select-Object -ExpandProperty InfName -Unique
    )

    if ($targets.Count -eq 0) {
        Write-Log 'Keine zu entfernenden Druckertreiber gefunden.' 'OK'
        return
    }

    Write-Log "Entferne $($targets.Count) Druckertreiber."

    foreach ($driver in $targets) {
        try {
            if ($script:ShouldProcessContext.ShouldProcess($driver.Name, 'Druckertreiber entfernen')) {
                Remove-PrinterDriver -Name $driver.Name -ErrorAction Stop
                Write-Log "Druckertreiber entfernt: $($driver.Name)" 'OK'
            }
        }
        catch {
            Write-Log "Druckertreiber konnte nicht entfernt werden: $($driver.Name) - $($_.Exception.Message)" 'ERROR'
        }
    }

    if ($targetInfNames.Count -eq 0) {
        Write-Log 'Keine zugehoerigen Drittanbieter-Treiberpakete im Driver Store gefunden.' 'OK'
        return
    }

    Write-Log "Entferne $($targetInfNames.Count) Drittanbieter-Treiberpakete aus dem Driver Store."

    foreach ($infName in $targetInfNames) {
        try {
            if ($script:ShouldProcessContext.ShouldProcess($infName, 'Treiberpaket aus Driver Store entfernen')) {
                $pnputilOutput = & pnputil.exe /delete-driver $infName /uninstall /force 2>&1
                foreach ($line in $pnputilOutput) {
                    Write-Log "pnputil $infName: $line"
                }

                if ($LASTEXITCODE -eq 0) {
                    Write-Log "Treiberpaket entfernt: $infName" 'OK'
                }
                else {
                    Write-Log "Treiberpaket konnte nicht entfernt werden: $infName (ExitCode $LASTEXITCODE)" 'WARN'
                }
            }
        }
        catch {
            Write-Log "Treiberpaket konnte nicht entfernt werden: $infName - $($_.Exception.Message)" 'ERROR'
        }
    }
}

function Remove-TargetPorts {
    $usedPorts = @(
        Get-Printer |
            Select-Object -ExpandProperty PortName -Unique
    )

    $ports = @(Get-PrinterPort | Sort-Object -Property Name)
    $targets = @($ports | Where-Object {
            $isProtected = Test-NameMatchesPattern -Name $_.Name -Patterns $protectedPortNamePatterns
            $isUsed = $usedPorts -contains $_.Name
            $isStandardTcpIp = $_.Name -match '^(IP_|WSD-|USB|COM\d+:|LPT\d+:)'
            -not ($isProtected -or $isUsed) -and $isStandardTcpIp
        })

    if ($targets.Count -eq 0) {
        Write-Log 'Keine unbenutzten Drittanbieter-Ports gefunden.' 'OK'
        return
    }

    Write-Log "Entferne $($targets.Count) unbenutzte Ports."

    foreach ($port in $targets) {
        try {
            if ($script:ShouldProcessContext.ShouldProcess($port.Name, 'Druckerport entfernen')) {
                Remove-PrinterPort -Name $port.Name -ErrorAction Stop
                Write-Log "Druckerport entfernt: $($port.Name)" 'OK'
            }
        }
        catch {
            Write-Log "Druckerport konnte nicht entfernt werden: $($port.Name) - $($_.Exception.Message)" 'ERROR'
        }
    }
}

if (-not (Test-IsAdministrator)) {
    throw 'Dieses Script muss in einer PowerShell-Konsole mit administrativen Rechten gestartet werden.'
}

$outputFolder = New-OutputFolder -Root $BackupRoot
$script:LogFile = Join-Path -Path $outputFolder -ChildPath 'PrintCleaner.log'
New-Item -Path $script:LogFile -ItemType File -Force | Out-Null

Start-Transcript -Path (Join-Path $outputFolder 'transcript.log') -Append | Out-Null

try {
    Write-Log 'PrintCleaner gestartet.'
    Write-Log "Computer: $env:COMPUTERNAME"
    Write-Log "Benutzer: $env:USERNAME"
    Write-Log "PowerShell: $($PSVersionTable.PSVersion)"
    Write-Log "BackupRoot: $BackupRoot"

    Export-Inventory -OutputFolder $outputFolder

    $allPrinters = @(Get-Printer | Sort-Object -Property Name)
    $targetPrinters = @($allPrinters | Where-Object {
            -not (Test-NameMatchesPattern -Name $_.Name -Patterns $protectedPrinterNamePatterns)
        })
    $protectedPrinters = @($allPrinters | Where-Object {
            Test-NameMatchesPattern -Name $_.Name -Patterns $protectedPrinterNamePatterns
        })

    Write-Host ''
    Write-Host 'Geschuetzte Drucker bleiben bestehen:'
    if ($protectedPrinters.Count -eq 0) {
        Write-Host '  Keine'
    }
    else {
        $protectedPrinters | ForEach-Object { Write-Host "  - $($_.Name)" }
    }

    Write-Host ''
    Write-Host 'Folgende Drucker werden entfernt:'
    if ($targetPrinters.Count -eq 0) {
        Write-Host '  Keine'
    }
    else {
        $targetPrinters | ForEach-Object { Write-Host "  - $($_.Name)" }
    }

    Write-Host ''
    Write-Host "Backup und Log: $outputFolder"
    Write-Host ''

    if (-not $Force) {
        $confirmation = Read-Host "Zum Fortfahren bitte exakt 'ENTFERNEN' eingeben"
        if ($confirmation -ne 'ENTFERNEN') {
            Write-Log 'Abbruch durch Benutzer.' 'WARN'
            return
        }
    }

    Remove-TargetPrinters
    Restart-PrintSpooler
    Remove-TargetDrivers
    Remove-TargetPorts
    Restart-PrintSpooler

    Export-Inventory -OutputFolder (Join-Path $outputFolder 'after')
    Write-Log 'PrintCleaner abgeschlossen.' 'OK'
    Write-Host ''
    Write-Host "Fertig. Logdatei: $script:LogFile"
}
finally {
    Stop-Transcript | Out-Null
}
