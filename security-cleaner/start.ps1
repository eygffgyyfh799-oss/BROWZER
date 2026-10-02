# Security Cleaner - one-command start (strict, full scan, confirmed threats only).
# Usage in any PowerShell window:
#   irm https://raw.githubusercontent.com/eygffgyyfh799-oss/BROWZER/claude/sleepy-ramanujan-pprdgc/security-cleaner/start.ps1 | iex
& {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $url  = 'https://raw.githubusercontent.com/eygffgyyfh799-oss/BROWZER/claude/sleepy-ramanujan-pprdgc/security-cleaner/Scan-And-Clean.ps1'
    $dir  = Join-Path $env:LOCALAPPDATA 'SecurityCleaner'
    $file = Join-Path $dir 'Scan-And-Clean.ps1'
    try {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Write-Host 'Downloading the latest Security Cleaner...' -ForegroundColor Cyan
        Invoke-WebRequest -Uri ($url + '?t=' + [DateTime]::UtcNow.Ticks) -OutFile $file -UseBasicParsing -ErrorAction Stop
    } catch { Write-Host "Download failed: $_" -ForegroundColor Red; return }
    $ver = (Select-String -LiteralPath $file -Pattern "^\`$Version = '([0-9.]+)'" | Select-Object -First 1).Matches.Groups[1].Value
    Write-Host "Version $ver ready. Windows will ask for administrator permission - press Yes." -ForegroundColor Green
    Write-Host 'To stop it at any time, run in another PowerShell window:' -ForegroundColor Yellow
    Write-Host '  irm https://raw.githubusercontent.com/eygffgyyfh799-oss/BROWZER/claude/sleepy-ramanujan-pprdgc/security-cleaner/stop.ps1 | iex' -ForegroundColor Yellow
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -NoExit -File `"$file`" -Strict"
}
