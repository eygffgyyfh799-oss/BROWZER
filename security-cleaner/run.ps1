# One-command launcher for Security Cleaner.
# Usage (in PowerShell):  irm https://raw.githubusercontent.com/eygffgyyfh799-oss/BROWZER/claude/sleepy-ramanujan-pprdgc/security-cleaner/run.ps1 | iex

& {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $url = 'https://raw.githubusercontent.com/eygffgyyfh799-oss/BROWZER/claude/sleepy-ramanujan-pprdgc/security-cleaner/Scan-And-Clean.ps1'
    $dir = Join-Path $env:LOCALAPPDATA 'SecurityCleaner'
    $file = Join-Path $dir 'Scan-And-Clean.ps1'

    Clear-Host
    Write-Host ''
    Write-Host '  ==============================================' -ForegroundColor Cyan
    Write-Host '               SECURITY CLEANER v5' -ForegroundColor Cyan
    Write-Host '  ==============================================' -ForegroundColor Cyan
    Write-Host ''
    Write-Host '   1  STRICT FULL: everything scanned, confirmed threats only (several hours)' -ForegroundColor Green
    Write-Host '   2  Fast auto-clean + junk cleanup      (about 10-20 minutes)'
    Write-Host '   3  Only clean temp / junk files        (a few minutes)'
    Write-Host '   4  Only scan (report, change nothing)'
    Write-Host '   5  Undo: restore quarantined files'
    Write-Host ''
    $choice = Read-Host '  Type a number and press Enter'

    switch ($choice.Trim()) {
        '1' { $opts = '-Strict' }
        '2' { $opts = '-Auto -CleanJunk' }
        '3' { $opts = '-JunkOnly' }
        '4' { $opts = '' }
        '5' { $opts = '-Restore' }
        default { Write-Host '  Wrong choice. Run the command again.' -ForegroundColor Red; return }
    }

    try {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Write-Host '  Downloading the latest version...'
        Invoke-WebRequest -Uri $url -OutFile $file -UseBasicParsing -ErrorAction Stop
    } catch {
        Write-Host "  Download failed: $_" -ForegroundColor Red
        return
    }

    # A new window opens as Administrator (press "Yes" on the Windows prompt). It stays open at the end.
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -NoExit -File `"$file`" $opts"
    Write-Host '  Started in a new Administrator window. Follow it there.' -ForegroundColor Green
}
