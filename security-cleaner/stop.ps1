# Security Cleaner - safe stop. Stops the tool, cancels the Defender scan it started and closes Kaspersky KVRT.
# Usage: irm https://raw.githubusercontent.com/eygffgyyfh799-oss/BROWZER/claude/sleepy-ramanujan-pprdgc/security-cleaner/stop.ps1 | iex
& {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $body = {
        $me = $PID
        $procs = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object { $_.ProcessId -ne $me -and $_.CommandLine -match 'Scan-And-Clean\.ps1' })
        foreach ($p in $procs) { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue }
        Write-Host ("Security Cleaner processes stopped: {0}" -f $procs.Count) -ForegroundColor Green
        $mp = Join-Path $env:ProgramFiles 'Windows Defender\MpCmdRun.exe'
        if (Test-Path -LiteralPath $mp) { & $mp -Scan -Cancel | Out-Null; Write-Host 'Defender scan cancelled (real-time protection stays ON).' -ForegroundColor Green }
        $k = @(Get-Process -Name 'KVRT' -ErrorAction SilentlyContinue)
        $k | Stop-Process -Force -ErrorAction SilentlyContinue
        Write-Host ("Kaspersky KVRT closed: {0}" -f $k.Count) -ForegroundColor Green
        Write-Host 'Stopped safely. Anything already moved is in C:\SecurityCleaner\Quarantine and can be restored with -Restore.' -ForegroundColor Cyan
    }
    if ($isAdmin) { & $body }
    else {
        $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes("& {$body}; Read-Host 'Press Enter to close'"))
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $enc"
    }
}
