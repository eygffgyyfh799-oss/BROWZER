<#
.SYNOPSIS
    Scans a Windows PC for malware left behind by cracked games, fake "Steam tools"
    and backdoored FiveM resources, then (optionally) cleans what it found.

.DESCRIPTION
    Scan mode (default) changes nothing. It:
      - updates Microsoft Defender and runs a Quick (or Full) scan plus custom scans
      - checks Defender for disabled protection and suspicious exclusions
      - checks persistence: Run keys, Startup folders, scheduled tasks, services,
        WMI subscriptions, IFEO debuggers, Winlogon hijacks
      - checks hosts file and proxy hijacks
      - looks for unsigned executables/scripts in AppData, Temp, ProgramData, Public
      - lists processes from user folders that talk to the internet
      - checks the Steam folder for DLL hijacks (SteamTools / GreenLuma / malware)
      - scans FiveM resources (.lua/.js) for known backdoor patterns
    A report is saved to the Desktop.

    With -Clean, every High/Medium finding is shown and fixed only after you answer Y.
    Files are moved to C:\SecurityCleaner\Quarantine (not deleted) and registry keys
    are exported before being changed, so everything can be restored.

.EXAMPLE
    .\Scan-And-Clean.ps1
    .\Scan-And-Clean.ps1 -ScanPaths "D:\Games","D:\FiveM-Server"
    .\Scan-And-Clean.ps1 -FullScan -Clean
    .\Scan-And-Clean.ps1 -Restore
#>
[CmdletBinding()]
param(
    [string[]]$ScanPaths = @(),
    [switch]$FullScan,
    [switch]$SkipDefenderScan,
    [switch]$Clean,
    [switch]$Restore
)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

# ---------------------------------------------------------------- setup

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host 'Run this as Administrator (right-click Scan.bat -> Run as administrator).' -ForegroundColor Red
    exit 1
}

$Stamp     = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$BaseDir   = 'C:\SecurityCleaner'
$QRoot     = Join-Path $BaseDir 'Quarantine'
$QDir      = Join-Path $QRoot $Stamp
$Manifest  = Join-Path $QDir 'manifest.tsv'
$Desktop   = [Environment]::GetFolderPath('Desktop')
$Report    = Join-Path $Desktop "SecurityScan_$Stamp.txt"
$script:QCount = 0

$UserDirPattern = '(?i)\\(AppData|Temp|ProgramData|Users\\Public|Downloads)\\'
$LolbinPattern  = '(?i)((powershell|pwsh)(\.exe)?["]?\s.*(-e(nc|ncodedcommand)?\s|-w(indowstyle)?\s+h|iex|invoke-expression|downloadstring|frombase64string|bypass)|mshta(\.exe)?["]?\s|wscript(\.exe)?["]?\s|cscript(\.exe)?["]?\s|regsvr32(\.exe)?["]?\s.*/i:|rundll32(\.exe)?["]?\s+[^,]*\\(appdata|temp|programdata|users\\public)\\|certutil.*-urlcache|bitsadmin.*/transfer|curl.*\|\s*(cmd|powershell))'

$Findings = New-Object System.Collections.Generic.List[object]
$SeenFiles = @{}

function Write-Section([string]$Text) {
    Write-Host ''
    Write-Host "=== $Text ===" -ForegroundColor Cyan
}

function Add-Finding {
    param(
        [string]$Category, [ValidateSet('High','Medium','Info')][string]$Severity,
        [string]$Item, [string]$Detail,
        [string]$Action = '', [hashtable]$Data = @{}, [string]$FixText = ''
    )
    $f = [pscustomobject]@{
        Id = $Findings.Count + 1; Category = $Category; Severity = $Severity
        Item = $Item; Detail = $Detail; Action = $Action; Data = $Data; FixText = $FixText
    }
    $Findings.Add($f)
    $color = @{ High = 'Red'; Medium = 'Yellow'; Info = 'Gray' }[$Severity]
    Write-Host ("  [{0}] {1}: {2}" -f $Severity, $Category, $Item) -ForegroundColor $color
    if ($Detail) { Write-Host "         $Detail" -ForegroundColor DarkGray }
}

function Add-FileFinding([string]$Category, [string]$Severity, [string]$Path, [string]$Detail) {
    if (-not $Path) { return }
    $key = $Path.ToLowerInvariant()
    if ($SeenFiles.ContainsKey($key)) { return }
    $SeenFiles[$key] = $true
    Add-Finding -Category $Category -Severity $Severity -Item $Path -Detail $Detail `
        -Action 'Quarantine' -Data @{ Path = $Path } -FixText 'Move file to quarantine'
}

function Get-ExePath([string]$Cmd) {
    if (-not $Cmd) { return $null }
    $c = [Environment]::ExpandEnvironmentVariables($Cmd.Trim())
    if ($c.StartsWith('"')) { return $c.Substring(1).Split('"')[0] }
    $m = [regex]::Match($c, '^(.+?\.(exe|dll|bat|cmd|vbs|vbe|js|jse|ps1|scr|com|pif|lnk|hta|wsf))(\s|,|$)', 'IgnoreCase')
    if ($m.Success) { return $m.Groups[1].Value }
    return $c.Split(' ')[0]
}

function Get-SigStatus([string]$Path) {
    if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return 'Missing' }
    try { return (Get-AuthenticodeSignature -LiteralPath $Path -ErrorAction Stop).Status.ToString() }
    catch { return 'Unknown' }
}

# Returns a list of reasons why a command line looks malicious (empty = looks fine).
function Test-SuspiciousCommand([string]$Cmd) {
    $reasons = @()
    if (-not $Cmd) { return $reasons }
    if ($Cmd -match $LolbinPattern) { $reasons += 'launches a hidden/encoded script (LOLBin)' }
    $exe = Get-ExePath $Cmd
    if ($exe -and $exe -match $UserDirPattern) {
        $sig = Get-SigStatus $exe
        if ($sig -ne 'Valid') { $reasons += "runs from a user folder, signature: $sig" }
    }
    if ($exe -and $exe -match '(?i)\.(vbs|vbe|js|jse|hta|scr|pif|wsf)$') { $reasons += 'script-type file' }
    return $reasons
}

function Get-RegExportPath([string]$PsPath) {
    return ($PsPath -replace '^HKCU:\\', 'HKCU\' -replace '^HKLM:\\', 'HKLM\')
}

function Initialize-Quarantine {
    if (-not (Test-Path -LiteralPath $QDir)) { New-Item -ItemType Directory -Path $QDir -Force | Out-Null }
}

function Backup-RegKey([string]$PsPath) {
    Initialize-Quarantine
    $file = Join-Path $QDir ('reg_{0:D4}.reg' -f ($script:QCount++))
    & reg.exe export (Get-RegExportPath $PsPath) $file /y 2>&1 | Out-Null
}

function Move-ToQuarantine([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { throw "not found: $Path" }
    Initialize-Quarantine
    Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -and ($_.Path -eq $Path -or $_.Path.StartsWith($Path + '\', 'OrdinalIgnoreCase')) } |
        Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 300
    $dest = Join-Path $QDir ('{0:D4}_{1}.quarantine' -f ($script:QCount++), (Split-Path $Path -Leaf))
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.PSIsContainer) {
        Copy-Item -LiteralPath $Path -Destination $dest -Recurse -Force
        Remove-Item -LiteralPath $Path -Recurse -Force
    } else {
        $item.Attributes = 'Normal'
        Move-Item -LiteralPath $Path -Destination $dest -Force
    }
    Add-Content -LiteralPath $Manifest -Value ("{0}`t{1}" -f $Path, $dest)
}

# ---------------------------------------------------------------- restore mode

if ($Restore) {
    $last = Get-ChildItem -LiteralPath $QRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'manifest.tsv') } |
        Sort-Object Name -Descending | Select-Object -First 1
    if (-not $last) { Write-Host 'Nothing to restore.' -ForegroundColor Yellow; exit 0 }
    Write-Host "Restoring from $($last.FullName)" -ForegroundColor Cyan
    foreach ($line in Get-Content -LiteralPath (Join-Path $last.FullName 'manifest.tsv')) {
        $parts = $line.Split("`t")
        if ($parts.Count -ne 2) { continue }
        $ans = Read-Host "Restore $($parts[0]) ? (y/n)"
        if ($ans -notmatch '^[yY]') { continue }
        try {
            $parent = Split-Path $parts[0] -Parent
            if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
            Move-Item -LiteralPath $parts[1] -Destination $parts[0] -Force
            Write-Host '  restored' -ForegroundColor Green
        } catch { Write-Host "  failed: $_" -ForegroundColor Red }
    }
    Write-Host 'Registry backups (.reg files) are in the same folder - double-click one to restore it.'
    exit 0
}

Write-Host 'Security scan started. Nothing is changed during the scan.' -ForegroundColor Green

# ---------------------------------------------------------------- 1. Defender

Write-Section 'Microsoft Defender'
$mpOk = $false
try {
    $mp = Get-MpComputerStatus -ErrorAction Stop
    $mpOk = $true
    if ($mp.AMRunningMode -and $mp.AMRunningMode -ne 'Normal') {
        Add-Finding 'Defender' 'Info' "Defender running mode: $($mp.AMRunningMode)" 'Another antivirus may be active; Defender scans may be limited.'
    }
    if (-not $mp.RealTimeProtectionEnabled -or -not $mp.AntivirusEnabled) {
        Add-Finding 'Defender' 'High' 'Real-time protection is OFF' 'Malware often turns this off.' `
            -Action 'DefenderEnable' -FixText 'Turn real-time protection back on'
    }
    if ($mp.PSObject.Properties['IsTamperProtected'] -and -not $mp.IsTamperProtected) {
        Add-Finding 'Defender' 'Medium' 'Tamper Protection is OFF' 'Turn it on manually: Windows Security > Virus & threat protection > Manage settings.'
    }
} catch {
    Add-Finding 'Defender' 'High' 'Microsoft Defender is not available' "$_"
}

# Policy values that malware sets to kill Defender
$polBase = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender'
$polChecks = @(
    @{ Key = $polBase; Names = 'DisableAntiSpyware','DisableAntiVirus','DisableRoutinelyTakingAction' },
    @{ Key = "$polBase\Real-Time Protection"; Names = 'DisableRealtimeMonitoring','DisableBehaviorMonitoring','DisableOnAccessProtection','DisableScanOnRealtimeEnable','DisableIOAVProtection' },
    @{ Key = "$polBase\Spynet"; Names = 'SpynetReporting','SubmitSamplesConsent' }
)
foreach ($pc in $polChecks) {
    $p = Get-ItemProperty -LiteralPath $pc.Key -ErrorAction SilentlyContinue
    if (-not $p) { continue }
    foreach ($n in $pc.Names) {
        if ($null -ne $p.$n) {
            $bad = ($n -like 'Disable*' -and $p.$n -eq 1) -or ($n -eq 'SpynetReporting' -and $p.$n -eq 0) -or ($n -eq 'SubmitSamplesConsent' -and $p.$n -eq 2)
            if ($bad) {
                Add-Finding 'Defender policy' 'High' "$($pc.Key)\$n = $($p.$n)" 'Policy that weakens Defender (typical malware change).' `
                    -Action 'RegDeleteValue' -Data @{ Key = $pc.Key; Name = $n } -FixText 'Delete this policy value'
            }
        }
    }
}

# Exclusions (malware adds these so Defender stops seeing it)
if ($mpOk) {
    try {
        $pref = Get-MpPreference -ErrorAction Stop
        $excl = @(
            @{ Type = 'Path';      Values = $pref.ExclusionPath },
            @{ Type = 'Process';   Values = $pref.ExclusionProcess },
            @{ Type = 'Extension'; Values = $pref.ExclusionExtension }
        )
        foreach ($e in $excl) {
            foreach ($v in @($e.Values)) {
                if (-not $v -or $v -like 'N/A*') { continue }
                $sev = 'Medium'
                if ($v -match '^[A-Za-z]:\\?$' -or $v -match '(?i)\\(AppData|Temp|ProgramData|Users)\\?' -or
                    $v -match '(?i)^\.?(exe|dll|scr|bat|ps1|vbs|js)$' -or $v -match '(?i)(powershell|cmd|wscript|mshta|rundll32|regsvr32)\.exe$') { $sev = 'High' }
                Add-Finding 'Defender exclusion' $sev "$($e.Type): $v" 'Defender will NOT scan this. Remove unless you added it yourself on purpose.' `
                    -Action 'MpExclusionRemove' -Data @{ Type = $e.Type; Value = $v } -FixText 'Remove exclusion'
            }
        }
    } catch { }
    foreach ($sub in 'Paths','Processes','Extensions') {
        $k = "$polBase\Exclusions\$sub"
        $p = Get-ItemProperty -LiteralPath $k -ErrorAction SilentlyContinue
        if (-not $p) { continue }
        $p.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' } | ForEach-Object {
            Add-Finding 'Defender exclusion (policy)' 'High' "$sub : $($_.Name)" 'Exclusion forced by policy.' `
                -Action 'RegDeleteValue' -Data @{ Key = $k; Name = $_.Name } -FixText 'Delete this policy exclusion'
        }
    }
}

# ---------------------------------------------------------------- 2. Defender scan

if ($mpOk -and -not $SkipDefenderScan) {
    Write-Section 'Defender scan (this can take a while)'
    try { Write-Host '  Updating signatures...'; Update-MpSignature -ErrorAction Stop } catch { Write-Host "  Update failed: $_" -ForegroundColor Yellow }

    $customPaths = @($ScanPaths)
    foreach ($d in @([Environment]::GetFolderPath('UserProfile') + '\Downloads', $Desktop, $env:APPDATA, $env:LOCALAPPDATA, $env:TEMP)) {
        if ($d -and (Test-Path -LiteralPath $d)) { $customPaths += $d }
    }
    try {
        if ($FullScan) { Write-Host '  Full scan...'; Start-MpScan -ScanType FullScan -ErrorAction Stop }
        else { Write-Host '  Quick scan...'; Start-MpScan -ScanType QuickScan -ErrorAction Stop }
    } catch { Write-Host "  Scan error: $_" -ForegroundColor Yellow }
    if (-not $FullScan) {
        foreach ($p in ($customPaths | Select-Object -Unique)) {
            Write-Host "  Custom scan: $p"
            try { Start-MpScan -ScanType CustomScan -ScanPath $p -ErrorAction Stop } catch { Write-Host "    error: $_" -ForegroundColor Yellow }
        }
    }
}

if ($mpOk) {
    try {
        $threats = @(Get-MpThreat -ErrorAction SilentlyContinue)
        $detections = @(Get-MpThreatDetection -ErrorAction Stop)
        # 2 cleaned, 3 quarantined, 4 removed, 6 blocked = handled. 5 = "Allowed" by the user, which is exactly what cracks ask you to do.
        $pending = @($detections | Where-Object { $_.ThreatStatusID -notin 2, 3, 4, 6 })
        foreach ($d in $detections | Sort-Object InitialDetectionTime -Descending | Select-Object -First 40) {
            $name = ($threats | Where-Object { $_.ThreatID -eq $d.ThreatID } | Select-Object -First 1).ThreatName
            if (-not $name) { $name = "ThreatID $($d.ThreatID)" }
            $sev = 'Info'; $state = 'handled'
            if ($d.ThreatStatusID -notin 2, 3, 4, 6) { $sev = 'High'; $state = 'NOT removed' }
            if ($d.ThreatStatusID -eq 5) { $state = 'ALLOWED by user' }
            Add-Finding 'Defender detection' $sev "$name ($state)" ("{0} | {1}" -f $d.InitialDetectionTime, (($d.Resources | Select-Object -First 3) -join ' ; '))
        }
        if ($pending.Count -gt 0) {
            Add-Finding 'Defender' 'High' "$($pending.Count) threat(s) still waiting for action" '' `
                -Action 'MpThreatRemove' -FixText 'Let Defender remove all detected threats'
        }
    } catch { }
}

# ---------------------------------------------------------------- 3. Autoruns

Write-Section 'Startup entries (Run keys)'
$runKeys = @(
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce',
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer\Run',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\RunOnce',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer\Run'
)
foreach ($k in $runKeys) {
    $p = Get-ItemProperty -LiteralPath $k -ErrorAction SilentlyContinue
    if (-not $p) { continue }
    foreach ($prop in $p.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' }) {
        $cmd = [string]$prop.Value
        $reasons = @(Test-SuspiciousCommand $cmd)
        $sev = 'Info'
        if ($reasons.Count -gt 0) { $sev = 'Medium' }
        if ($reasons -match 'LOLBin|script-type' -or $reasons.Count -gt 1) { $sev = 'High' }
        $detail = $cmd; if ($reasons) { $detail = "$cmd  <-- " + ($reasons -join '; ') }
        Add-Finding 'Run key' $sev "$($prop.Name)  [$k]" $detail `
            -Action 'RegDeleteValue' -Data @{ Key = $k; Name = $prop.Name } -FixText 'Remove startup entry'
        if ($sev -ne 'Info') {
            $exe = Get-ExePath $cmd
            if ($exe -match $UserDirPattern -and (Test-Path -LiteralPath $exe)) { Add-FileFinding 'Startup file' $sev $exe "Started by Run key $($prop.Name)" }
        }
    }
}

# Winlogon hijacks
$wl = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -ErrorAction SilentlyContinue
if ($wl) {
    if ($wl.Shell -and $wl.Shell.Trim() -ine 'explorer.exe') {
        Add-Finding 'Winlogon' 'High' "Shell = $($wl.Shell)" 'Should be explorer.exe' `
            -Action 'RegSetValue' -Data @{ Key = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'; Name = 'Shell'; Value = 'explorer.exe' } -FixText 'Reset to explorer.exe'
    }
    if ($wl.Userinit -and ($wl.Userinit.Trim().TrimEnd(',') -ine 'C:\Windows\system32\userinit.exe')) {
        Add-Finding 'Winlogon' 'High' "Userinit = $($wl.Userinit)" 'Should be C:\Windows\system32\userinit.exe,' `
            -Action 'RegSetValue' -Data @{ Key = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'; Name = 'Userinit'; Value = 'C:\Windows\system32\userinit.exe,' } -FixText 'Reset Userinit'
    }
}

# IFEO debugger hijacks (used to block antivirus / hijack programs)
Get-ChildItem -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options' -ErrorAction SilentlyContinue | ForEach-Object {
    $dbg = (Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue).Debugger
    if ($dbg) {
        $k = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\' + $_.PSChildName
        Add-Finding 'IFEO hijack' 'High' "$($_.PSChildName) -> $dbg" 'Launching this program runs something else instead.' `
            -Action 'RegDeleteValue' -Data @{ Key = $k; Name = 'Debugger' } -FixText 'Remove Debugger hijack'
    }
}

Write-Section 'Startup folders'
$startupDirs = @(
    (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'),
    (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\StartUp')
)
$wsh = New-Object -ComObject WScript.Shell
foreach ($dir in $startupDirs) {
    Get-ChildItem -LiteralPath $dir -Force -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'desktop.ini' } | ForEach-Object {
        $target = $_.FullName; $args2 = ''
        if ($_.Extension -ieq '.lnk') {
            try { $sc = $wsh.CreateShortcut($_.FullName); $target = $sc.TargetPath; $args2 = $sc.Arguments } catch { }
        }
        $reasons = @(Test-SuspiciousCommand ("`"$target`" $args2"))
        $sev = 'Info'
        if ($_.Extension -match '(?i)^\.(vbs|vbe|js|jse|hta|wsf|scr|pif|ps1|bat|cmd)$') { $sev = 'High'; $reasons += 'script in Startup folder' }
        elseif ($reasons.Count -gt 0) { $sev = 'Medium' }
        Add-FileFinding 'Startup folder' $sev $_.FullName ("-> $target $args2 " + ($reasons -join '; '))
    }
}

Write-Section 'Scheduled tasks'
foreach ($t in Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskPath -notlike '\Microsoft\*' }) {
    foreach ($a in @($t.Actions)) {
        if (-not $a.Execute) { continue }
        $cmd = "`"$($a.Execute)`" $($a.Arguments)"
        $reasons = @(Test-SuspiciousCommand $cmd)
        if ($reasons.Count -eq 0) { continue }
        if ($t.Settings.Hidden) { $reasons += 'hidden task' }
        $sev = 'Medium'; if ($reasons -match 'LOLBin|script-type|hidden' -or $reasons.Count -gt 1) { $sev = 'High' }
        Add-Finding 'Scheduled task' $sev "$($t.TaskPath)$($t.TaskName)" ("$cmd  <-- " + ($reasons -join '; ')) `
            -Action 'TaskDisable' -Data @{ Path = $t.TaskPath; Name = $t.TaskName } -FixText 'Back up and disable task'
        $exe = Get-ExePath $cmd
        if ($exe -match $UserDirPattern -and (Test-Path -LiteralPath $exe)) { Add-FileFinding 'Task file' $sev $exe "Started by task $($t.TaskName)" }
    }
}

Write-Section 'Services'
foreach ($s in Get-CimInstance Win32_Service -ErrorAction SilentlyContinue) {
    $reasons = @(Test-SuspiciousCommand $s.PathName)
    if ($reasons.Count -eq 0) { continue }
    Add-Finding 'Service' 'High' "$($s.Name) ($($s.DisplayName))" ("$($s.PathName)  <-- " + ($reasons -join '; ')) `
        -Action 'ServiceDisable' -Data @{ Name = $s.Name } -FixText 'Stop and disable service'
    $exe = Get-ExePath $s.PathName
    if ($exe -match $UserDirPattern -and (Test-Path -LiteralPath $exe)) { Add-FileFinding 'Service file' 'High' $exe "Binary of service $($s.Name)" }
}

Write-Section 'WMI persistence'
Get-CimInstance -Namespace root\subscription -ClassName __EventConsumer -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -ne 'SCM Event Log Consumer' } | ForEach-Object {
        $what = $_.CommandLineTemplate; if (-not $what) { $what = $_.ScriptText }; if (-not $what) { $what = $_.ExecutablePath }
        Add-Finding 'WMI consumer' 'High' "$($_.CimClass.CimClassName): $($_.Name)" ([string]$what).Substring(0, [Math]::Min(200, ([string]$what).Length)) `
            -Action 'WmiRemove' -Data @{ Name = $_.Name } -FixText 'Remove WMI consumer and its binding'
    }

# ---------------------------------------------------------------- 4. Network hijacks

Write-Section 'Hosts file and proxy'
$hostsPath = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
$hostsLines = @(Get-Content -LiteralPath $hostsPath -ErrorAction SilentlyContinue | Where-Object { $_.Trim() -and -not $_.Trim().StartsWith('#') })
if ($hostsLines.Count -gt 0) {
    $sev = 'Medium'
    if ($hostsLines -match '(?i)microsoft|windowsupdate|defender|virustotal|malwarebytes|kaspersky|eset|avast|avg|bitdefender|norton|mcafee|steam|discord|google') { $sev = 'High' }
    Add-Finding 'Hosts file' $sev "$($hostsLines.Count) custom entries" (($hostsLines | Select-Object -First 8) -join ' | ') `
        -Action 'HostsReset' -FixText 'Back up hosts file and reset it to default'
}
$inet = Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue
if ($inet -and ($inet.ProxyEnable -eq 1 -or $inet.AutoConfigURL)) {
    Add-Finding 'Proxy' 'Medium' "Proxy: $($inet.ProxyServer) PAC: $($inet.AutoConfigURL)" 'A proxy can be used to spy on your traffic. Disable unless you set it.' `
        -Action 'ProxyDisable' -FixText 'Disable proxy / PAC'
}

# ---------------------------------------------------------------- 5. Suspicious files

Write-Section 'Unsigned programs/scripts in user folders'
$fileRoots = @(
    @{ Path = $env:APPDATA;      Depth = 1 },
    @{ Path = $env:LOCALAPPDATA; Depth = 1 },
    @{ Path = $env:TEMP;         Depth = 2 },
    @{ Path = $env:ProgramData;  Depth = 1 },
    @{ Path = $env:PUBLIC;       Depth = 3 }
)
$scriptExt = '(?i)^\.(vbs|vbe|js|jse|hta|wsf|scr|pif)$'
$softExt   = '(?i)^\.(ps1|bat|cmd)$'
$now = Get-Date
foreach ($r in $fileRoots) {
    if (-not $r.Path -or -not (Test-Path -LiteralPath $r.Path)) { continue }
    Get-ChildItem -LiteralPath $r.Path -Recurse -Depth $r.Depth -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -match '(?i)^\.(exe|com|scr|pif|vbs|vbe|js|jse|hta|wsf|ps1|bat|cmd)$' -and $_.FullName -notmatch '(?i)\\Microsoft\\(Windows|Edge|Teams|OneDrive)' } |
        ForEach-Object {
            $age = ($now - $_.LastWriteTime).TotalDays
            $hidden = [bool]($_.Attributes -band [IO.FileAttributes]::Hidden)
            if ($_.Extension -match $scriptExt) {
                Add-FileFinding 'Suspicious file' 'High' $_.FullName "script/screensaver in user folder, modified $($_.LastWriteTime)"
            } elseif ($_.Extension -match $softExt) {
                if ($age -lt 90) { Add-FileFinding 'Suspicious file' 'Medium' $_.FullName "script modified $($_.LastWriteTime)" }
            } else {
                $sig = Get-SigStatus $_.FullName
                if ($sig -eq 'HashMismatch') { Add-FileFinding 'Suspicious file' 'High' $_.FullName 'signature is BROKEN (file was tampered with)' }
                elseif ($sig -ne 'Valid') {
                    $sev = 'Info'
                    if ($age -lt 180) { $sev = 'Medium' }
                    if ($hidden) { $sev = 'High' }
                    Add-FileFinding 'Unsigned program' $sev $_.FullName ("signature: $sig, modified $($_.LastWriteTime)" + $(if ($hidden) { ', HIDDEN' } else { '' }))
                }
            }
        }
}

Write-Section 'Programs from user folders connected to the internet'
try {
    $conns = Get-NetTCPConnection -State Established -ErrorAction Stop | Where-Object { $_.RemoteAddress -notmatch '^(127\.|::1|0\.0\.0\.0)' }
    foreach ($g in $conns | Group-Object OwningProcess) {
        $proc = Get-Process -Id $g.Name -ErrorAction SilentlyContinue
        if (-not $proc -or -not $proc.Path -or $proc.Path -notmatch $UserDirPattern) { continue }
        $sig = Get-SigStatus $proc.Path
        if ($sig -eq 'Valid') { continue }
        $remotes = ($g.Group | ForEach-Object { "$($_.RemoteAddress):$($_.RemotePort)" } | Select-Object -Unique -First 5) -join ', '
        Add-FileFinding 'Network' 'High' $proc.Path "PID $($proc.Id) unsigned ($sig), connected to $remotes"
    }
} catch { }

# ---------------------------------------------------------------- 6. Steam / SteamTools

Write-Section 'Steam folder (SteamTools / GreenLuma / DLL hijack)'
$steam = (Get-ItemProperty -LiteralPath 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
if ($steam) {
    $steam = $steam -replace '/', '\'
    foreach ($dll in 'hid.dll','xinput1_4.dll','xinput1_3.dll','dwmapi.dll','version.dll','winmm.dll','dinput8.dll','winhttp.dll','d3d9.dll','user32.dll') {
        $p = Join-Path $steam $dll
        if (Test-Path -LiteralPath $p) {
            Add-FileFinding 'Steam DLL hijack' 'High' $p "Not part of Steam. Loaded into Steam automatically (SteamTools/unlocker or malware). Signature: $(Get-SigStatus $p)"
        }
    }
    foreach ($d in 'config\stplug-in','AppList') {
        $p = Join-Path $steam $d
        if (Test-Path -LiteralPath $p) { Add-FileFinding 'Steam unlocker' 'Medium' $p 'SteamTools/GreenLuma data folder (unlocker, can get the account banned).' }
    }
    Get-ChildItem -LiteralPath $steam -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '(?i)greenluma|dllinjector|steamtools|st-setup|stplug' } |
        ForEach-Object { Add-FileFinding 'Steam unlocker' 'Medium' $_.FullName 'Unlocker/injector file' }
} else {
    Write-Host '  Steam not found.'
}

# ---------------------------------------------------------------- 7. FiveM

Write-Section 'FiveM client and server resources'
$fivemApp = Join-Path $env:LOCALAPPDATA 'FiveM\FiveM.app'
foreach ($sub in 'plugins','mods') {
    $p = Join-Path $fivemApp $sub
    Get-ChildItem -LiteralPath $p -Recurse -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -match '(?i)^\.(dll|asi|exe)$' } |
        ForEach-Object { Add-FileFinding 'FiveM client' 'Medium' $_.FullName "Injected module in FiveM $sub (cheats/mods often carry stealers). Signature: $(Get-SigStatus $_.FullName)" }
}

$resRoots = @($ScanPaths) + @(
    (Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads'),
    $Desktop,
    [Environment]::GetFolderPath('MyDocuments')
) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique

$resourceDirs = @{}
foreach ($root in $resRoots) {
    Write-Host "  Looking for FiveM resources in $root"
    Get-ChildItem -LiteralPath $root -Recurse -File -Force -Include 'fxmanifest.lua','__resource.lua' -ErrorAction SilentlyContinue |
        ForEach-Object { $resourceDirs[$_.DirectoryName.ToLowerInvariant()] = $_.DirectoryName }
}
Write-Host "  Found $($resourceDirs.Count) resource(s)"

$knownBad   = '(?i)cipher-panel|ciphercheats|blum-panel|\bcipher\.lua\b'
$httpRx     = '(?i)PerformHttpRequest|https?\.(get|request)\s*\(|\bfetch\s*\(|XMLHttpRequest|http\.request'
$loadRx     = '(?i)(?<![\w.:])(load|loadstring)\s*\(|assert\s*\(\s*load|\beval\s*\(|new\s+Function\s*\(|\bRunString\s*\('
$execRx     = '(?i)os\.execute\s*\(|io\.popen\s*\(|child_process'
$b64Rx      = '(?i)Buffer\.from\s*\([^)]*base64|\batob\s*\('
$charRx     = 'string\.char\s*\(\s*\d+\s*(,\s*\d+\s*){20,}\)'

$scannedFiles = @{}
foreach ($dir in $resourceDirs.Values) {
    Get-ChildItem -LiteralPath $dir -Recurse -File -Force -Include '*.lua','*.js' -ErrorAction SilentlyContinue |
        Where-Object { $_.Length -lt 5MB } | ForEach-Object {
            $fp = $_.FullName
            if ($scannedFiles.ContainsKey($fp.ToLowerInvariant())) { return }
            $scannedFiles[$fp.ToLowerInvariant()] = $true
            $t = $null
            try { $t = [IO.File]::ReadAllText($fp) } catch { return }
            if (-not $t) { return }

            $reasons = @(); $sev = $null
            $hex = [regex]::Matches($t, '\\x[0-9a-fA-F]{2}').Count
            $hasHttp = $t -match $httpRx
            $hasLoad = $t -match $loadRx
            $hasChar = $t -match $charRx
            if ($t -match $knownBad)                          { $reasons += 'known FiveM backdoor panel name'; $sev = 'High' }
            if ($hasHttp -and $hasLoad)                       { $reasons += 'downloads code from the internet and runs it'; $sev = 'High' }
            if ($hasLoad -and ($hex -gt 30 -or $hasChar))     { $reasons += "runs obfuscated code (hex escapes: $hex)"; $sev = 'High' }
            if ($_.Extension -ieq '.js' -and $t -match '\beval\s*\(' -and $t -match $b64Rx) { $reasons += 'eval of base64 data'; $sev = 'High' }
            if (-not $sev -and $hex -gt 100)                  { $reasons += "heavily obfuscated ($hex hex escapes)"; $sev = 'Medium' }
            if ($t -match $execRx)                            { $reasons += 'runs system commands'; if (-not $sev) { $sev = 'Medium' } }
            if ($_.Extension -ieq '.lua' -and ($t -split "`n" | Where-Object { $_.Length -gt 3000 } | Select-Object -First 1)) {
                $reasons += 'very long single line (obfuscation)'; if (-not $sev) { $sev = 'Medium' }
            }
            if (-not $sev) { return }

            # point at the first offending line so it can be removed by hand if preferred
            $lineInfo = ''
            $lines = $t -split "`n"
            for ($i = 0; $i -lt $lines.Count; $i++) {
                if ($lines[$i] -match $knownBad -or $lines[$i] -match $loadRx -or $lines[$i] -match $execRx -or $lines[$i] -match $charRx) {
                    $snip = $lines[$i].Trim(); if ($snip.Length -gt 140) { $snip = $snip.Substring(0, 140) + '...' }
                    $lineInfo = " | line $($i + 1): $snip"; break
                }
            }
            Add-FileFinding 'FiveM backdoor' $sev $fp (($reasons -join '; ') + $lineInfo)
        }
}
Write-Host "  Scanned $($scannedFiles.Count) script file(s)"

# ---------------------------------------------------------------- report

$high = @($Findings | Where-Object Severity -eq 'High')
$med  = @($Findings | Where-Object Severity -eq 'Medium')
$info = @($Findings | Where-Object Severity -eq 'Info')

$out = New-Object System.Collections.Generic.List[string]
$out.Add("Security scan report - $Stamp - $env:COMPUTERNAME")
$out.Add("High: $($high.Count)   Medium: $($med.Count)   Info: $($info.Count)")
$out.Add('')
foreach ($sevName in 'High','Medium','Info') {
    $group = @($Findings | Where-Object Severity -eq $sevName)
    if (-not $group) { continue }
    $out.Add("########## $sevName ##########")
    foreach ($f in $group) {
        $out.Add(("#{0} [{1}] {2}" -f $f.Id, $f.Category, $f.Item))
        if ($f.Detail) { $out.Add("     $($f.Detail)") }
        if ($f.FixText -and $sevName -ne 'Info') { $out.Add("     fix: $($f.FixText)") }
    }
    $out.Add('')
}
$out | Out-File -LiteralPath $Report -Encoding UTF8

Write-Section 'Summary'
Write-Host ("  High: {0}   Medium: {1}   Info: {2}" -f $high.Count, $med.Count, $info.Count)
Write-Host "  Report saved to: $Report" -ForegroundColor Green

# ---------------------------------------------------------------- clean

function Invoke-Fix($f) {
    $d = $f.Data
    switch ($f.Action) {
        'Quarantine'        { Move-ToQuarantine $d.Path }
        'RegDeleteValue'    { Backup-RegKey $d.Key; Remove-ItemProperty -LiteralPath $d.Key -Name $d.Name -Force -ErrorAction Stop }
        'RegSetValue'       { Backup-RegKey $d.Key; Set-ItemProperty -LiteralPath $d.Key -Name $d.Name -Value $d.Value -ErrorAction Stop }
        'TaskDisable'       {
            Initialize-Quarantine
            Export-ScheduledTask -TaskPath $d.Path -TaskName $d.Name | Out-File -LiteralPath (Join-Path $QDir ('task_{0:D4}.xml' -f ($script:QCount++))) -Encoding Unicode
            Disable-ScheduledTask -TaskPath $d.Path -TaskName $d.Name -ErrorAction Stop | Out-Null
        }
        'ServiceDisable'    { Stop-Service -Name $d.Name -Force -ErrorAction SilentlyContinue; Set-Service -Name $d.Name -StartupType Disabled -ErrorAction Stop }
        'WmiRemove'         {
            Get-CimInstance -Namespace root\subscription -ClassName __FilterToConsumerBinding -ErrorAction SilentlyContinue |
                Where-Object { $_.Consumer.Name -eq $d.Name } | Remove-CimInstance -ErrorAction Stop
            Get-CimInstance -Namespace root\subscription -ClassName __EventConsumer -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -eq $d.Name } | Remove-CimInstance -ErrorAction Stop
        }
        'MpExclusionRemove' {
            switch ($d.Type) {
                'Path'      { Remove-MpPreference -ExclusionPath $d.Value -ErrorAction Stop }
                'Process'   { Remove-MpPreference -ExclusionProcess $d.Value -ErrorAction Stop }
                'Extension' { Remove-MpPreference -ExclusionExtension $d.Value -ErrorAction Stop }
            }
        }
        'MpThreatRemove'    { Remove-MpThreat -ErrorAction Stop }
        'DefenderEnable'    { Set-MpPreference -DisableRealtimeMonitoring $false -DisableBehaviorMonitoring $false -DisableIOAVProtection $false -ErrorAction Stop }
        'HostsReset'        {
            Initialize-Quarantine
            Copy-Item -LiteralPath $hostsPath -Destination (Join-Path $QDir 'hosts.backup') -Force
            $default = "# Copyright (c) 1993-2009 Microsoft Corp.`r`n#`r`n# localhost name resolution is handled within DNS itself.`r`n#`t127.0.0.1       localhost`r`n#`t::1             localhost`r`n"
            [IO.File]::WriteAllText($hostsPath, $default, [Text.Encoding]::ASCII)
            & ipconfig.exe /flushdns | Out-Null
        }
        'ProxyDisable'      {
            $k = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
            Backup-RegKey $k
            Set-ItemProperty -LiteralPath $k -Name ProxyEnable -Value 0
            Remove-ItemProperty -LiteralPath $k -Name AutoConfigURL -ErrorAction SilentlyContinue
        }
        default { throw "no automatic fix" }
    }
}

$fixable = @($Findings | Where-Object { $_.Severity -ne 'Info' -and $_.Action })
if (-not $Clean -and $fixable.Count -gt 0) {
    $ans = Read-Host "`nFound $($fixable.Count) item(s) that can be cleaned. Start cleaning now? (y/n)"
    if ($ans -match '^[yY]') { $Clean = $true }
}

if ($Clean -and $fixable.Count -gt 0) {
    Write-Section 'Cleaning'
    Write-Host '  For each item: y = fix, n = skip, a = fix this and all remaining, q = stop' -ForegroundColor Cyan
    $all = $false; $fixed = 0; $failed = 0
    foreach ($f in $fixable | Sort-Object @{ Expression = { if ($_.Severity -eq 'High') { 0 } else { 1 } } }, Id) {
        Write-Host ''
        Write-Host ("#{0} [{1}] {2}: {3}" -f $f.Id, $f.Severity, $f.Category, $f.Item) -ForegroundColor $(if ($f.Severity -eq 'High') { 'Red' } else { 'Yellow' })
        if ($f.Detail) { Write-Host "    $($f.Detail)" -ForegroundColor DarkGray }
        if (-not $all) {
            $ans = Read-Host "    $($f.FixText)? (y/n/a/q)"
            if ($ans -match '^[qQ]') { break }
            if ($ans -match '^[aA]') { $all = $true }
            elseif ($ans -notmatch '^[yY]') { continue }
        }
        try { Invoke-Fix $f; $fixed++; Write-Host '    done' -ForegroundColor Green }
        catch { $failed++; Write-Host "    failed: $_" -ForegroundColor Red }
    }
    Write-Host ''
    Write-Host "  Fixed: $fixed   Failed: $failed" -ForegroundColor Green
    if (Test-Path -LiteralPath $QDir) { Write-Host "  Quarantine and backups: $QDir  (undo with Restore.bat)" }
    Write-Host '  Restart the PC, then run Scan.bat again to confirm it is clean.' -ForegroundColor Cyan
}

Write-Host ''
Write-Host 'IMPORTANT: cracked games and fake tools usually contain password stealers.' -ForegroundColor Yellow
Write-Host 'From ANOTHER clean device (phone), change passwords for: email, Discord, Steam,' -ForegroundColor Yellow
Write-Host 'Rockstar/CFX, banks. Log out all sessions, turn on 2FA, and deauthorize all Steam devices.' -ForegroundColor Yellow
Write-Host 'If High items keep coming back after cleaning, back up your files and reset Windows.' -ForegroundColor Yellow
