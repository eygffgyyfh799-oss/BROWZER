<#
.SYNOPSIS
    Security Cleaner v3 - scans a Windows PC for malware, stealers and crypto miners left
    behind by cracked games, fake "Steam tools" and backdoored FiveM resources, then
    (optionally) cleans what it found.

.DESCRIPTION
    Scan mode (default) changes nothing. It checks:
      - Microsoft Defender: status, tampering policies, exclusions, PUA/cloud protection,
        detection history (including threats you "Allowed"), then updates and scans
      - Running processes: crypto miners, fake system processes (svchost/explorer in the
        wrong folder), hidden/encoded PowerShell, high CPU usage from unsigned programs
      - Network: unsigned programs from user folders online, connections to mining ports
      - Persistence: Run keys, Startup folders, scheduled tasks, services, drivers, WMI,
        IFEO, Winlogon, AppInit_DLLs, PowerShell profiles
      - Browsers: force-installed extensions and shortcuts with --load-extension
      - Hosts file, proxy, disabled Windows Update
      - Files: unsigned programs/scripts in user folders, double extensions (.pdf.exe),
        miner binaries and miner configs
      - Steam: DLL hijacks (SteamTools / GreenLuma / malware)
      - FiveM: injected client plugins and backdoored .lua/.js resources, including code
        hidden with \x / \ddd / string.char / String.fromCharCode encoding
      - Firewall off, inbound firewall rules for unsigned user-folder programs, UAC off,
        extra admin accounts, remote-access tools / RATs
    -SecondOpinion also runs Kaspersky Virus Removal Tool (signature-verified download).
    -CleanJunk / -JunkOnly delete temp and cache files (temp, crash dumps, error reports,
    shader/browser/Discord/FiveM caches). Nothing else.

    Safety (-Clean):
      - every fix is confirmed by you (or -AutoFixHigh for High only)
      - a System Restore point is created first
      - files are MOVED to C:\SecurityCleaner\Quarantine, never deleted
      - registry keys are exported before changes; tasks/services are disabled, not deleted
      - hard guard: never touches anything inside C:\Windows, Microsoft-signed files,
        signed programs in Program Files, drive roots, main user folders, critical services
        or critical system processes
      - everything can be undone with -Restore

.EXAMPLE
    .\Scan-And-Clean.ps1
    .\Scan-And-Clean.ps1 -FullScan -ScanPaths "D:\Games","D:\FiveM-Server"
    .\Scan-And-Clean.ps1 -FullScan -Clean -AutoFixHigh
    .\Scan-And-Clean.ps1 -FullScan -SecondOpinion -Clean -AutoFixHigh -CleanJunk
    .\Scan-And-Clean.ps1 -JunkOnly
    .\Scan-And-Clean.ps1 -Restore
#>
[CmdletBinding()]
param(
    [string[]]$ScanPaths = @(),
    [switch]$FullScan,
    [switch]$SkipDefenderScan,
    [switch]$Clean,
    [switch]$AutoFixHigh,
    [switch]$OfflineScan,
    [switch]$SecondOpinion,
    [switch]$CleanJunk,
    [switch]$JunkOnly,
    [switch]$Restore,
    [switch]$Auto,
    [switch]$Full,
    [switch]$Strict,
    [string[]]$Server = @(),
    [string[]]$Trust = @()
)

$ErrorActionPreference = 'Continue'
if ($Full) { $FullScan = $true; $SecondOpinion = $true; $Auto = $true; $CleanJunk = $true }
# -Strict = everything scanned, one command, no questions, only confirmed threats acted on
if ($Strict) { $FullScan = $true; $SecondOpinion = $true; $CleanJunk = $true; $Auto = $false }
$ProgressPreference = 'SilentlyContinue'
$Version = '6.0'

# ---------------------------------------------------------------- setup

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host 'Run this as Administrator (open PowerShell with "Run as administrator").' -ForegroundColor Red
    return
}

$Stamp     = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$BaseDir   = 'C:\SecurityCleaner'
$QRoot     = Join-Path $BaseDir 'Quarantine'
$QDir      = Join-Path $QRoot $Stamp
$Manifest  = Join-Path $QDir 'manifest.tsv'
$LogDir    = Join-Path $BaseDir 'Logs'
$Desktop   = [Environment]::GetFolderPath('Desktop')
$Documents = [Environment]::GetFolderPath('MyDocuments')
$Downloads = Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads'
$Report    = Join-Path $Desktop "SecurityScan_$Stamp.txt"
$script:QCount = 0

New-Item -ItemType Directory -Path $LogDir -Force | Out-Null

# ---- local threat database: SHA256 of every confirmed threat, so it is recognised instantly next time (even renamed)
$ThreatDbFile = Join-Path $BaseDir 'threat-db.csv'
$script:ThreatDb = @{}
$script:ThreatDbAdded = 0
if (Test-Path -LiteralPath $ThreatDbFile) {
    try { Import-Csv -LiteralPath $ThreatDbFile | ForEach-Object { if ($_.Sha256) { $script:ThreatDb[$_.Sha256.ToUpperInvariant()] = $_ } } } catch { }
}
function Add-ThreatDbEntry([string]$Path, [string]$Category, [string]$Reason) {
    try {
        if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
        $h = (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash.ToUpperInvariant()
        if ($script:ThreatDb.ContainsKey($h)) { return }
        $e = [pscustomobject]@{ Sha256 = $h; Name = (Split-Path $Path -Leaf); Category = $Category
            Reason = ([string]$Reason -replace '[\r\n]+', ' '); FirstSeen = (Get-Date -Format 'yyyy-MM-dd HH:mm'); Path = $Path }
        $script:ThreatDb[$h] = $e
        $e | Export-Csv -LiteralPath $ThreatDbFile -Append -NoTypeInformation -Encoding UTF8
        $script:ThreatDbAdded++
    } catch { }
}
try { Start-Transcript -LiteralPath (Join-Path $LogDir "run_$Stamp.log") -Force | Out-Null } catch { }

$SteamPath = (Get-ItemProperty -LiteralPath 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
if ($SteamPath) { $SteamPath = $SteamPath -replace '/', '\' }

$UserDirPattern = '(?i)\\(AppData|Temp|ProgramData|Users\\Public|Downloads)\\'
$LolbinPattern  = '(?i)((powershell|pwsh)(\.exe)?["]?\s.*(-e(nc|ncodedcommand)?\s|-w(indowstyle)?\s+h|iex|invoke-expression|downloadstring|frombase64string|bypass)|mshta(\.exe)?["]?\s|wscript(\.exe)?["]?\s|cscript(\.exe)?["]?\s|regsvr32(\.exe)?["]?\s.*/i:|rundll32(\.exe)?["]?\s+[^,]*\\(appdata|temp|programdata|users\\public)\\|certutil.*-urlcache|bitsadmin.*/transfer|curl.*\|\s*(cmd|powershell))'
# stricter version used on RUNNING processes (legit tools often run powershell -ExecutionPolicy Bypass)
$RunningBadCmd  = '(?i)-e(nc|ncodedcommand)?\s+[A-Za-z0-9+/=]{40,}|frombase64string|downloadstring|downloadfile|\biex\s*[\(\$]|invoke-expression|mshta(\.exe)?["]?\s+(https?:|vbscript:|javascript:)|(wscript|cscript)(\.exe)?["]?\s+.*\\(appdata|temp|programdata|users\\public)\\'

$MinerNames = 'xmrig|xmr-stak|nbminer|t-rex|lolminer|phoenixminer|gminer|nanominer|teamredminer|claymore|ethminer|srbminer|cpuminer|minerd|bzminer|rigel|onezerominer|wildrig|nheqminer|ccminer|excavator|miniz|kawpowminer|xmrminer'
$MinerArgs  = '(?i)stratum\+(tcp|ssl|tls)://|--donate-level|--randomx|--cinit-|\s--coin[= ]|\s--algo[= ]|\s-a\s+(rx/0|kawpow|ethash|etchash|autolykos2|cn/)|nicehash\.com|minexmr|supportxmr|nanopool|2miners|f2pool|herominers|moneroocean|unmineable|hashvault|c3pool|xmrpool'
$MinerPorts = @(3333, 4444, 5555, 7777, 14433, 14444, 45560, 45700, 10128, 20535, 19999)
$SysNames   = @('svchost','explorer','csrss','lsass','winlogon','services','smss','wininit','conhost','dllhost','taskhostw','sihost','spoolsv','runtimebroker','audiodg','wmiprvse','ctfmon','fontdrvhost','dwm','searchindexer','taskmgr','lsm','userinit')
$FakeSysNames = '(?i)^(scvhost|svhost|svch0st|svchosts|svchost32|svchostt|expl0rer|explorar|explore|csrs|csrsss|lsas|lsasss|isass|winlogin|win1ogon|dllh0st|conhosts|taskhost32|runtimebrokers|wininit32|smss32|servics)$'
$CriticalProcs = @('system','registry','smss','csrss','wininit','winlogon','services','lsass','lsaiso','svchost','msmpeng','memory compression','fontdrvhost','dwm')
$CriticalServices = '(?i)^(WinDefend|WdNisSvc|WdFilter|WdBoot|WdNisDrv|Sense|SecurityHealthService|wscsvc|mpssvc|BFE|wuauserv|UsoSvc|WaaSMedicSvc|BITS|TrustedInstaller|msiserver|RpcSs|RpcEptMapper|DcomLaunch|LSM|SamSs|EventLog|Dhcp|Dnscache|nsi|CryptSvc|Winmgmt|Schedule|ProfSvc|gpsvc|Power|PlugPlay|Audiosrv|AudioEndpointBuilder|Netman|netprofm|NlaSvc|LanmanWorkstation|Themes|UserManager|CoreMessagingRegistrar|StateRepository|SystemEventsBroker|BrokerInfrastructure|TimeBrokerSvc)$'

$Findings  = New-Object System.Collections.Generic.List[object]
$SeenFiles = @{}
$SeenKeys  = @{}
$SelfPids  = @($PID)
try { $SelfPids += (Get-CimInstance Win32_Process -Filter "ProcessId=$PID" -ErrorAction Stop).ParentProcessId } catch { }

function Write-Section([string]$Text) {
    Write-Host ''
    Write-Host "=== $Text ===" -ForegroundColor Cyan
}

function Get-NormPath([string]$Path) {
    if (-not $Path) { return $null }
    try { return [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Path)).TrimEnd('\') } catch { return $null }
}

$ProtectedDirs = @(
    $env:SystemDrive + '\', $env:SystemRoot, $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData,
    $env:APPDATA, $env:LOCALAPPDATA, $env:USERPROFILE, $env:PUBLIC, $env:TEMP, $Desktop, $Documents, $Downloads,
    (Split-Path $env:USERPROFILE -Parent), $SteamPath, $BaseDir,
    (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'),
    (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\StartUp')
) | Where-Object { $_ } | ForEach-Object { Get-NormPath $_ } | Where-Object { $_ }

function Get-SigInfo([string]$Path) {
    $r = [pscustomobject]@{ Status = 'Missing'; Microsoft = $false; Signer = '' }
    if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $r }
    try {
        $s = Get-AuthenticodeSignature -LiteralPath $Path -ErrorAction Stop
        $r.Status = $s.Status.ToString()
        if ($s.SignerCertificate) {
            $r.Signer = $s.SignerCertificate.Subject
            $r.Microsoft = ($s.Status -eq 'Valid' -and $s.SignerCertificate.Subject -match 'O=Microsoft (Corporation|Windows)')
        }
    } catch { $r.Status = 'Unknown' }
    return $r
}
function Get-SigStatus([string]$Path) { return (Get-SigInfo $Path).Status }

# Returns $null when the path may be quarantined, otherwise the reason it is protected.
function Test-ProtectedPath([string]$Path) {
    $full = Get-NormPath $Path
    if (-not $full) { return 'invalid path' }
    if ($full.Length -le 3) { return 'drive root' }
    foreach ($p in $ProtectedDirs) { if ($full -ieq $p) { return 'important system/user folder' } }
    $leaf = Split-Path $full -Leaf
    $isPsProfile = $leaf -match '(?i)^(Microsoft\.PowerShell_)?profile\.ps1$'
    if ($full.StartsWith($env:SystemRoot + '\', [StringComparison]::OrdinalIgnoreCase) -and -not $isPsProfile -and
        -not $full.StartsWith($env:SystemRoot + '\Temp\', [StringComparison]::OrdinalIgnoreCase)) { return 'inside the Windows folder' }
    $inSteam = $SteamPath -and $full.StartsWith((Get-NormPath $SteamPath) + '\', [StringComparison]::OrdinalIgnoreCase)
    foreach ($sys in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramW6432, (Join-Path $env:ProgramData 'Microsoft')) | Where-Object { $_ }) {
        if (-not $inSteam -and $full.StartsWith((Get-NormPath $sys) + '\', [StringComparison]::OrdinalIgnoreCase)) { return 'installed program / system folder' }
    }
    if (Test-Path -LiteralPath $full -PathType Leaf) {
        $sig = Get-SigInfo $full
        if ($sig.Microsoft) { return 'file signed by Microsoft' }
        $pf = @($env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ }
        foreach ($p in $pf) {
            if ($sig.Status -eq 'Valid' -and $full.StartsWith($p + '\', [StringComparison]::OrdinalIgnoreCase)) { return 'signed program in Program Files' }
        }
    } elseif (Test-Path -LiteralPath $full -PathType Container) {
        $n = @(Get-ChildItem -LiteralPath $full -Recurse -Force -File -ErrorAction SilentlyContinue | Select-Object -First 2001).Count
        if ($n -gt 2000) { return 'folder too large to quarantine automatically' }
    }
    return $null
}

# ---- allowlist: things the user trusts are reported as Info and never touched
$AllowFile = Join-Path $BaseDir 'allowlist.txt'
if (-not (Test-Path -LiteralPath $AllowFile)) {
    @(
        '# Security Cleaner allowlist - one entry per line. Lines starting with # are ignored.'
        '# Any finding whose path, name or command line CONTAINS an entry is trusted:'
        '# it is shown as Info and never stopped, disabled or quarantined.'
        '# Add your own:  .\Scan-And-Clean.ps1 -Trust "D:\Games\MyGame"'
        '# Note: crypto miners, fake system processes, FiveM backdoors and Defender detections are never trusted.'
        'C:\DeepCool\'
        '%LOCALAPPDATA%\Discord\'
        '%ProgramData%\SquirrelMachineInstalls\'
        '%LOCALAPPDATA%\Medal\'
        '%LOCALAPPDATA%\Roblox\'
        '%LOCALAPPDATA%\Programs\HeidiSQL\'
        '%ProgramData%\CPUID Software\'
        '%SystemRoot%\temp\cpuz'
        'B9ECED6F.ArmouryCrate'
        '%ProgramFiles%\ASUS\'
        '%ProgramFiles%\SteelSeries\'
        '\downloads\server\fxserver.exe'
    ) | Set-Content -LiteralPath $AllowFile -Encoding UTF8
}
if ($Trust.Count -gt 0) {
    foreach ($t in $Trust) { if ($t.Trim()) { Add-Content -LiteralPath $AllowFile -Value $t.Trim() -Encoding UTF8; Write-Host "Trusted: $($t.Trim())" -ForegroundColor Green } }
}
$Allow = @(Get-Content -LiteralPath $AllowFile -ErrorAction SilentlyContinue |
    ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') } |
    ForEach-Object { [Environment]::ExpandEnvironmentVariables($_) } | Where-Object { $_.Length -ge 4 })
# Every program installed on this PC (from the Windows uninstall list) is trusted automatically
$InstalledDirs = @()
$tooBroad = @($env:SystemDrive + '\', $env:SystemRoot, $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData, $env:USERPROFILE,
    $env:APPDATA, $env:LOCALAPPDATA, (Join-Path $env:LOCALAPPDATA 'Programs'), $env:TEMP, $env:PUBLIC) | Where-Object { $_ } | ForEach-Object { Get-NormPath $_ }
foreach ($uk in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall', 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall') {
    foreach ($k in Get-ChildItem -LiteralPath $uk -ErrorAction SilentlyContinue) {
        $pr = Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction SilentlyContinue
        if (-not $pr -or -not $pr.DisplayName) { continue }
        $cands = @()
        if ($pr.InstallLocation) { $cands += ([string]$pr.InstallLocation).Trim().Trim('"') }
        if ($pr.DisplayIcon) { $ic = ([string]$pr.DisplayIcon).Trim() -replace ',\s*-?[0-9]+$', ''; $cands += Split-Path $ic.Trim('"') -Parent }
        foreach ($c in $cands) {
            $n = Get-NormPath $c
            if (-not $n -or $n.Length -lt 8 -or $tooBroad -contains $n -or $n -match '(?i)\\(Temp|Downloads|Desktop)(\\|$)') { continue }
            if ($n.StartsWith($env:SystemRoot, [StringComparison]::OrdinalIgnoreCase)) { continue }   # never trust Windows (powershell, rundll32...)
            if ($SteamPath -and $n -ieq (Get-NormPath $SteamPath)) { continue }   # Steam folder stays checked for hijack DLLs
            if (Test-Path -LiteralPath $n -PathType Container) { $InstalledDirs += ($n + '\') }
        }
    }
}
$InstalledDirs = @($InstalledDirs | Sort-Object -Unique)
$Allow += $InstalledDirs
# These are never trusted, even inside a trusted folder (malware hides in legit folders)
$NeverTrust = '(?i)^(Crypto miner|Fake system process|Malicious script running|Mining pool connection|FiveM backdoor|Defender.*|Steam DLL hijack|Steam unlocker|Fake document / dangerous file|Forced browser extension|WMI consumer|Disguised file|Crack tool|Cracked game|Program in media folder|Malicious shortcut|Known threat \(database\)|Rootkit indicator|Ransomware indicator)$'

function Test-Trusted([string]$Text) {
    if (-not $Text) { return $false }
    foreach ($a in $Allow) { if ($Text.IndexOf($a, [StringComparison]::OrdinalIgnoreCase) -ge 0) { return $true } }
    return $false
}

function Add-Finding {
    param(
        [string]$Category, [ValidateSet('High','Medium','Info')][string]$Severity,
        [string]$Item, [string]$Detail,
        [string]$Action = '', [hashtable]$Data = @{}, [string]$FixText = '', [string]$Tech = ''
    )
    if ($Severity -ne 'Info' -and $Category -notmatch $NeverTrust -and "$Item`n$Detail" -notmatch $RunningBadCmd -and
        (Test-Trusted ("$Item`n$Detail`n" + [string]$Data.Path))) {
        $Severity = 'Info'; $Detail = "$Detail [trusted by your allowlist - not touched]"; $Action = ''; $FixText = ''
    }
    $f = [pscustomobject]@{
        Id = $Findings.Count + 1; Category = $Category; Severity = $Severity
        Item = $Item; Detail = $Detail; Action = $Action; Data = $Data; FixText = $FixText; Tech = $Tech
    }
    $Findings.Add($f)
    $color = @{ High = 'Red'; Medium = 'Yellow'; Info = 'Gray' }[$Severity]
    Write-Host ("  [{0}] {1}: {2}" -f $Severity, $Category, $Item) -ForegroundColor $color
    if ($Detail) { Write-Host "         $Detail" -ForegroundColor DarkGray }
}

function Add-FileFinding([string]$Category, [string]$Severity, [string]$Path, [string]$Detail, [string]$Tech = '') {
    $full = Get-NormPath $Path
    if (-not $full -or -not (Test-Path -LiteralPath $full)) { return }
    $key = $full.ToLowerInvariant()
    if ($SeenFiles.ContainsKey($key)) { return }
    $SeenFiles[$key] = $true
    $why = Test-ProtectedPath $full
    if ($why) {
        Add-Finding -Category $Category -Severity 'Info' -Item $full -Detail "$Detail [protected: $why - not touched]" -Tech $Tech
    } else {
        Add-Finding -Category $Category -Severity $Severity -Item $full -Detail $Detail `
            -Action 'Quarantine' -Data @{ Path = $full } -FixText 'Move to quarantine' -Tech $Tech
    }
}

function Add-KeyFinding([string]$Category, [string]$Severity, [string]$Item, [string]$Detail, [string]$Action, [hashtable]$Data, [string]$FixText) {
    $key = ($Action + '|' + (($Data.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join '|')).ToLowerInvariant()
    if ($SeenKeys.ContainsKey($key)) { return }
    $SeenKeys[$key] = $true
    Add-Finding -Category $Category -Severity $Severity -Item $Item -Detail $Detail -Action $Action -Data $Data -FixText $FixText
}

function Get-ExePath([string]$Cmd) {
    if (-not $Cmd) { return $null }
    $c = [Environment]::ExpandEnvironmentVariables($Cmd.Trim())
    if ($c.StartsWith('"')) { return $c.Substring(1).Split('"')[0] }
    $m = [regex]::Match($c, '^(.+?\.(exe|dll|bat|cmd|vbs|vbe|js|jse|ps1|scr|com|pif|lnk|hta|wsf))(\s|,|$)', 'IgnoreCase')
    if ($m.Success) { return $m.Groups[1].Value }
    return $c.Split(' ')[0]
}

# Every file path mentioned in a command line (the exe and any script/dll it loads)
function Get-ReferencedFiles([string]$Cmd) {
    if (-not $Cmd) { return @() }
    $c = [Environment]::ExpandEnvironmentVariables($Cmd)
    $list = @()
    $exe = Get-ExePath $c
    if ($exe) { $list += $exe }
    foreach ($m in [regex]::Matches($c, '(?i)([a-z]:\\[^"<>|*?\r\n]+?\.(exe|dll|ps1|vbs|vbe|js|jse|bat|cmd|hta|wsf|scr|pif|com))(?=["\s,]|$)')) {
        $list += $m.Groups[1].Value
    }
    return @($list | Select-Object -Unique)
}

# Returns reasons why a command line looks malicious (empty = looks fine).
function Test-SuspiciousCommand([string]$Cmd) {
    $reasons = @()
    if (-not $Cmd) { return $reasons }
    if ($Cmd -match $LolbinPattern) { $reasons += 'launches a hidden/encoded script (LOLBin)' }
    if ($Cmd -match $MinerArgs) { $reasons += 'crypto miner arguments' }
    foreach ($f in Get-ReferencedFiles $Cmd) {
        if ($f -match $UserDirPattern) {
            $sig = Get-SigStatus $f
            if ($sig -ne 'Valid') { $reasons += "runs from a user folder ($(Split-Path $f -Leaf), signature: $sig)"; break }
        }
    }
    $exe = Get-ExePath $Cmd
    if ($exe -and $exe -match '(?i)\.(vbs|vbe|js|jse|hta|scr|pif|wsf)$') { $reasons += 'script-type file' }
    return $reasons
}

function Add-ReferencedFileFindings([string]$Cmd, [string]$Category, [string]$Severity, [string]$Why) {
    foreach ($f in Get-ReferencedFiles $Cmd) {
        if ($f -match $UserDirPattern -and (Test-Path -LiteralPath $f -PathType Leaf)) {
            Add-FileFinding $Category $Severity $f $Why
        }
    }
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
    if (-not (Test-Path -LiteralPath $file)) { throw "could not back up $PsPath - not changed" }
}

function Move-ToQuarantine([string]$Path) {
    $full = Get-NormPath $Path
    if (-not $full -or -not (Test-Path -LiteralPath $full)) { throw "not found: $Path" }
    $why = Test-ProtectedPath $full
    if ($why) { throw "skipped for safety: $why" }
    Initialize-Quarantine
    Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.Id -notin $SelfPids -and $_.Path -and ($_.Path -ieq $full -or $_.Path.StartsWith($full + '\', [StringComparison]::OrdinalIgnoreCase)) } |
        Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 400
    $dest = Join-Path $QDir ('{0:D4}_{1}.quarantine' -f ($script:QCount++), (Split-Path $full -Leaf))
    $item = Get-Item -LiteralPath $full -Force
    if ($item.PSIsContainer) {
        Copy-Item -LiteralPath $full -Destination $dest -Recurse -Force -ErrorAction Stop
        Remove-Item -LiteralPath $full -Recurse -Force -ErrorAction Stop
    } else {
        $item.Attributes = 'Normal'
        Move-Item -LiteralPath $full -Destination $dest -Force -ErrorAction Stop
    }
    Add-Content -LiteralPath $Manifest -Value ("{0}`t{1}" -f $full, $dest)
}

# Lists files under a folder without following junctions/symlinks (so cleanup can never escape the folder)
function Get-FilesNoLinks([string]$Root, [switch]$Directories) {
    $stack = New-Object System.Collections.Stack
    $stack.Push($Root)
    while ($stack.Count -gt 0) {
        $dir = $stack.Pop()
        try {
            $di = New-Object IO.DirectoryInfo $dir
            if (-not $Directories) { foreach ($f in $di.GetFiles()) { $f } }
            foreach ($sub in $di.GetDirectories()) {
                if (-not ($sub.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                    if ($Directories) { $sub }
                    $stack.Push($sub.FullName)
                }
            }
        } catch { }
    }
}

function Format-Size([double]$Bytes) {
    if ($Bytes -ge 1GB) { return '{0:N2} GB' -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return '{0:N1} MB' -f ($Bytes / 1MB) }
    return '{0:N0} KB' -f ($Bytes / 1KB)
}

# Deletes temp/cache/junk files only. Every target is a cache or temp folder that Windows and apps rebuild.
function Clear-JunkFiles([switch]$NoPrompt, [switch]$EmptyRecycleBin) {
    Write-Section 'Cleaning temporary / junk files'
    $targets = New-Object System.Collections.Generic.List[object]
    $add = { param($name, $path, $hours) if ($path) { $targets.Add([pscustomobject]@{ Name = $name; Path = $path; Hours = $hours }) } }

    if ($env:TEMP -match '(?i)\\(Temp|Tmp)$') { & $add 'User temp files' $env:TEMP 24 }
    & $add 'Windows temp files'         "$env:SystemRoot\Temp" 24
    & $add 'Crash dumps'                "$env:LOCALAPPDATA\CrashDumps" 0
    & $add 'Error reports (archive)'    "$env:ProgramData\Microsoft\Windows\WER\ReportArchive" 0
    & $add 'Error reports (queue)'      "$env:ProgramData\Microsoft\Windows\WER\ReportQueue" 0
    & $add 'DirectX shader cache'       "$env:LOCALAPPDATA\D3DSCache" 0
    & $add 'NVIDIA shader cache'        "$env:LOCALAPPDATA\NVIDIA\DXCache" 0
    & $add 'NVIDIA GL cache'            "$env:LOCALAPPDATA\NVIDIA\GLCache" 0
    & $add 'AMD shader cache'           "$env:LOCALAPPDATA\AMD\DxCache" 0
    & $add 'FiveM cache'                "$env:LOCALAPPDATA\FiveM\FiveM.app\data\cache" 0
    & $add 'FiveM server cache'         "$env:LOCALAPPDATA\FiveM\FiveM.app\data\server-cache" 0
    & $add 'FiveM server cache (priv)'  "$env:LOCALAPPDATA\FiveM\FiveM.app\data\server-cache-priv" 0
    & $add 'Discord cache'              "$env:APPDATA\discord\Cache" 0
    & $add 'Discord code cache'         "$env:APPDATA\discord\Code Cache" 0
    foreach ($b in @(
        @{ N = 'Chrome'; P = "$env:LOCALAPPDATA\Google\Chrome\User Data" },
        @{ N = 'Edge';   P = "$env:LOCALAPPDATA\Microsoft\Edge\User Data" },
        @{ N = 'Brave';  P = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data" },
        @{ N = 'Opera';  P = "$env:LOCALAPPDATA\Opera Software" })) {
        if (-not (Test-Path -LiteralPath $b.P)) { continue }
        Get-ChildItem -LiteralPath $b.P -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
            foreach ($c in 'Cache', 'Code Cache', 'GPUCache') {
                $cp = Join-Path $_.FullName $c
                if (Test-Path -LiteralPath $cp) { & $add "$($b.N) cache ($($_.Name))" $cp 0 }
            }
        }
    }
    Get-ChildItem -LiteralPath "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles" -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
        & $add "Firefox cache ($($_.Name))" (Join-Path $_.FullName 'cache2') 0
    }

    # hard safety: never clean a folder that resolves to anything important
    $forbidden = @($env:SystemDrive + '\', $env:SystemRoot, "$env:SystemRoot\System32", $env:ProgramFiles, ${env:ProgramFiles(x86)},
        $env:ProgramData, $env:USERPROFILE, $env:APPDATA, $env:LOCALAPPDATA, $Desktop, $Documents, $Downloads, $BaseDir) |
        Where-Object { $_ } | ForEach-Object { Get-NormPath $_ }

    $total = 0.0
    $script:JunkCount = 0
    foreach ($t in $targets) {
        $root = Get-NormPath $t.Path
        if (-not $root -or -not (Test-Path -LiteralPath $root -PathType Container)) { continue }
        if ($forbidden -contains $root -or $root.Length -lt 12) { Write-Host "  skipped (unsafe path): $root" -ForegroundColor Yellow; continue }
        $cutoff = (Get-Date).AddHours(-$t.Hours)
        $freed = 0.0; $count = 0
        foreach ($f in Get-FilesNoLinks $root) {
            if ($t.Hours -gt 0 -and $f.LastWriteTime -gt $cutoff) { continue }
            $len = $f.Length
            try {
                if ($f.Attributes -band [IO.FileAttributes]::ReadOnly) { $f.Attributes = 'Normal' }
                $f.Delete(); $freed += $len; $count++
            } catch { }   # file in use - skip it
        }
        # remove now-empty sub folders (never the root itself)
        @(Get-FilesNoLinks $root -Directories) | Sort-Object { $_.FullName.Length } -Descending | ForEach-Object {
            try { if (-not $_.EnumerateFileSystemInfos().GetEnumerator().MoveNext()) { $_.Delete() } } catch { }
        }
        if ($count -gt 0) { Write-Host ("  {0,-34} {1,6} files  {2}" -f $t.Name, $count, (Format-Size $freed)) }
        $total += $freed
        $script:JunkCount += $count
    }
    try { Delete-DeliveryOptimizationCache -Force -ErrorAction Stop; Write-Host '  Delivery Optimization cache cleared' } catch { }
    $rb = 'n'
    if ($EmptyRecycleBin) { $rb = 'y' } elseif (-not $NoPrompt) { $rb = Read-Host '  Also empty the Recycle Bin? (y/n)' }
    if ($rb -match '^[yY]') { try { Clear-RecycleBin -Force -ErrorAction Stop; Write-Host '  Recycle Bin emptied' } catch { } }
    $script:JunkFreed = $total
    Write-Host ("  Total freed: {0}" -f (Format-Size $total)) -ForegroundColor Green
}

# ---- FiveM detection rules (shared by the normal scan and -Server mode)
$knownBad = '(?i)cipher-panel|ciphercheats|blum-panel|\bcipher\.lua\b|fivem-backdoor|backdoor\.lua'
$httpRx   = '(?i)PerformHttpRequest|https?\.(get|request)\s*\(|\bfetch\s*\(|XMLHttpRequest|http\.request|require\(\s*[''"]https?[''"]\s*\)'
$loadRx   = '(?i)(?<![\w.:])(load|loadstring)\s*\(|assert\s*\(\s*load|\beval\s*\(|new\s+Function\s*\(|\bRunString\s*\(|_G\s*\[\s*[''"](load|loadstring|assert)[''"]\s*\]'
$hiddenKw = '(?i)\b(loadstring|load|PerformHttpRequest|os\.execute|io\.popen|eval|child_process|require)\b|https?://'
$execRx   = '(?i)os\.execute\s*\(|io\.popen\s*\(|child_process'
$b64Rx    = '(?i)Buffer\.from\s*\([^)]*base64|\batob\s*\('
$charRx   = '(string\.char|String\.fromCharCode)\s*\(\s*[0-9]+\s*(,\s*[0-9]+\s*){20,}\)'
$stealRx  = '(?i)GetConvar\s*\(\s*[''"](sv_licenseKey|sv_licenseKeyToken|rcon_password|steam_webApiKey|mysql_connection_string)[''"]'
$webhookRx = '(?i)discord(app)?\.com/api/webhooks/'

# Decode \xNN, \ddd, string.char(...) and String.fromCharCode(...) so hidden code is visible
function Expand-Obfuscation([string]$Text) {
    $d = [regex]::Replace($Text, '\\x([0-9a-fA-F]{2})', { param($m) [string][char][Convert]::ToInt32($m.Groups[1].Value, 16) })
    $d = [regex]::Replace($d, '\\([0-9]{2,3})', { param($m) $n = [int]$m.Groups[1].Value; if ($n -lt 256) { [string][char]$n } else { $m.Value } })
    $d = [regex]::Replace($d, '(string\.char|String\.fromCharCode)\s*\(([0-9\s,]+)\)', {
        param($m)
        $chars = foreach ($v in ($m.Groups[2].Value -split ',')) { $v = $v.Trim(); if ($v -match '^[0-9]+$' -and [int]$v -lt 256) { [char][int]$v } }
        '"' + (-join $chars) + '"'
    })
    return $d
}


# ---- FiveM SERVER mode: find malicious code, remove only those lines, never touch clean files
$ObfuscatorRx = '(?i)Luraph|MoonSec|IronBrew|Prometheus Obfuscator|wearedevs\.net/obfuscator|protected (with|using|by) \w+ ?obfuscator'
$SignalRx     = '(?i)PerformHttpRequest|https?[:.]|\\x[0-9a-f]{2}|\\[0-9]{2,3}|string\.char|fromCharCode|\bload|\beval|Function\s*\(|child_process|_0x[0-9a-f]{4}|cipher|blum|GetConvar|webhooks|os\.execute|io\.popen|atob|base64|_G\s*\['

# Why a single line is malicious ($null = not malicious)
function Get-LineThreat([string]$Line, [bool]$IsJs) {
    if ($Line -notmatch $SignalRx) { return $null }
    $dec = Expand-Obfuscation $Line
    $all = $Line + "`n" + $dec
    $net  = ($all -match $httpRx) -or ($all -match 'https?://')
    $exec = $all -match $loadRx
    if ($all -match $knownBad) { return 'known FiveM backdoor panel' }
    if ($net -and $exec) { return 'downloads code from the internet and runs it' }
    if ($all -match $stealRx -and ($all -match $webhookRx -or $net)) { return 'steals server keys/passwords' }
    if ($dec -ne $Line -and [regex]::Matches($dec, $hiddenKw).Count -gt [regex]::Matches($Line, $hiddenKw).Count -and
        $dec -match '(?i)PerformHttpRequest|https?://|\bload|loadstring|\beval|child_process|os\.execute|io\.popen') { return 'network/exec code hidden with encoding' }
    if ($IsJs -and $Line -match '\beval\s*\(' -and $Line -match $b64Rx) { return 'runs base64-encoded code' }
    if ($IsJs -and [regex]::Matches($Line, '_0x[0-9a-fA-F]{4,}').Count -gt 15 -and $all -match '(?i)\beval|Function\s*\(|https?|child_process|require\s*\(') { return 'obfuscated JavaScript loader' }
    if (-not $IsJs -and $Line.Length -gt 1000 -and [regex]::Matches($Line, '\\x[0-9a-fA-F]{2}').Count -gt 50 -and $exec) { return 'obfuscated Lua loader' }
    return $null
}

# Bracket / Lua block balance of a piece of code (strings and comments removed). 0 = complete statement(s).
function Get-CodeBalance([string]$Code, [bool]$IsJs) {
    $c = $Code
    $c = [regex]::Replace($c, '--\[(=*)\[[\s\S]*?\]\1\]', '')
    $c = [regex]::Replace($c, '\[(=*)\[[\s\S]*?\]\1\]', '""')
    $c = [regex]::Replace($c, '"(?:\\.|[^"\\\r\n])*"', '""')
    $c = [regex]::Replace($c, "'(?:\\.|[^'\\\r\n])*'", "''")
    $c = [regex]::Replace($c, '`(?:\\.|[^`\\])*`', '""')
    $c = [regex]::Replace($c, '/\*[\s\S]*?\*/', '')
    if ($IsJs) { $c = [regex]::Replace($c, '//[^\r\n]*', '') } else { $c = [regex]::Replace($c, '--[^\r\n]*', '') }
    $b = 0; $p = 0; $k = 0
    foreach ($ch in $c.ToCharArray()) {
        switch ($ch) { '(' { $p++ } ')' { $p-- } '{' { $b++ } '}' { $b-- } '[' { $k++ } ']' { $k-- } }
    }
    $blocks = 0
    if (-not $IsJs) {
        $blocks = [regex]::Matches($c, '\b(function|if|do|repeat)\b').Count - [regex]::Matches($c, '\b(end|until)\b').Count
    }
    return [Math]::Abs($p) + [Math]::Abs($b) + [Math]::Abs($k) + [Math]::Abs($blocks)
}

# Analyse one file. Returns $null when clean.
function Get-ServerFileVerdict([IO.FileInfo]$File) {
    $fp = $File.FullName
    $isJs = $File.Extension -ieq '.js'
    $bytes = $null; try { $bytes = [IO.File]::ReadAllBytes($fp) } catch { return $null }
    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $text = [Text.Encoding]::UTF8.GetString($bytes)
    if ($hasBom) { $text = $text.Substring(1) }
    $isBundle = ($fp -match '(?i)\\citizen\\system_resources\\|\\node_modules\\') -or
                ($isJs -and ($File.Name -match '(?i)\.min\.js$' -or $File.Length -gt 300KB -or $fp -match '(?i)\\(dist|build|yarn|webpack)\\'))
    if ($isBundle) {
        # bundled/official code: only a known panel or secrets sent to a webhook count
        if ($text -notmatch $knownBad -and -not ($text -match $stealRx -and $text -match $webhookRx)) { return $null }
    } elseif ($text -notmatch $SignalRx) {
        return $null
    }

    $lines = [regex]::Split($text, '(?<=\n)')
    $bad = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $why = Get-LineThreat $lines[$i] $isJs
        if ($why) { $bad += [pscustomobject]@{ Index = $i; Why = $why; Need = $i }; continue }
        # multi-line backdoor: code runner (load/eval) right after a web request a few lines above
        if (-not $isBundle -and $lines[$i] -match $loadRx) {
            for ($k = $i - 1; $k -ge [Math]::Max(0, $i - 6); $k--) {
                $up = $lines[$k] + "`n" + (Expand-Obfuscation $lines[$k])
                if ($up -match $httpRx -or $up -match 'https?://') {
                    $bad += [pscustomobject]@{ Index = $i; Why = 'downloads code from the internet and runs it (multi-line)'; Need = $k }; break
                }
            }
        }
    }
    $obf = (-not $isBundle) -and ($text -match $ObfuscatorRx)
    if ($bad.Count -eq 0) {
        if ($obf) { return [pscustomobject]@{ Path = $fp; Status = 'Obfuscated'; Reason = 'protected by an obfuscator - its code cannot be checked'; Ranges = @(); Lines = $lines; Bom = $hasBom; IsJs = $isJs } }
        return $null
    }

    # find a removable range for each bad line: the line alone, or the smallest complete statement around it
    $ranges = @(); $unsafe = @()
    foreach ($bl in $bad) {
        $found = $null
        for ($size = 0; $size -le 12 -and -not $found; $size++) {
            for ($up = 0; $up -le $size -and -not $found; $up++) {
                $s = $bl.Index - $up; $e = $bl.Index + ($size - $up)
                if ($s -lt 0 -or $e -ge $lines.Count -or $s -gt $bl.Need) { continue }   # must include the web request line
                $chunk = -join $lines[$s..$e]
                if ((Get-CodeBalance $chunk $isJs) -eq 0) { $found = [pscustomobject]@{ Start = $s; End = $e; Why = $bl.Why } }
            }
        }
        if ($found) { $ranges += $found } else { $unsafe += $bl }
    }

    $status = 'Cleanable'; $reason = (($bad | ForEach-Object { $_.Why } | Select-Object -Unique) -join '; ')
    if ($unsafe.Count -gt 0) {
        $status = 'Infected'; $reason += " (malicious code is mixed into other code - cannot be removed safely)"
    } else {
        $remove = @{}
        foreach ($r in $ranges) { for ($j = $r.Start; $j -le $r.End; $j++) { $remove[$j] = $true } }
        $kept = for ($j = 0; $j -lt $lines.Count; $j++) { if (-not $remove.ContainsKey($j)) { $lines[$j] } }
        $rest = -join @($kept)
        $restCode = [regex]::Replace($rest, '(?m)^\s*(--|//).*$', '').Trim()
        if ($restCode.Length -lt 30) {
            $status = 'MaliciousFile'; $reason += ' (the whole file is malicious)'
        } else {
            # verify: the cleaned file must not contain anything malicious any more
            $still = $false
            $rl = [regex]::Split($rest, '(?<=\n)')
            for ($q = 0; $q -lt $rl.Count -and -not $still; $q++) {
                if (Get-LineThreat $rl[$q] $isJs) { $still = $true; break }
                if ($rl[$q] -match $loadRx) {
                    for ($k = $q - 1; $k -ge [Math]::Max(0, $q - 6); $k--) { if ($rl[$k] -match $httpRx) { $still = $true; break } }
                }
            }
            if ($still -or (Get-CodeBalance $rest $isJs) -ne (Get-CodeBalance $text $isJs)) {
                $status = 'Infected'; $reason += ' (could not verify the file after removing the code)'
            }
        }
    }
    return [pscustomobject]@{ Path = $fp; Status = $status; Reason = $reason; Ranges = $ranges; Lines = $lines; Bom = $hasBom; IsJs = $isJs }
}

function Repair-ServerFile($V) {
    Initialize-Quarantine
    $backup = Join-Path $QDir ('{0:D4}_{1}.original' -f ($script:QCount++), (Split-Path $V.Path -Leaf))
    Copy-Item -LiteralPath $V.Path -Destination $backup -Force -ErrorAction Stop
    Add-Content -LiteralPath $Manifest -Value ("{0}`t{1}" -f $V.Path, $backup)
    $remove = @{}
    foreach ($r in $V.Ranges) { for ($j = $r.Start; $j -le $r.End; $j++) { $remove[$j] = $r } }
    $mark = '-- [SecurityCleaner] removed malicious code here'; if ($V.IsJs) { $mark = '// [SecurityCleaner] removed malicious code here' }
    $sb = New-Object System.Text.StringBuilder
    for ($j = 0; $j -lt $V.Lines.Count; $j++) {
        if ($remove.ContainsKey($j)) {
            if ($j -eq $remove[$j].Start) { $nl = "`n"; if ($V.Lines[$remove[$j].End] -match "`r`n$") { $nl = "`r`n" }; [void]$sb.Append($mark + $nl) }
            continue
        }
        [void]$sb.Append($V.Lines[$j])
    }
    [IO.File]::WriteAllText($V.Path, $sb.ToString(), (New-Object System.Text.UTF8Encoding($V.Bom)))
}

function Invoke-ServerScan([string[]]$Roots) {
    Write-Section 'FiveM server scan'
    $files = New-Object System.Collections.Generic.List[object]
    foreach ($root in $Roots) {
        if (-not (Test-Path -LiteralPath $root -PathType Container)) { Write-Host "  Folder not found: $root" -ForegroundColor Red; continue }
        Write-Host "  Reading $root ..."
        Get-ChildItem -LiteralPath $root -Recurse -File -Force -ErrorAction SilentlyContinue |
            Where-Object { ($_.Extension -ieq '.lua' -or $_.Extension -ieq '.js') -and $_.Length -lt 5MB -and $_.FullName -notmatch '(?i)\\cache\\' } |
            ForEach-Object { $files.Add($_) }
    }
    Write-Host "  Checking $($files.Count) script files..."
    $verdicts = New-Object System.Collections.Generic.List[object]
    $n = 0
    foreach ($f in $files) {
        $n++; if ($n % 250 -eq 0) { Write-Host "    $n / $($files.Count)" -ForegroundColor DarkGray }
        $v = Get-ServerFileVerdict $f
        if ($v) { $verdicts.Add($v) }
    }

    # server.cfg: resources allowed to run console commands (backdoors use this)
    $aceNotes = @()
    foreach ($root in $Roots) {
        Get-ChildItem -LiteralPath $root -Recurse -File -Force -Filter 'server.cfg' -ErrorAction SilentlyContinue | ForEach-Object {
            $cfg = $_.FullName
            Select-String -LiteralPath $cfg -Pattern '^\s*add_ace\s+resource\.(\S+)\s+command\b.*allow' -ErrorAction SilentlyContinue |
                ForEach-Object { $aceNotes += "$cfg line $($_.LineNumber): resource '$($_.Matches[0].Groups[1].Value)' may run ANY console command" }
        }
    }

    $clean = @($verdicts | Where-Object Status -eq 'Cleanable')
    $malf  = @($verdicts | Where-Object Status -eq 'MaliciousFile')
    $inf   = @($verdicts | Where-Object Status -eq 'Infected')
    $obf   = @($verdicts | Where-Object Status -eq 'Obfuscated')

    Write-Section 'Result'
    Write-Host ("  Scripts checked: {0}   Clean: {1}   Infected: {2}   Obfuscated (cannot check): {3}" -f $files.Count, ($files.Count - $verdicts.Count), ($clean.Count + $malf.Count + $inf.Count), $obf.Count)
    if (($clean.Count + $malf.Count + $inf.Count) -eq 0) { Write-Host '  No malicious code found in the server files.' -ForegroundColor Green }

    $plan = New-Object System.Collections.Generic.List[object]
    foreach ($v in $clean) { $plan.Add([pscustomobject]@{ V = $v; Act = 'clean' }) }
    foreach ($v in $malf)  { $plan.Add([pscustomobject]@{ V = $v; Act = 'quarantine' }) }

    $done = @(); $failed = @()
    foreach ($v in $inf) { $failed += [pscustomobject]@{ Path = $v.Path; Why = "INFECTED - could not be cleaned safely, NOT touched: $($v.Reason)" } }
    if ($plan.Count -gt 0) {
        Write-Section 'FINAL STEP - your approval is needed'
        for ($i = 0; $i -lt $plan.Count; $i++) {
            $x = $plan[$i]; $v = $x.V
            Write-Host ''
            if ($x.Act -eq 'clean') {
                Write-Host ("  {0,2}. REMOVE MALICIOUS LINES (rest of the file is kept): {1}" -f ($i + 1), $v.Path) -ForegroundColor Red
                foreach ($r in $v.Ranges) {
                    $snip = ($v.Lines[$r.Start]).Trim(); if ($snip.Length -gt 110) { $snip = $snip.Substring(0, 110) + '...' }
                    $lr = "line $($r.Start + 1)"; if ($r.End -gt $r.Start) { $lr = "lines $($r.Start + 1)-$($r.End + 1)" }
                    Write-Host ("      {0}: {1}" -f $lr, $snip) -ForegroundColor DarkGray
                    Write-Host ("      reason: {0}" -f $r.Why) -ForegroundColor DarkGray
                }
            } else {
                Write-Host ("  {0,2}. MOVE WHOLE FILE TO QUARANTINE: {1}" -f ($i + 1), $v.Path) -ForegroundColor Red
                Write-Host ("      reason: {0}" -f $v.Reason) -ForegroundColor DarkGray
            }
        }
        Write-Host ''
        Write-Host '  Originals are backed up first - everything can be undone with:  .\Scan-And-Clean.ps1 -Restore' -ForegroundColor Cyan
        Write-Host '  y = approve all   n = nothing   numbers = all EXCEPT these (e.g. 2,4)' -ForegroundColor Cyan
        $ans = (Read-Host '  Your choice').Trim()
        $skip = @(); $go = $true
        if ($ans -match '^[nN]') { $go = $false }
        elseif ($ans -match '^[0-9 ,]+$') { $skip = @($ans -split '[ ,]+' | Where-Object { $_ } | ForEach-Object { [int]$_ }) }
        elseif ($ans -notmatch '^[yY]') { $go = $false; Write-Host '  Not understood - nothing was changed.' -ForegroundColor Yellow }
        if ($go) {
            for ($i = 0; $i -lt $plan.Count; $i++) {
                if ($skip -contains ($i + 1)) { $failed += [pscustomobject]@{ Path = $plan[$i].V.Path; Why = 'skipped by you - still infected' }; continue }
                $x = $plan[$i]
                try {
                    if ($x.Act -eq 'clean') {
                        Repair-ServerFile $x.V
                        $re = Get-ServerFileVerdict (Get-Item -LiteralPath $x.V.Path)
                        if ($re -and $re.Status -ne 'Obfuscated') { throw 'malicious code still detected after cleaning' }
                        $done += "CLEANED      $($x.V.Path)"
                    } else {
                        Move-ToQuarantine $x.V.Path
                        $done += "QUARANTINED  $($x.V.Path)"
                    }
                } catch { $failed += [pscustomobject]@{ Path = $x.V.Path; Why = "$_" } }
            }
        } else {
            foreach ($x in $plan) { $failed += [pscustomobject]@{ Path = $x.V.Path; Why = "not approved - still infected ($($x.V.Reason))" } }
        }
    }

    # ---- final report
    $rep = New-Object System.Collections.Generic.List[string]
    $rep.Add("Security Cleaner v$Version - FiveM server report - $Stamp")
    $rep.Add("Folders: $($Roots -join ', ')")
    $rep.Add("Scripts checked: $($files.Count)")
    $rep.Add('')
    Write-Section 'Summary'
    foreach ($d in $done) { Write-Host "  $d" -ForegroundColor Green; $rep.Add($d) }
    if ($failed.Count -gt 0) {
        Write-Host ''
        Write-Host '  INFECTED FILES THAT WERE NOT CLEANED:' -ForegroundColor Red
        $rep.Add(''); $rep.Add('INFECTED FILES THAT WERE NOT CLEANED:')
        foreach ($f in $failed) {
            Write-Host "    $($f.Path)" -ForegroundColor Red
            Write-Host "      why: $($f.Why)" -ForegroundColor DarkGray
            $rep.Add("  $($f.Path)"); $rep.Add("    why: $($f.Why)")
        }
        Write-Host ''
        Write-Host '  Command to DELETE these files permanently (copy and paste it if you are sure):' -ForegroundColor Yellow
        $cmd = ($failed | ForEach-Object { "Remove-Item -LiteralPath '" + ($_.Path -replace "'", "''") + "' -Force" }) -join '; '
        Write-Host "  $cmd"
        $rep.Add(''); $rep.Add('Delete command:'); $rep.Add($cmd)
    }
    if ($obf.Count -gt 0) {
        Write-Host ''
        Write-Host '  OBFUSCATED SCRIPTS (code is hidden, cannot be checked - not touched):' -ForegroundColor Yellow
        $rep.Add(''); $rep.Add('OBFUSCATED SCRIPTS (not touched):')
        foreach ($v in $obf) { Write-Host "    $($v.Path)"; $rep.Add("  $($v.Path)") }
        Write-Host '    Keep them only if they came from a trusted seller (Tebex/official). Leaked scripts like this are a common backdoor source.' -ForegroundColor DarkGray
    }
    if ($aceNotes.Count -gt 0) {
        Write-Host ''
        Write-Host '  server.cfg - resources allowed to run console commands (check you trust each one):' -ForegroundColor Yellow
        $rep.Add(''); $rep.Add('server.cfg command permissions:')
        foreach ($a in $aceNotes) { Write-Host "    $a"; $rep.Add("  $a") }
    }
    $repFile = Join-Path $Desktop "ServerScan_$Stamp.txt"
    $rep | Out-File -LiteralPath $repFile -Encoding UTF8
    Write-Host ''
    Write-Host "  Report saved to: $repFile" -ForegroundColor Green
    if ($done.Count -gt 0) {
        Write-Host '  IMPORTANT: a backdoor may already have stolen your keys. Regenerate your sv_licenseKey (keymaster.fivem.net),' -ForegroundColor Yellow
        Write-Host '  change rcon/database passwords and Discord bot tokens, and remove admins you do not know.' -ForegroundColor Yellow
    }
}

# ---- -Full: every file on every drive (except Windows itself)
# Reads the REAL file type from the file header, finds disguised programs, crack/keygen/activator tools,
# cracked games, programs hidden in picture/video/music folders and malicious shortcuts.

# $true when the file really is a Windows program (MZ header + PE signature), whatever its extension says
function Test-IsWindowsProgram([string]$Path) {
    $fs = $null
    try {
        $fs = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        $buf = New-Object byte[] 1024
        $n = $fs.Read($buf, 0, 1024)
        if ($n -lt 64 -or $buf[0] -ne 0x4D -or $buf[1] -ne 0x5A) { return $false }
        $pe = [BitConverter]::ToInt32($buf, 0x3C)
        if ($pe -lt 64 -or $pe + 4 -gt $n) { return $false }
        return ($buf[$pe] -eq 0x50 -and $buf[$pe + 1] -eq 0x45 -and $buf[$pe + 2] -eq 0 -and $buf[$pe + 3] -eq 0)
    } catch { return $false } finally { if ($fs) { $fs.Dispose() } }
}

function Invoke-DeepFileScan {
    Write-Section 'Every file on every drive (real file type, cracks, disguised programs)'
    $drives = @(Get-CimInstance Win32_LogicalDisk -ErrorAction SilentlyContinue | Where-Object { $_.DriveType -in 2, 3 } | ForEach-Object { $_.DeviceID + '\' })
    if ($drives.Count -eq 0) { $drives = @($env:SystemDrive + '\') }
    $skip = @{}
    foreach ($p in @($env:SystemRoot, $BaseDir, (Join-Path $env:SystemDrive 'Recovery'), (Join-Path $env:SystemDrive 'ProgramData\Microsoft\Windows Defender'))) {
        $n = Get-NormPath $p; if ($n) { $skip[$n.ToLowerInvariant()] = $true }
    }
    $mediaExt  = '(?i)^\.(jpe?g|png|gif|bmp|webp|tiff?|ico|heic|mp4|mkv|avi|mov|wmv|flv|webm|m4v|mp3|wav|flac|aac|ogg|m4a|pdf|docx?|xlsx?|pptx?|txt|rtf|csv)$'
    $progExt   = '(?i)^\.(exe|dll|scr|com|pif|msi|cpl|ocx|sys)$'
    $scriptExt = '(?i)^\.(bat|cmd|ps1|vbs|vbe|js|jse|wsf|hta)$'
    $doubleExt = '(?i)\.(pdf|docx?|xlsx?|pptx?|txt|jpe?g|png|gif|bmp|mp3|mp4|avi|mkv|mov|zip|rar|7z)\s*\.(exe|scr|com|pif|bat|cmd|vbs|vbe|js|jse|hta|wsf|lnk)$'
    $activator = '(?i)kmspico|kms[\s_.-]?auto|aact(_x64)?\.exe|re-?loader|hwidgen|windows[\s_.-]?loader|kms[\s_.-]?tools|microsoft[\s_.-]?toolkit|kmsauto'
    $crackName = '(?i)(^|[\s_.\-\[\(])(crack(ed)?|keygen|key[\s_-]?gen|patch(er)?|activator|serial[\s_-]?gen|hack(s|er)?|cheat(s|er)?|injector|trainer|unlocker|bypass|spoofer|executor|mod[\s_-]?menu)([\s_.\-\]\)0-9]|$)'
    $crackFile = '(?i)^(steam_emu\.ini|onlinefix(64)?\.(ini|dll)|codex\.ini|cream_api\.ini|cpy\.ini|3dmgame\.(ini|dll)|ali213\.ini|smartsteamemu\.ini|unsteam\.ini|rld\.ini|skidrow\.ini|empress\.ini|tenoke\.ini|hlm\.ini|steamclient_loader(_x64)?\.(exe|ini)|coldclientloader\.ini|steam_api(64)?\.cdx|valve\.ini)$'
    $mediaDirs = @([Environment]::GetFolderPath('MyPictures'), [Environment]::GetFolderPath('MyVideos'), [Environment]::GetFolderPath('MyMusic')) |
        Where-Object { $_ } | ForEach-Object { (Get-NormPath $_) + '\' }
    $lnkDirs = @($Desktop, $Downloads, (Join-Path $env:PUBLIC 'Desktop')) | Where-Object { $_ } | ForEach-Object { (Get-NormPath $_) + '\' }
    $shell = $null; try { $shell = New-Object -ComObject WScript.Shell } catch { }
    $crackDirs = @{}
    $encDirs = @{}; $ransomNotes = 0
    $ransomNote = '(?i)^(_readme\.txt|how[_ -]?to[_ -]?(decrypt|restore|recover|back)[^\\]*\.(txt|html?|hta|rtf)|[^\\]*decrypt[_ -]?(instructions|my[_ -]?files|files)[^\\]*\.(txt|html?|hta|rtf)|restore[_ -]?(my[_ -]?)?files[^\\]*\.(txt|html?|hta|rtf)|!+[_ -]*read[_ -]*me[_ -]*!+[^\\]*\.(txt|html?|hta|rtf))$'
    $ransomExt  = '(?i)^\.(locked|encrypted|crypted|crypt|crypz|cerber[0-9]?|locky|zepto|odin|wncry|wnry|wcry|wncryt|djvu|ryk|conti|lockbit|akira|blackcat|alphv|hive|babuk|phobos|dharma|makop)$'
    $script:CrackedGames = @()
    $total = 0; $headers = 0

    foreach ($drive in $drives) {
        Write-Host "  Scanning drive $drive (this can take a long time on big drives)..."
        $stack = New-Object System.Collections.Stack
        $stack.Push($drive)
        while ($stack.Count -gt 0) {
            $dir = $stack.Pop()
            $di = New-Object IO.DirectoryInfo $dir
            $subs = @(); $files = @()
            try { $subs = $di.GetDirectories() } catch { }
            try { $files = $di.GetFiles() } catch { }
            foreach ($sd in $subs) {
                if ($sd.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
                if ($sd.Name -ieq '$Recycle.Bin' -or $sd.Name -ieq 'System Volume Information' -or $sd.Name -ieq 'WinSxS') { continue }
                if ($skip.ContainsKey($sd.FullName.TrimEnd('\').ToLowerInvariant())) { continue }
                $stack.Push($sd.FullName)
            }
            foreach ($f in $files) {
                $total++
                if ($total % 100000 -eq 0) { Write-Host ("    {0:N0} files checked..." -f $total) -ForegroundColor DarkGray }
                $name = $f.Name; $ext = $f.Extension; $full = $f.FullName

                if ($name.IndexOf([char]0x202E) -ge 0) {
                    Add-FileFinding 'Disguised file' 'High' $full 'The file name uses a hidden right-to-left character to fake its extension (classic malware trick).' 'File name contains U+202E (RIGHT-TO-LEFT OVERRIDE)'
                    continue
                }
                if ($name -match $doubleExt) {
                    Add-FileFinding 'Disguised file' 'High' $full "Looks like a .$($Matches[1]) file but is really a .$($Matches[2]) program." "Double extension: '.$($Matches[1]).$($Matches[2])' - Windows hides the last one"
                    continue
                }
                if ($ext -match $mediaExt -and $f.Length -gt 1024) {
                    $headers++
                    if (Test-IsWindowsProgram $full) {
                        Add-FileFinding 'Disguised file' 'High' $full "This is a Windows program pretending to be a $ext file." "File header is MZ + PE (Windows executable) but the extension is $ext"
                        continue
                    }
                }
                if ($ext -match $progExt -or $ext -match '(?i)^\.(zip|rar|7z|iso)$') {
                    if ($name -match $activator) {
                        Add-FileFinding 'Crack tool' 'High' $full 'Windows/Office activator (crack). These are one of the most common ways malware gets installed.' "File name matches activator pattern: '$($Matches[0])'"
                        continue
                    }
                    if ($name -match $crackName) {
                        Add-FileFinding 'Crack tool' 'Medium' $full "Crack/cheat/hack tool (name contains '$($Matches[2])'). Such tools very often carry stealers." "File name matches crack/cheat pattern: '$($Matches[2])'"
                        continue
                    }
                }
                if ($name -match $ransomNote) {
                    $ransomNotes++
                    if ($ransomNotes -le 30) {
                        Add-Finding 'Ransomware indicator' 'High' $full 'A ransomware note (ransom/decrypt instructions). Your files may have been encrypted. Do NOT pay; keep the note for identification.' -Tech "File name matches ransom-note pattern"
                    }
                }
                if ($ext -match $ransomExt) { $k = $f.DirectoryName; if ($encDirs.ContainsKey($k)) { $encDirs[$k]++ } else { $encDirs[$k] = 1 } }
                if ($script:ThreatDb.Count -gt 0 -and ($ext -match $progExt -or $ext -match $scriptExt) -and $f.Length -lt 200MB -and
                    ($full -match $UserDirPattern -or $full -match '(?i)\\(Desktop|Documents)\\' -or -not $full.StartsWith($env:SystemDrive, [StringComparison]::OrdinalIgnoreCase))) {
                    $h = $null; try { $h = (Get-FileHash -LiteralPath $full -Algorithm SHA256 -ErrorAction Stop).Hash.ToUpperInvariant() } catch { }
                    if ($h -and $script:ThreatDb.ContainsKey($h)) {
                        $e = $script:ThreatDb[$h]
                        Add-FileFinding 'Known threat (database)' 'High' $full "Exactly the same file as a threat removed before: $($e.Name) ($($e.Category), first seen $($e.FirstSeen))." "SHA256 $h matches the local threat database"
                        continue
                    }
                }
                if ($name -match $crackFile) {
                    $root = $f.DirectoryName
                    if ((Split-Path $root -Leaf) -ieq 'steam_settings') { $root = Split-Path $root -Parent }
                    if (-not $crackDirs.ContainsKey($root.ToLowerInvariant())) { $crackDirs[$root.ToLowerInvariant()] = @($root, $full) }
                    continue
                }
                if (($ext -match $progExt -or $ext -match $scriptExt)) {
                    foreach ($md in $mediaDirs) {
                        if ($full.StartsWith($md, [StringComparison]::OrdinalIgnoreCase)) {
                            Add-FileFinding 'Program in media folder' 'High' $full "A program/script hidden among your pictures, videos or music." "Extension $ext inside $md"
                            break
                        }
                    }
                }
                if ($ext -ieq '.lnk' -and $shell) {
                    $inLnkDir = $false
                    foreach ($ld in $lnkDirs) { if ($full.StartsWith($ld, [StringComparison]::OrdinalIgnoreCase)) { $inLnkDir = $true; break } }
                    if ($inLnkDir -or $f.Directory.Parent -eq $null) {
                        try {
                            $sc = $shell.CreateShortcut($full)
                            $cmd = "`"$($sc.TargetPath)`" $($sc.Arguments)"
                            if ($sc.TargetPath -match '(?i)\\(powershell|pwsh|cmd|mshta|wscript|cscript|rundll32|regsvr32)\.exe$' -and $sc.Arguments -and
                                ($cmd -match $RunningBadCmd -or $cmd -match $LolbinPattern -or $sc.Arguments -match '(?i)https?://|\.(vbs|js|jse|hta|ps1|bat|cmd|dll)\b')) {
                                Add-FileFinding 'Malicious shortcut' 'High' $full 'A shortcut that secretly runs a script/command (used by USB worms and droppers).' "Shortcut target: $cmd"
                            }
                        } catch { }
                    }
                }
                if ($name -ieq 'autorun.inf' -and $f.Directory.Parent -eq $null) {
                    $txt = ''; try { $txt = [IO.File]::ReadAllText($full) } catch { }
                    if ($txt -match '(?im)^\s*(open|shellexecute|shell\\[^=]*\\command)\s*=') {
                        Add-FileFinding 'Malicious shortcut' 'Medium' $full 'autorun.inf that starts a program when the drive is opened (USB worm technique).' 'autorun.inf contains open=/shellexecute='
                    }
                }
            }
        }
    }

    foreach ($k in $encDirs.Keys) {
        if ($encDirs[$k] -ge 20) {
            Add-Finding 'Ransomware indicator' 'High' $k "$($encDirs[$k]) files in this folder have ransomware-style extensions (encrypted files). Nothing was changed." -Tech "Extensions such as .locked/.encrypted/.djvu/.lockbit counted: $($encDirs[$k])"
        }
    }
    foreach ($v in $crackDirs.Values) {
        $root = $v[0]; $ind = $v[1]
        $n = Get-NormPath $root
        $unsafe = (-not $n) -or ($n.Length -le 3) -or ($ProtectedDirs -contains $n) -or
                  $n.StartsWith($env:SystemRoot, [StringComparison]::OrdinalIgnoreCase) -or (($n -split '\\').Count -lt 3)
        if ($unsafe) {
            Add-Finding 'Cracked game' 'Info' $root "Crack files found ($(Split-Path $ind -Leaf)) but this folder is too important to delete automatically." -Tech "Crack indicator: $ind"
        } else {
            Add-Finding 'Cracked game' 'Medium' $root "This game/program is cracked (crack file: $(Split-Path $ind -Leaf)). Cracked games are a top source of stealers and miners." `
                -Tech "Crack indicator file: $ind"
            $script:CrackedGames += [pscustomobject]@{ Path = $root; Indicator = $ind }
        }
    }
    Write-Host ("  Checked {0:N0} files ({1:N0} pictures/videos/documents opened to verify their real type)." -f $total, $headers)
}

# Second, independent engine: Kaspersky Virus Removal Tool (free, portable, different detections than Defender)
function Invoke-SecondOpinion {
    Write-Section 'Second opinion: Kaspersky Virus Removal Tool'
    $dir  = Join-Path $BaseDir 'KVRT'
    $data = Join-Path $dir 'data'
    $exe  = Join-Path $dir 'KVRT.exe'
    New-Item -ItemType Directory -Path $data -Force | Out-Null
    try {
        Write-Host '  Downloading the latest KVRT (about 150 MB)...'
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri 'https://devbuilds.s.kaspersky-labs.com/devbuilds/KVRT/latest/full/KVRT.exe' -OutFile $exe -UseBasicParsing -ErrorAction Stop
    } catch { Write-Host "  Download failed: $_" -ForegroundColor Yellow; return }
    $sig = Get-SigInfo $exe
    if ($sig.Status -ne 'Valid' -or $sig.Signer -notmatch '(?i)Kaspersky') {
        Write-Host "  Downloaded file is not validly signed by Kaspersky ($($sig.Status)). Deleted, not run." -ForegroundColor Red
        Remove-Item -LiteralPath $exe -Force -ErrorAction SilentlyContinue
        return
    }
    $kArgs = @('-accepteula', '-silent', '-adinsilent', '-processlevel', '2', '-d', $data)
    if ($FullScan) { $kArgs += '-allvolumes' }
    Write-Host '  Scanning with KVRT (memory, startup, system and disks). This can take a long time...'
    try {
        $p = Start-Process -FilePath $exe -ArgumentList $kArgs -Wait -PassThru -ErrorAction Stop
        Write-Host "  KVRT finished (exit code $($p.ExitCode)). It quarantines what it finds itself." -ForegroundColor Green
        Write-Host "  KVRT reports: $data\Reports   (run $exe normally to see or restore its quarantine)"
    } catch { Write-Host "  KVRT failed to run: $_" -ForegroundColor Yellow }
}

# ---------------------------------------------------------------- restore mode

if ($Restore) {
    $last = Get-ChildItem -LiteralPath $QRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'manifest.tsv') } |
        Sort-Object Name -Descending | Select-Object -First 1
    if (-not $last) { Write-Host 'Nothing to restore.' -ForegroundColor Yellow; try { Stop-Transcript | Out-Null } catch { }; return }
    Write-Host "Restoring from $($last.FullName)" -ForegroundColor Cyan
    foreach ($line in Get-Content -LiteralPath (Join-Path $last.FullName 'manifest.tsv')) {
        $parts = $line.Split("`t")
        if ($parts.Count -ne 2) { continue }
        $ans = Read-Host "Restore $($parts[0]) ? (y/n)"
        if ($ans -notmatch '^[yY]') { continue }
        try {
            $parent = Split-Path $parts[0] -Parent
            if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
            Move-Item -LiteralPath $parts[1] -Destination $parts[0] -Force -ErrorAction Stop
            Write-Host '  restored' -ForegroundColor Green
        } catch { Write-Host "  failed: $_" -ForegroundColor Red }
    }
    Write-Host 'Registry backups (.reg) and task backups (.xml) are in the same folder.'
    Write-Host 'Double-click a .reg file to restore it. Disabled tasks/services can be re-enabled in Task Scheduler / services.msc.'
    Write-Host 'You can also use System Restore (rstrui.exe) and pick the "SecurityCleaner" restore point.'
    try { Stop-Transcript | Out-Null } catch { }
    return
}

if ($Trust.Count -gt 0 -and -not ($FullScan -or $Clean -or $CleanJunk -or $SecondOpinion)) {
    Write-Host "Saved to $AllowFile. Run the scan again and these will not be touched."
    try { Stop-Transcript | Out-Null } catch { }
    return
}
Write-Host "Protected, never touched: Windows, Program Files, $($InstalledDirs.Count) installed programs, $($Allow.Count - $InstalledDirs.Count) allowlist entries" -ForegroundColor Green

if ($Server.Count -gt 0) {
    Invoke-ServerScan $Server
    try { Stop-Transcript | Out-Null } catch { }
    return
}

if ($JunkOnly) {
    Clear-JunkFiles
    try { Stop-Transcript | Out-Null } catch { }
    return
}

Write-Host "Security Cleaner v$Version - scan started. Nothing is changed during the scan." -ForegroundColor Green

# ---------------------------------------------------------------- 1. Defender status

Write-Section 'Microsoft Defender'
$mpOk = $false
try {
    $mp = Get-MpComputerStatus -ErrorAction Stop
    $mpOk = $true
    if ($mp.AMRunningMode -and $mp.AMRunningMode -ne 'Normal') {
        Add-Finding 'Defender' 'Info' "Defender running mode: $($mp.AMRunningMode)" 'Another antivirus may be active; Defender scans may be limited.'
    }
    if (-not $mp.RealTimeProtectionEnabled -or -not $mp.AntivirusEnabled -or -not $mp.BehaviorMonitorEnabled -or -not $mp.IoavProtectionEnabled) {
        Add-Finding 'Defender' 'High' 'Part of Defender protection is OFF' ("RealTime=$($mp.RealTimeProtectionEnabled) Behavior=$($mp.BehaviorMonitorEnabled) Downloads=$($mp.IoavProtectionEnabled)") `
            -Action 'DefenderEnable' -FixText 'Turn protection back on'
    }
    if ($mp.PSObject.Properties['IsTamperProtected'] -and -not $mp.IsTamperProtected) {
        Add-Finding 'Defender' 'Medium' 'Tamper Protection is OFF' 'Turn it on yourself: Windows Security > Virus & threat protection > Manage settings > Tamper Protection.'
    }
    if ($mp.AntivirusSignatureAge -gt 3) {
        Add-Finding 'Defender' 'Medium' "Virus definitions are $($mp.AntivirusSignatureAge) days old" 'Updated automatically during the scan.'
    }
} catch {
    Add-Finding 'Defender' 'High' 'Microsoft Defender is not available' "$_"
}

$polBase = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender'
$polChecks = @(
    @{ Key = $polBase; Names = 'DisableAntiSpyware','DisableAntiVirus','DisableRoutinelyTakingAction','ServiceKeepAlive' },
    @{ Key = "$polBase\Real-Time Protection"; Names = 'DisableRealtimeMonitoring','DisableBehaviorMonitoring','DisableOnAccessProtection','DisableScanOnRealtimeEnable','DisableIOAVProtection' },
    @{ Key = "$polBase\Spynet"; Names = 'SpynetReporting','SubmitSamplesConsent' },
    @{ Key = "$polBase\Scan"; Names = 'DisableArchiveScanning','DisableRemovableDriveScanning' },
    @{ Key = "$polBase\Signature Updates"; Names = 'ForceUpdateFromMU','DisableUpdateOnStartupWithoutEngine' },
    @{ Key = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Notifications'; Names = 'DisableNotifications','DisableEnhancedNotifications' },
    @{ Key = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'; Names = 'EnableSmartScreen' }
)
foreach ($pc in $polChecks) {
    $p = Get-ItemProperty -LiteralPath $pc.Key -ErrorAction SilentlyContinue
    if (-not $p) { continue }
    foreach ($n in $pc.Names) {
        if ($null -eq $p.$n) { continue }
        $bad = ($n -like 'Disable*' -and $p.$n -eq 1) -or ($n -eq 'SpynetReporting' -and $p.$n -eq 0) -or
               ($n -eq 'SubmitSamplesConsent' -and $p.$n -eq 2) -or ($n -eq 'ServiceKeepAlive' -and $p.$n -eq 0) -or
               ($n -eq 'EnableSmartScreen' -and $p.$n -eq 0)
        if ($bad) {
            $psev = 'High'; if ($n -eq 'EnableSmartScreen') { $psev = 'Medium' }
            Add-KeyFinding 'Defender policy' $psev "$($pc.Key)\$n = $($p.$n)" 'Policy that weakens Windows protection (malware or "optimizer" tools do this).' `
                'RegDeleteValue' @{ Key = $pc.Key; Name = $n } 'Delete this policy value'
        }
    }
}

if ($mpOk) {
    try {
        $pref = Get-MpPreference -ErrorAction Stop
        $excl = @(
            @{ Type = 'Path';      Values = $pref.ExclusionPath },
            @{ Type = 'Process';   Values = $pref.ExclusionProcess },
            @{ Type = 'Extension'; Values = $pref.ExclusionExtension },
            @{ Type = 'IpAddress'; Values = $pref.ExclusionIpAddress }
        )
        foreach ($e in $excl) {
            foreach ($v in @($e.Values)) {
                if (-not $v -or $v -like 'N/A*') { continue }
                $sev = 'Medium'
                if ($v -match '^[A-Za-z]:\\?\*?$' -or $v -match '(?i)\\(AppData|Temp|ProgramData|Users|Windows)\\?' -or
                    $v -match '(?i)^\.?\*?\.?(exe|dll|scr|bat|cmd|ps1|vbs|js|sys|tmp)$' -or
                    $v -match '(?i)(powershell|pwsh|cmd|wscript|cscript|mshta|rundll32|regsvr32|svchost|explorer|conhost|dllhost)\.exe$') { $sev = 'High' }
                Add-KeyFinding 'Defender exclusion' $sev "$($e.Type): $v" 'Defender will NOT scan this. Remove unless you added it yourself on purpose.' `
                    'MpExclusionRemove' @{ Type = $e.Type; Value = $v } 'Remove exclusion'
            }
        }
        if ($pref.PUAProtection -ne 1 -or $pref.MAPSReporting -eq 0 -or $pref.SubmitSamplesConsent -eq 2) {
            Add-Finding 'Defender' 'Medium' 'PUA / cloud protection is not fully on' 'Without these, Defender misses most miners, adware and new malware.' `
                -Action 'MpHarden' -FixText 'Enable PUA blocking and cloud protection'
        }
    } catch { }
    foreach ($sub in 'Paths','Processes','Extensions','IpAddresses') {
        $k = "$polBase\Exclusions\$sub"
        $p = Get-ItemProperty -LiteralPath $k -ErrorAction SilentlyContinue
        if (-not $p) { continue }
        $p.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' } | ForEach-Object {
            Add-KeyFinding 'Defender exclusion (policy)' 'High' "$sub : $($_.Name)" 'Exclusion forced by policy.' `
                'RegDeleteValue' @{ Key = $k; Name = $_.Name } 'Delete this policy exclusion'
        }
    }
}

# ---------------------------------------------------------------- 2. Running processes (miners, fakes, scripts)

Write-Section 'Running processes'
$procs = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)
foreach ($p in $procs) {
    if ($p.ProcessId -in $SelfPids -or $p.ProcessId -le 4) { continue }
    $name = [string]$p.Name; $path = [string]$p.ExecutablePath; $cmd = [string]$p.CommandLine
    if ($cmd -match 'Scan-And-Clean') { continue }
    $base = [IO.Path]::GetFileNameWithoutExtension($name).ToLowerInvariant()
    $label = "$name (PID $($p.ProcessId))"

    if ($base -match "^($MinerNames)" -or $cmd -match $MinerArgs) {
        Add-KeyFinding 'Crypto miner' 'High' $label "$path | $cmd" 'KillProcess' @{ Pid = [int]$p.ProcessId; Name = $name } 'Stop the process'
        if ($path) { Add-FileFinding 'Crypto miner' 'High' $path 'Miner program (running)' }
        continue
    }
    if ($base -match $FakeSysNames) {
        Add-KeyFinding 'Fake system process' 'High' $label "Name imitates a Windows process: $path" 'KillProcess' @{ Pid = [int]$p.ProcessId; Name = $name } 'Stop the process'
        if ($path) { Add-FileFinding 'Fake system process' 'High' $path 'Imitates a Windows process' }
        continue
    }
    if ($SysNames -contains $base -and $path -and -not $path.StartsWith($env:SystemRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
        Add-KeyFinding 'Fake system process' 'High' $label "Windows process running from the WRONG folder: $path" 'KillProcess' @{ Pid = [int]$p.ProcessId; Name = $name } 'Stop the process'
        Add-FileFinding 'Fake system process' 'High' $path "Fake $name"
        continue
    }
    if ($cmd -match $RunningBadCmd) {
        $short = $cmd; if ($short.Length -gt 220) { $short = $short.Substring(0, 220) + '...' }
        Add-KeyFinding 'Malicious script running' 'High' $label $short 'KillProcess' @{ Pid = [int]$p.ProcessId; Name = $name } 'Stop the process'
        Add-ReferencedFileFindings $cmd 'Script file' 'High' "Used by running process $name"
    }
}

Write-Host '  Measuring CPU usage for 8 seconds...'
$cores = [Environment]::ProcessorCount
$cpu1 = @{}
foreach ($pr in Get-Process -ErrorAction SilentlyContinue) { try { $cpu1[$pr.Id] = $pr.TotalProcessorTime.TotalSeconds } catch { } }
Start-Sleep -Seconds 8
foreach ($pr in Get-Process -ErrorAction SilentlyContinue) {
    if (-not $cpu1.ContainsKey($pr.Id) -or $pr.Id -in $SelfPids) { continue }
    try { $delta = $pr.TotalProcessorTime.TotalSeconds - $cpu1[$pr.Id] } catch { continue }
    $pct = [Math]::Round($delta / 8 / $cores * 100, 1)
    if ($pct -lt 15 -or -not $pr.Path) { continue }
    $sig = Get-SigInfo $pr.Path
    if ($sig.Microsoft -or $sig.Status -eq 'Valid') { continue }
    $sev = 'Medium'; if ($pr.Path -match $UserDirPattern) { $sev = 'High' }
    Add-FileFinding 'High CPU (possible miner)' $sev $pr.Path "$($pr.ProcessName) uses $pct% CPU, signature: $($sig.Status). If this is a game you are playing now, skip it."
}

# ---------------------------------------------------------------- 3. Network

Write-Section 'Network'
try {
    $conns = @(Get-NetTCPConnection -State Established -ErrorAction Stop | Where-Object { $_.RemoteAddress -notmatch '^(127\.|::1$|0\.0\.0\.0)' })
    foreach ($c in $conns | Where-Object { $_.RemotePort -in $MinerPorts }) {
        $pr = Get-Process -Id $c.OwningProcess -ErrorAction SilentlyContinue
        if (-not $pr -or $pr.Id -in $SelfPids) { continue }
        $sig = Get-SigInfo $pr.Path
        if ($sig.Microsoft) { continue }
        $sev = 'Medium'; if ($sig.Status -ne 'Valid') { $sev = 'High' }
        Add-KeyFinding 'Mining pool connection' $sev "$($pr.ProcessName) (PID $($pr.Id)) -> $($c.RemoteAddress):$($c.RemotePort)" "$($pr.Path) signature: $($sig.Status)" `
            'KillProcess' @{ Pid = [int]$pr.Id; Name = $pr.ProcessName } 'Stop the process'
        if ($pr.Path) { Add-FileFinding 'Mining pool connection' $sev $pr.Path "Connected to mining port $($c.RemotePort)" }
    }
    foreach ($g in $conns | Group-Object OwningProcess) {
        $pr = Get-Process -Id $g.Name -ErrorAction SilentlyContinue
        if (-not $pr -or -not $pr.Path -or $pr.Path -notmatch $UserDirPattern -or $pr.Id -in $SelfPids) { continue }
        $sig = Get-SigStatus $pr.Path
        if ($sig -eq 'Valid') { continue }
        $remotes = ($g.Group | ForEach-Object { "$($_.RemoteAddress):$($_.RemotePort)" } | Select-Object -Unique -First 5) -join ', '
        Add-FileFinding 'Unsigned program online' 'High' $pr.Path "PID $($pr.Id) signature: $sig, connected to $remotes"
    }
} catch { }

# ---------------------------------------------------------------- 4. Persistence

Write-Section 'Startup entries (Run keys, Winlogon, IFEO, AppInit)'
$runKeys = @(
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce',
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer\Run',
    'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Windows',
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
        # HKCU\...\Windows NT\CurrentVersion\Windows holds many settings - only Load/Run are autostarts
        if ($k -like '*Windows NT\CurrentVersion\Windows' -and $prop.Name -notin 'Load','Run') { continue }
        $cmd = [string]$prop.Value
        if (-not $cmd.Trim()) { continue }
        $reasons = @(Test-SuspiciousCommand $cmd)
        $sev = 'Info'
        if ($reasons.Count -gt 0) { $sev = 'Medium' }
        if (($reasons -match 'LOLBin|script-type|miner').Count -gt 0 -or $reasons.Count -gt 1) { $sev = 'High' }
        $detail = $cmd; if ($reasons) { $detail = "$cmd  <-- " + ($reasons -join '; ') }
        Add-KeyFinding 'Run key' $sev "$($prop.Name)  [$k]" $detail 'RegDeleteValue' @{ Key = $k; Name = $prop.Name } 'Remove startup entry'
        if ($sev -ne 'Info') { Add-ReferencedFileFindings $cmd 'Startup file' $sev "Started by Run key $($prop.Name)" }
    }
}

$wlKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
$wl = Get-ItemProperty -LiteralPath $wlKey -ErrorAction SilentlyContinue
if ($wl) {
    if ($wl.Shell -and $wl.Shell.Trim() -ine 'explorer.exe') {
        Add-KeyFinding 'Winlogon' 'High' "Shell = $($wl.Shell)" 'Should be explorer.exe' 'RegSetValue' @{ Key = $wlKey; Name = 'Shell'; Value = 'explorer.exe' } 'Reset to explorer.exe'
    }
    if ($wl.Userinit -and ($wl.Userinit.Trim().TrimEnd(',') -ine "$env:SystemRoot\system32\userinit.exe")) {
        Add-KeyFinding 'Winlogon' 'High' "Userinit = $($wl.Userinit)" "Should be $env:SystemRoot\system32\userinit.exe," 'RegSetValue' @{ Key = $wlKey; Name = 'Userinit'; Value = "$env:SystemRoot\system32\userinit.exe," } 'Reset Userinit'
    }
}
$wlUser = Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Winlogon' -ErrorAction SilentlyContinue
if ($wlUser -and $wlUser.Shell) {
    Add-KeyFinding 'Winlogon' 'High' "User Shell = $($wlUser.Shell)" 'Per-user shell replacement (malware trick)' 'RegDeleteValue' @{ Key = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Winlogon'; Name = 'Shell' } 'Remove user shell override'
}

Get-ChildItem -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options' -ErrorAction SilentlyContinue | ForEach-Object {
    $dbg = (Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue).Debugger
    if ($dbg) {
        $k = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\' + $_.PSChildName
        $img = $_.PSChildName.Trim("'").ToLowerInvariant()
        $sev = 'High'; $why = 'Launching this program runs something else instead (often used to block antivirus).'
        $blocksSecurity = $img -match '(?i)^(msmpeng|mpcmdrun|msascui|securityhealth\w*|smartscreen|mrt|mbam\w*|avp\w*|kvrt|esets\w*|egui|avast\w*|avg\w*|bdagent|norton\w*|mcafee\w*|hijackthis|autoruns\w*|procexp\w*|procmon\w*|taskmgr|regedit|rstrui|cmd|powershell|msert|mpsigstub)(\.exe)?$'
        if (-not $blocksSecurity -and $dbg -match '(?i)^("?C:\\WINDOWS\\System32\\)?(taskkill|systray|dllhost)\.exe') {
            $sev = 'Medium'; $why = 'Blocks a Windows telemetry/background program. Usually done by "optimizer"/privacy tweak tools, not malware. Removing it is harmless.'
        }
        if ($blocksSecurity) { $why = 'Blocks a SECURITY or system tool from starting - typical malware trick.' }
        Add-KeyFinding 'IFEO hijack' $sev "$($_.PSChildName) -> $dbg" $why `
            'RegDeleteValue' @{ Key = $k; Name = 'Debugger' } 'Remove Debugger hijack'
    }
}
Get-ChildItem -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SilentProcessExit' -ErrorAction SilentlyContinue | ForEach-Object {
    $mon = (Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue).MonitorProcess
    if ($mon) {
        Add-KeyFinding 'SilentProcessExit hijack' 'High' "$($_.PSChildName) -> $mon" 'Runs a program whenever this one closes.' `
            'RegDeleteValue' @{ Key = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SilentProcessExit\' + $_.PSChildName; Name = 'MonitorProcess' } 'Remove hijack'
    }
}

foreach ($k in 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows NT\CurrentVersion\Windows') {
    $p = Get-ItemProperty -LiteralPath $k -ErrorAction SilentlyContinue
    if ($p -and $p.AppInit_DLLs -and ([string]$p.AppInit_DLLs).Trim()) {
        $sev = 'Medium'; if ($p.LoadAppInit_DLLs -eq 1) { $sev = 'High' }
        Add-KeyFinding 'AppInit_DLLs' $sev "$($p.AppInit_DLLs)" 'DLL injected into every program.' 'RegSetValue' @{ Key = $k; Name = 'AppInit_DLLs'; Value = '' } 'Clear AppInit_DLLs'
    }
}

Write-Section 'Startup folders'
$startupDirs = @(
    (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'),
    (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\StartUp')
)
$wsh = $null
try { $wsh = New-Object -ComObject WScript.Shell } catch { }
foreach ($dir in $startupDirs) {
    Get-ChildItem -LiteralPath $dir -Force -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'desktop.ini' } | ForEach-Object {
        $target = $_.FullName; $args2 = ''
        if ($_.Extension -ieq '.lnk' -and $wsh) {
            try { $sc = $wsh.CreateShortcut($_.FullName); $target = $sc.TargetPath; $args2 = $sc.Arguments } catch { }
        }
        $reasons = @(Test-SuspiciousCommand ("`"$target`" $args2"))
        $sev = 'Info'
        if ($_.Extension -match '(?i)^\.(vbs|vbe|js|jse|hta|wsf|scr|pif|ps1|bat|cmd|exe|com)$') { $sev = 'High'; $reasons += 'program/script placed directly in Startup folder' }
        elseif ($reasons.Count -gt 0) { $sev = 'Medium' }
        Add-FileFinding 'Startup folder' $sev $_.FullName ("-> $target $args2 " + ($reasons -join '; '))
        if ($sev -ne 'Info') { Add-ReferencedFileFindings ("`"$target`" $args2") 'Startup file' $sev "Target of startup item $($_.Name)" }
    }
}

Write-Section 'Scheduled tasks'
foreach ($t in Get-ScheduledTask -ErrorAction SilentlyContinue) {
    $isMs = $t.TaskPath -like '\Microsoft\*'
    foreach ($a in @($t.Actions)) {
        if (-not $a.PSObject.Properties['Execute'] -or -not $a.Execute) { continue }
        $cmd = "`"$($a.Execute.Trim().Trim('"'))`" $($a.Arguments)"
        $reasons = @(Test-SuspiciousCommand $cmd)
        if ($reasons.Count -eq 0) { continue }
        # tasks under \Microsoft\ need a strong signal - malware hides there, but so do legit tasks
        if ($isMs -and ($reasons -match 'user folder|miner').Count -eq 0 -and $cmd -notmatch $RunningBadCmd) { continue }
        if ($t.Settings.Hidden) { $reasons += 'hidden task' }
        # a hidden PowerShell window alone is common for vendor tasks (Intel, ASUS...); High needs a stronger signal
        $sev = 'Medium'
        if (($reasons -match 'user folder|script-type|hidden task|miner').Count -gt 0 -or $cmd -match $RunningBadCmd -or $isMs) { $sev = 'High' }
        $wd = ''; if ($a.WorkingDirectory) { $wd = "  (folder: $($a.WorkingDirectory))" }
        Add-KeyFinding 'Scheduled task' $sev "$($t.TaskPath)$($t.TaskName)" ("$cmd$wd  <-- " + ($reasons -join '; ')) `
            'TaskDisable' @{ Path = $t.TaskPath; Name = $t.TaskName } 'Back up and disable task'
        Add-ReferencedFileFindings $cmd 'Task file' $sev "Started by task $($t.TaskName)"
    }
}

Write-Section 'Services and drivers'
foreach ($s in Get-CimInstance Win32_Service -ErrorAction SilentlyContinue) {
    $reasons = @(Test-SuspiciousCommand $s.PathName)
    if ($reasons.Count -eq 0) { continue }
    Add-KeyFinding 'Service' 'High' "$($s.Name) ($($s.DisplayName))" ("$($s.PathName)  <-- " + ($reasons -join '; ')) `
        'ServiceDisable' @{ Name = $s.Name } 'Stop and disable service'
    Add-ReferencedFileFindings $s.PathName 'Service file' 'High' "Binary of service $($s.Name)"
}
foreach ($d in Get-CimInstance Win32_SystemDriver -ErrorAction SilentlyContinue) {
    $dp = [string]$d.PathName
    $dp = $dp -replace '^\\\?\?\\', '' -replace '(?i)^\\SystemRoot\\', "$env:SystemRoot\" -replace '(?i)^system32\\', "$env:SystemRoot\System32\"
    if ($dp -match $UserDirPattern) {
        $dsig = Get-SigStatus $dp
        if ($dsig -eq 'Valid') {
            Add-Finding 'Driver' 'Info' "$($d.Name) ($($d.State))" "Signed driver loaded from $dp. Normal for hardware tools (CPU-Z, Armoury Crate, fan/RGB/monitoring software)."
        } else {
            Add-KeyFinding 'Driver' 'High' "$($d.Name) ($($d.State))" "UNSIGNED kernel driver loaded from a user folder: $dp (signature: $dsig)" 'ServiceDisable' @{ Name = $d.Name } 'Disable driver (takes effect after restart)'
            Add-FileFinding 'Driver file' 'High' $dp "Driver $($d.Name)"
        }
    } elseif ($d.Name -match '(?i)winring0' -or $dp -match '(?i)winring0') {
        Add-Finding 'Driver' 'Medium' "$($d.Name) ($($d.State)) $dp" 'WinRing0 is used by crypto miners (also by some fan/RGB/monitoring tools). If you do not use such a tool, it is suspicious.'
    }
}

Write-Section 'WMI persistence'
Get-CimInstance -Namespace root\subscription -ClassName __EventConsumer -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -ne 'SCM Event Log Consumer' } | ForEach-Object {
        $what = [string]$_.CommandLineTemplate; if (-not $what) { $what = [string]$_.ScriptText }; if (-not $what) { $what = [string]$_.ExecutablePath }
        Add-KeyFinding 'WMI consumer' 'High' "$($_.CimClass.CimClassName): $($_.Name)" $what.Substring(0, [Math]::Min(200, $what.Length)) `
            'WmiRemove' @{ Name = $_.Name } 'Remove WMI consumer and its binding'
    }

Write-Section 'PowerShell profiles'
$profiles = @(
    "$env:SystemRoot\System32\WindowsPowerShell\v1.0\profile.ps1",
    "$env:SystemRoot\System32\WindowsPowerShell\v1.0\Microsoft.PowerShell_profile.ps1",
    (Join-Path $Documents 'WindowsPowerShell\profile.ps1'),
    (Join-Path $Documents 'WindowsPowerShell\Microsoft.PowerShell_profile.ps1'),
    (Join-Path $Documents 'PowerShell\profile.ps1'),
    (Join-Path $Documents 'PowerShell\Microsoft.PowerShell_profile.ps1')
)
foreach ($pf in $profiles) {
    if (-not (Test-Path -LiteralPath $pf -PathType Leaf)) { continue }
    $txt = Get-Content -LiteralPath $pf -Raw -ErrorAction SilentlyContinue
    $sev = 'Info'
    if ($txt -match $RunningBadCmd -or $txt -match '(?i)Start-Process|Invoke-WebRequest|Net\.WebClient|http') { $sev = 'High' }
    Add-FileFinding 'PowerShell profile' $sev $pf 'Runs every time PowerShell opens. If you did not write it, it is malware.'
}

# ---------------------------------------------------------------- 5. Browsers

Write-Section 'Browsers'
$forceKeys = @(
    'HKLM:\SOFTWARE\Policies\Google\Chrome\ExtensionInstallForcelist',
    'HKCU:\SOFTWARE\Policies\Google\Chrome\ExtensionInstallForcelist',
    'HKLM:\SOFTWARE\Policies\Microsoft\Edge\ExtensionInstallForcelist',
    'HKCU:\SOFTWARE\Policies\Microsoft\Edge\ExtensionInstallForcelist',
    'HKLM:\SOFTWARE\Policies\BraveSoftware\Brave\ExtensionInstallForcelist',
    'HKCU:\SOFTWARE\Policies\BraveSoftware\Brave\ExtensionInstallForcelist',
    'HKLM:\SOFTWARE\Policies\Opera Software\Opera\ExtensionInstallForcelist'
)
foreach ($k in $forceKeys) {
    $p = Get-ItemProperty -LiteralPath $k -ErrorAction SilentlyContinue
    if (-not $p) { continue }
    $p.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' } | ForEach-Object {
        Add-KeyFinding 'Forced browser extension' 'High' "$($_.Value)" "Installed by policy ($k). Stealers use this to read passwords and swap crypto addresses." `
            'RegDeleteValue' @{ Key = $k; Name = $_.Name } 'Remove forced extension'
    }
}
$lnkDirs = @($Desktop, (Join-Path $env:PUBLIC 'Desktop'),
    (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'),
    (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs'),
    (Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'))
if ($wsh) {
    foreach ($dir in $lnkDirs) {
        Get-ChildItem -LiteralPath $dir -Recurse -Depth 2 -Filter '*.lnk' -Force -File -ErrorAction SilentlyContinue | ForEach-Object {
            try { $sc = $wsh.CreateShortcut($_.FullName) } catch { return }
            if ($sc.Arguments -match '(?i)--load-extension|--remote-debugging-port|--disable-extensions-except' -or
                ($sc.TargetPath -match '(?i)\\(powershell|cmd|mshta|wscript|cscript)\.exe$' -and $_.Name -match '(?i)chrome|edge|brave|opera|firefox|discord|steam')) {
                Add-FileFinding 'Hijacked shortcut' 'High' $_.FullName "-> $($sc.TargetPath) $($sc.Arguments)"
            }
        }
    }
}

# ---------------------------------------------------------------- 6. Network settings

Write-Section 'Hosts file, proxy, Windows Update'
$hostsPath = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
$hostsLines = @(Get-Content -LiteralPath $hostsPath -ErrorAction SilentlyContinue | Where-Object { $_.Trim() -and -not $_.Trim().StartsWith('#') })
$devLine = '^\s*(127\.0\.0\.1|::1|0\.0\.0\.0)\s+[\w.-]+\.(local|test|localhost|lan|dev\.local|internal)(\s|#|$)'
$realHosts = @($hostsLines | Where-Object { $_ -notmatch $devLine })
if ($hostsLines.Count -gt 0 -and $realHosts.Count -eq 0) {
    Add-Finding 'Hosts file' 'Info' "$($hostsLines.Count) local development entries" 'Only .local/.test sites pointing to this PC (XAMPP/Laragon etc.). Harmless.'
}
$hostsLines = $realHosts
if ($hostsLines.Count -gt 0) {
    $sev = 'Medium'
    if ($hostsLines -match '(?i)microsoft|windowsupdate|defender|virustotal|malwarebytes|kaspersky|eset|avast|avg|bitdefender|norton|mcafee|steam|discord|google|github') { $sev = 'High' }
    Add-Finding 'Hosts file' $sev "$($hostsLines.Count) custom entries" (($hostsLines | Select-Object -First 8) -join ' | ') `
        -Action 'HostsReset' -FixText 'Back up hosts file and reset it to default'
}
$inet = Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue
if ($inet -and ($inet.ProxyEnable -eq 1 -or $inet.AutoConfigURL)) {
    Add-Finding 'Proxy' 'Medium' "Proxy: $($inet.ProxyServer) PAC: $($inet.AutoConfigURL)" 'A proxy can be used to spy on your traffic. Disable unless you set it.' `
        -Action 'ProxyDisable' -FixText 'Disable proxy / PAC'
}
$wu = Get-Service -Name wuauserv -ErrorAction SilentlyContinue
if ($wu -and $wu.StartType -eq 'Disabled') {
    Add-Finding 'Windows Update' 'Medium' 'Windows Update service is disabled' 'Miners and malware disable updates to stay hidden.' `
        -Action 'ServiceEnable' -Data @{ Name = 'wuauserv' } -FixText 'Set Windows Update back to Manual (default)'
}
$wuPol = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' -ErrorAction SilentlyContinue
if ($wuPol -and $wuPol.NoAutoUpdate -eq 1) {
    Add-KeyFinding 'Windows Update' 'Medium' 'NoAutoUpdate policy = 1' 'Automatic updates are turned off by policy.' 'RegDeleteValue' @{ Key = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'; Name = 'NoAutoUpdate' } 'Delete policy value'
}

# ---------------------------------------------------------------- 6b. Security settings / remote access

Write-Section 'Firewall, UAC, accounts, remote access'
try {
    foreach ($fp in Get-NetFirewallProfile -ErrorAction Stop) {
        if (-not $fp.Enabled) {
            Add-KeyFinding 'Firewall' 'High' "Windows Firewall is OFF ($($fp.Name) profile)" 'Malware turns the firewall off so it can be controlled remotely.' `
                'FirewallEnable' @{ Profile = $fp.Name } 'Turn the firewall back on'
        }
    }
} catch { }
try {
    $appFilters = @(Get-NetFirewallApplicationFilter -All -ErrorAction Stop | Where-Object { $_.Program -and $_.Program -ne 'Any' })
    foreach ($af in $appFilters) {
        $prog = [Environment]::ExpandEnvironmentVariables($af.Program)
        if ($prog -notmatch $UserDirPattern) { continue }
        $rule = $af | Get-NetFirewallRule -ErrorAction SilentlyContinue
        if (-not $rule -or $rule.Enabled -ne 'True' -or $rule.Direction -ne 'Inbound' -or $rule.Action -ne 'Allow') { continue }
        $sig = Get-SigStatus $prog
        if ($sig -eq 'Valid') { continue }
        if ($sig -eq 'Missing') {
            Add-Finding 'Firewall rule' 'Info' "$($rule.DisplayName)" "Leftover rule for a program that no longer exists: $prog"
            continue
        }
        Add-KeyFinding 'Firewall rule' 'Medium' "$($rule.DisplayName)" "Allows incoming connections to $prog (signature: $sig). Remote-access malware adds rules like this." `
            'FirewallRuleDisable' @{ Name = $rule.Name } 'Disable this firewall rule'
    }
} catch { }

$uacKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
$uac = Get-ItemProperty -LiteralPath $uacKey -ErrorAction SilentlyContinue
if ($uac) {
    if ($uac.EnableLUA -eq 0) {
        Add-KeyFinding 'UAC' 'High' 'User Account Control is OFF' 'Any program can get admin rights silently. (Takes effect after restart.)' `
            'RegSetValue' @{ Key = $uacKey; Name = 'EnableLUA'; Value = 1 } 'Turn UAC back on'
    }
    if ($uac.ConsentPromptBehaviorAdmin -eq 0) {
        Add-KeyFinding 'UAC' 'Medium' 'UAC never asks for permission' 'Programs get admin rights without a prompt.' `
            'RegSetValue' @{ Key = $uacKey; Name = 'ConsentPromptBehaviorAdmin'; Value = 5 } 'Restore default UAC prompt'
    }
}

try {
    $me = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    foreach ($m in Get-LocalGroupMember -SID 'S-1-5-32-544' -ErrorAction Stop) {
        if ($m.PrincipalSource -ne 'Local' -or $m.SID.Value -eq $me -or $m.SID.Value -like '*-500') { continue }
        $u = Get-LocalUser -SID $m.SID -ErrorAction SilentlyContinue
        if ($u -and $u.Enabled) {
            $sev = 'Medium'; if ($u.Name -match '\$$' -or $u.Name -match '(?i)^(support|admin|sys|help|defaultuser|user)[0-9]*$') { $sev = 'High' }
            Add-Finding 'Admin account' $sev "Extra administrator account: $($m.Name)" 'If you did not create this account, someone may have remote access. Remove it in Settings > Accounts > Other users.'
        }
    }
} catch { }

$rdp = Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -ErrorAction SilentlyContinue
if ($rdp -and $rdp.fDenyTSConnections -eq 0) {
    Add-Finding 'Remote Desktop' 'Info' 'Remote Desktop is enabled' 'If you do not use it, turn it off: Settings > System > Remote Desktop.'
}
$remoteTools = '(?i)^(anydesk|teamviewer|tv_w32|tv_x64|rustdesk|screenconnect|connectwise|ammyy|aa_v3|remcos|splashtop|supremo|radmin|rserver3|rutserv|rfusclient|ultraviewer|dwagent|atera|meshagent|netsupport|client32|tightvnc|tvnserver|winvnc|vncserver)'
foreach ($p in $procs) {
    $b = [IO.Path]::GetFileNameWithoutExtension([string]$p.Name)
    if ($b -match $remoteTools) {
        $sev = 'Info'; $extra = 'Remote-control program running. Fine if YOU installed it; otherwise someone can control your PC.'
        if ($b -match '(?i)^(remcos|rutserv|rfusclient|client32|meshagent)' -or ([string]$p.ExecutablePath -match $UserDirPattern -and (Get-SigStatus $p.ExecutablePath) -ne 'Valid')) {
            $sev = 'High'; $extra = 'Remote-control tool commonly abused by attackers (RAT), running from an unusual place.'
        }
        Add-Finding 'Remote access' $sev "$($p.Name) (PID $($p.ProcessId))" "$($p.ExecutablePath) - $extra"
        if ($sev -eq 'High' -and $p.ExecutablePath) { Add-FileFinding 'Remote access' 'High' $p.ExecutablePath 'Abused remote-control tool' }
    }
}

# ---------------------------------------------------------------- 6c. Rootkits and ransomware protection

Write-Section 'Rootkit checks'
try {
    $bcd = (& bcdedit.exe /enum '{current}' 2>$null) -join "`n"
    if ($bcd -match '(?im)^\s*testsigning\s+Yes') {
        Add-Finding 'Rootkit indicator' 'High' 'Test-signing mode is ON' 'Windows accepts unsigned kernel drivers (used by rootkits and kernel cheats). Turn off: bcdedit /set testsigning off' -Tech 'bcdedit {current}: testsigning Yes'
    }
    if ($bcd -match '(?im)^\s*nointegritychecks\s+Yes') {
        Add-Finding 'Rootkit indicator' 'High' 'Driver signature checks are disabled' 'Windows loads drivers without checking them. Turn on: bcdedit /set nointegritychecks off' -Tech 'bcdedit {current}: nointegritychecks Yes'
    }
} catch { }
foreach ($d in Get-CimInstance Win32_SystemDriver -Filter "State='Running'" -ErrorAction SilentlyContinue) {
    $dp = [string]$d.PathName
    $dp = $dp -replace '^\\\?\?\\', '' -replace '(?i)^\\SystemRoot\\', "$env:SystemRoot\" -replace '(?i)^system32\\', "$env:SystemRoot\System32\"
    if (-not $dp -or -not (Test-Path -LiteralPath $dp -PathType Leaf)) { continue }
    $sig = Get-SigStatus $dp
    if ($sig -in 'NotSigned', 'HashMismatch') {
        Add-Finding 'Rootkit indicator' 'High' "$($d.Name)" "A running kernel driver has NO valid signature: $dp. Possible rootkit - verify before trusting it." -Tech "Authenticode status: $sig"
    }
}
if ($mpOk) {
    try {
        if ((Get-MpPreference -ErrorAction Stop).EnableControlledFolderAccess -ne 1) {
            Add-Finding 'Ransomware protection' 'Info' 'Controlled folder access is off' 'Optional: Windows Security > Ransomware protection. It can block some games from saving, so it is not turned on automatically.'
        }
    } catch { }
}

# ---------------------------------------------------------------- 7. Files

Write-Section 'Suspicious files in user folders'
$now = Get-Date
$fileRoots = @(
    @{ Path = $env:APPDATA;      Depth = 1 },
    @{ Path = $env:LOCALAPPDATA; Depth = 1 },
    @{ Path = $env:TEMP;         Depth = 2 },
    @{ Path = $env:ProgramData;  Depth = 1 },
    @{ Path = $env:PUBLIC;       Depth = 3 }
)
$scriptExt = '(?i)^\.(vbs|vbe|js|jse|hta|wsf|scr|pif)$'
$softExt   = '(?i)^\.(ps1|bat|cmd)$'
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
                    $hid = ''; if ($hidden) { $hid = ', HIDDEN' }
                    Add-FileFinding 'Unsigned program' $sev $_.FullName "signature: $sig, modified $($_.LastWriteTime)$hid"
                }
            }
        }
}

Write-Host '  Looking for miner programs and configs...'
foreach ($root in @($env:APPDATA, $env:LOCALAPPDATA, $env:ProgramData, $env:TEMP, $env:PUBLIC) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }) {
    Get-ChildItem -LiteralPath $root -Recurse -Depth 4 -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
        $n = $_.Name.ToLowerInvariant()
        if ($_.Extension -match '(?i)^\.(exe|dll|sys)$' -and $n -match "^($MinerNames)") {
            Add-FileFinding 'Crypto miner' 'High' $_.FullName 'Miner program'
        } elseif ($n -match '(?i)^winring0(x64)?\.sys$') {
            Add-FileFinding 'Crypto miner' 'High' $_.FullName 'WinRing0 driver in a user folder (typical for miners)'
        } elseif ($_.Extension -ieq '.json' -and $_.Length -lt 200KB) {
            $j = $null; try { $j = [IO.File]::ReadAllText($_.FullName) } catch { }
            if ($j -and $j -match '"donate-level"|stratum\+(tcp|ssl)://|"pools"\s*:\s*\[\s*\{[^}]*"url"') {
                Add-FileFinding 'Crypto miner' 'High' $_.FullName 'Miner configuration file'
            }
        }
    }
}

Write-Host '  Looking for fake documents (double extensions) in Downloads/Desktop...'
foreach ($root in @($Downloads, $Desktop, $Documents) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }) {
    Get-ChildItem -LiteralPath $root -Recurse -Depth 3 -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '(?i)\.(pdf|docx?|xlsx?|pptx?|txt|jpe?g|png|gif|mp3|mp4|avi|mkv|zip|rar|7z)\s*\.(exe|scr|com|pif|bat|cmd|vbs|vbe|js|jse|hta|wsf|lnk)$' -or
                       $_.Extension -match '(?i)^\.(scr|pif|vbe|jse|wsf|hta)$' } |
        ForEach-Object { Add-FileFinding 'Fake document / dangerous file' 'High' $_.FullName 'Disguised program (double extension or dangerous type)' }
}

if ($Full -or $Strict) { Invoke-DeepFileScan }

# ---------------------------------------------------------------- 8. Steam

Write-Section 'Steam folder (SteamTools / GreenLuma / DLL hijack)'
if ($SteamPath -and (Test-Path -LiteralPath $SteamPath)) {
    foreach ($dll in 'hid.dll','xinput1_4.dll','xinput1_3.dll','xinput9_1_0.dll','dwmapi.dll','version.dll','winmm.dll','dinput8.dll','winhttp.dll','d3d9.dll','d3d11.dll','dxgi.dll','user32.dll','iphlpapi.dll','wininet.dll','cryptbase.dll','userenv.dll') {
        $p = Join-Path $SteamPath $dll
        if (Test-Path -LiteralPath $p) {
            Add-FileFinding 'Steam DLL hijack' 'High' $p "Not part of Steam. Loaded into Steam automatically (SteamTools/unlocker or malware). Signature: $(Get-SigStatus $p)"
        }
    }
    foreach ($d in 'config\stplug-in','AppList') {
        $p = Join-Path $SteamPath $d
        if (Test-Path -LiteralPath $p) { Add-FileFinding 'Steam unlocker' 'Medium' $p 'SteamTools/GreenLuma data folder (unlocker, can get the account banned).' }
    }
    Get-ChildItem -LiteralPath $SteamPath -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '(?i)greenluma|dllinjector|steamtools|st-setup|stplug|luatools|millennium' -or
                       ($_.Extension -match '(?i)^\.(vbs|js|bat|cmd|ps1|scr)$') } |
        ForEach-Object { Add-FileFinding 'Steam unlocker' 'Medium' $_.FullName 'Unlocker/injector or script file in Steam folder' }
} else {
    Write-Host '  Steam not found.'
}

# ---------------------------------------------------------------- 9. FiveM

Write-Section 'FiveM client and server resources'
$fivemApp = Join-Path $env:LOCALAPPDATA 'FiveM\FiveM.app'
foreach ($sub in 'plugins','mods') {
    $p = Join-Path $fivemApp $sub
    Get-ChildItem -LiteralPath $p -Recurse -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -match '(?i)^\.(dll|asi|exe)$' } |
        ForEach-Object { Add-FileFinding 'FiveM client' 'Medium' $_.FullName "Injected module in FiveM $sub (cheats/mods often carry stealers). Signature: $(Get-SigStatus $_.FullName)" }
}

$resRoots = @($ScanPaths) + @($Downloads, $Desktop, $Documents, 'C:\txData', 'C:\FXServer') |
    Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique

$resourceDirs = @{}
foreach ($root in $resRoots) {
    Write-Host "  Looking for FiveM resources in $root"
    Get-ChildItem -LiteralPath $root -Recurse -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ieq 'fxmanifest.lua' -or $_.Name -ieq '__resource.lua' } |
        ForEach-Object { $resourceDirs[$_.DirectoryName.ToLowerInvariant()] = $_.DirectoryName }
}
Write-Host "  Found $($resourceDirs.Count) resource(s)"

$scannedFiles = @{}
foreach ($dir in $resourceDirs.Values) {
    Get-ChildItem -LiteralPath $dir -Recurse -File -Force -ErrorAction SilentlyContinue |
        Where-Object { ($_.Extension -ieq '.lua' -or $_.Extension -ieq '.js') -and $_.Length -lt 5MB } | ForEach-Object {
            $fp = $_.FullName
            if ($scannedFiles.ContainsKey($fp.ToLowerInvariant())) { return }
            $scannedFiles[$fp.ToLowerInvariant()] = $true
            $t = $null
            try { $t = [IO.File]::ReadAllText($fp) } catch { return }
            if (-not $t) { return }

            $isJs = $_.Extension -ieq '.js'
            # bundled UI code (NUI) legitimately contains eval/fetch - only strong signals count there
            # official FXServer files and big bundles (yarn, webpack, oxmysql build.js...) contain every pattern legitimately
            $isOfficial = $fp -match '(?i)\\citizen\\system_resources\\'
            $isBundle = $isOfficial -or ($isJs -and ($fp -match '(?i)\\(node_modules|html|ui|web|nui|dist|build|yarn|webpack)\\' -or
                        $_.Name -match '(?i)\.min\.js$' -or $_.Length -gt 300KB))
            $dec = Expand-Obfuscation $t
            # encoding that reveals new code keywords/URLs = someone is hiding what the script does
            $hidden = ($dec -ne $t) -and ([regex]::Matches($dec, $hiddenKw).Count -gt [regex]::Matches($t, $hiddenKw).Count)
            $all = $t + "`n" + $dec

            $reasons = @(); $sev = $null
            $hex = [regex]::Matches($t, '\\x[0-9a-fA-F]{2}').Count
            $hasHttp = $all -match $httpRx
            $hasLoad = $all -match $loadRx
            if ($all -match $knownBad)                              { $reasons += 'known FiveM backdoor panel'; $sev = 'High' }
            # bundles: only a Discord webhook next to server secrets is strong enough
            if ($all -match $stealRx -and ($all -match $webhookRx -or ($hasHttp -and -not $isBundle))) { $reasons += 'reads server keys/passwords and sends them out'; $sev = 'High' }
            if (-not $isBundle -and $hidden)                        { $reasons += 'network/exec code HIDDEN with encoding'; $sev = 'High' }
            if (-not $isBundle -and $isJs -and $t -match '\beval\s*\(' -and $t -match $b64Rx) { $reasons += 'eval of base64 data'; $sev = 'High' }
            if (-not $isBundle) {
                if ($hasHttp -and $hasLoad)                         { $reasons += 'downloads code from the internet and runs it'; $sev = 'High' }
                if ($hasLoad -and ($hex -gt 30 -or $t -match $charRx)) { $reasons += "runs obfuscated code (hex escapes: $hex)"; $sev = 'High' }
                if (-not $sev -and $hex -gt 100)                    { $reasons += "heavily obfuscated ($hex hex escapes)"; $sev = 'Medium' }
                if ($all -match $execRx)                            { $reasons += 'runs system commands'; if (-not $sev) { $sev = 'Medium' } }
                if (-not $isJs -and ($t -split "`n" | Where-Object { $_.Length -gt 3000 } | Select-Object -First 1)) {
                    $reasons += 'very long single line (obfuscation)'; if (-not $sev) { $sev = 'Medium' }
                }
            }
            if (-not $sev) { return }

            $lineInfo = ''
            $lines = $t -split "`n"
            for ($i = 0; $i -lt $lines.Count; $i++) {
                $ln = $lines[$i]
                if ($ln -match $knownBad -or $ln -match $loadRx -or $ln -match $execRx -or $ln -match $charRx -or $ln -match $stealRx -or $ln -match '(\\x[0-9a-fA-F]{2}){8,}') {
                    $snip = $ln.Trim(); if ($snip.Length -gt 140) { $snip = $snip.Substring(0, 140) + '...' }
                    $lineInfo = " | line $($i + 1): $snip"; break
                }
            }
            Add-FileFinding 'FiveM backdoor' $sev $fp (($reasons -join '; ') + $lineInfo)
        }
}
Write-Host "  Scanned $($scannedFiles.Count) script file(s)"

# ---------------------------------------------------------------- 10. Defender scan + history

if ($mpOk -and -not $SkipDefenderScan) {
    Write-Section 'Defender scan (this can take a while)'
    try { Write-Host '  Updating definitions...'; Update-MpSignature -ErrorAction Stop } catch { Write-Host "  Update failed: $_" -ForegroundColor Yellow }
    if ($Strict) {
        try {
            Set-MpPreference -MAPSReporting Advanced -SubmitSamplesConsent SendSafeSamples -CloudBlockLevel High -CloudExtendedTimeout 50 -ErrorAction Stop
            $script:CloudHardened = $true
            Write-Host '  Cloud protection set to High: new and unknown threats are analysed by Microsoft in real time.'
        } catch { Write-Host "  Could not raise cloud protection: $_" -ForegroundColor Yellow }
    }
    if ($Full -and -not $Strict) {
        try { Set-MpPreference -PUAProtection Enabled -ErrorAction Stop; Write-Host '  PUA detection turned ON (finds cracks, keygens, hack tools, adware).' } catch { }
    }
    try {
        if ($FullScan) { Write-Host '  Full scan (can take 30-90 minutes)...'; Start-MpScan -ScanType FullScan -ErrorAction Stop }
        else { Write-Host '  Quick scan...'; Start-MpScan -ScanType QuickScan -ErrorAction Stop }
    } catch { Write-Host "  Scan error: $_" -ForegroundColor Yellow }
    if (-not $FullScan) {
        $customPaths = @($ScanPaths) + @($Downloads, $Desktop, $env:APPDATA, $env:LOCALAPPDATA, $env:TEMP, $env:ProgramData, $SteamPath) + @($resourceDirs.Values)
        # auto mode = fast: the quick scan already covers memory, startup and system locations
        if ($Auto) { $customPaths = @($ScanPaths) + @($Downloads, $env:TEMP) }
        foreach ($p in ($customPaths | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique)) {
            Write-Host "  Custom scan: $p"
            try { Start-MpScan -ScanType CustomScan -ScanPath $p -ErrorAction Stop } catch { Write-Host "    error: $_" -ForegroundColor Yellow }
        }
    }
}

if ($SecondOpinion) { Invoke-SecondOpinion }

if ($mpOk) {
    try {
        $threats = @(Get-MpThreat -ErrorAction SilentlyContinue)
        $detections = @(Get-MpThreatDetection -ErrorAction Stop)
        # 2 cleaned, 3 quarantined, 4 removed, 6 blocked = handled. 5 = "Allowed" by the user, which is exactly what cracks ask you to do.
        $pending = @($detections | Where-Object { $_.ThreatStatusID -notin 2, 3, 4, 6 })
        foreach ($d in $detections | Sort-Object InitialDetectionTime -Descending | Select-Object -First 50) {
            $name = ($threats | Where-Object { $_.ThreatID -eq $d.ThreatID } | Select-Object -First 1).ThreatName
            if (-not $name) { $name = "ThreatID $($d.ThreatID)" }
            $sev = 'Info'; $state = 'handled'
            if ($d.ThreatStatusID -notin 2, 3, 4, 6) { $sev = 'High'; $state = 'NOT removed' }
            if ($d.ThreatStatusID -eq 5) { $state = 'ALLOWED by user' }
            Add-Finding 'Defender detection' $sev "$name ($state)" ("{0} | {1}" -f $d.InitialDetectionTime, (($d.Resources | Select-Object -First 3) -join ' ; '))
        }
        if ($pending.Count -gt 0) {
            Add-Finding 'Defender' 'High' "$($pending.Count) threat(s) still waiting for action" '' -Action 'MpThreatRemove' -FixText 'Let Defender remove all detected threats'
        }
        $allowed = @($pref.ThreatIDDefaultAction_Ids | Where-Object { $_ })
        for ($i = 0; $i -lt $allowed.Count; $i++) {
            if (@($pref.ThreatIDDefaultAction_Actions)[$i] -eq 6) {
                Add-KeyFinding 'Defender allowed threat' 'High' "ThreatID $($allowed[$i]) is permanently ALLOWED" 'Defender was told to ignore this threat forever.' `
                    'MpAllowRemove' @{ Id = [long]$allowed[$i] } 'Stop allowing this threat'
            }
        }
    } catch { }
}

# ---------------------------------------------------------------- report

$high = @($Findings | Where-Object Severity -eq 'High')
$med  = @($Findings | Where-Object Severity -eq 'Medium')
$info = @($Findings | Where-Object Severity -eq 'Info')

$out = New-Object System.Collections.Generic.List[string]
$out.Add("Security Cleaner v$Version - scan report - $Stamp - $env:COMPUTERNAME")
$out.Add("High: $($high.Count)   Medium: $($med.Count)   Info: $($info.Count)")
$out.Add('High = very likely malware. Medium = suspicious, check it. Info = for your information, never touched.')
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
if ($high.Count -eq 0 -and $med.Count -eq 0) { Write-Host '  Nothing suspicious found.' -ForegroundColor Green }

# ---------------------------------------------------------------- clean

function Invoke-Fix($f) {
    $d = $f.Data
    switch ($f.Action) {
        'Quarantine'        { Add-ThreatDbEntry $d.Path $f.Category $f.Detail; Move-ToQuarantine $d.Path }
        'KillProcess'       {
            $pr = Get-Process -Id $d.Pid -ErrorAction SilentlyContinue
            if (-not $pr) { return }
            if ($pr.Id -in $SelfPids) { throw 'skipped for safety: this is the scanner itself' }
            if ($CriticalProcs -contains $pr.ProcessName.ToLowerInvariant() -and $pr.Path -and $pr.Path.StartsWith($env:SystemRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
                throw 'skipped for safety: critical Windows process'
            }
            Stop-Process -Id $d.Pid -Force -ErrorAction Stop
        }
        'RegDeleteValue'    { Backup-RegKey $d.Key; Remove-ItemProperty -LiteralPath $d.Key -Name $d.Name -Force -ErrorAction Stop }
        'RegSetValue'       { Backup-RegKey $d.Key; Set-ItemProperty -LiteralPath $d.Key -Name $d.Name -Value $d.Value -ErrorAction Stop }
        'TaskDisable'       {
            Initialize-Quarantine
            Export-ScheduledTask -TaskPath $d.Path -TaskName $d.Name | Out-File -LiteralPath (Join-Path $QDir ('task_{0:D4}.xml' -f ($script:QCount++))) -Encoding Unicode
            Stop-ScheduledTask -TaskPath $d.Path -TaskName $d.Name -ErrorAction SilentlyContinue
            Disable-ScheduledTask -TaskPath $d.Path -TaskName $d.Name -ErrorAction Stop | Out-Null
        }
        'ServiceDisable'    {
            if ($d.Name -match $CriticalServices) { throw 'skipped for safety: critical Windows service' }
            Backup-RegKey "HKLM:\SYSTEM\CurrentControlSet\Services\$($d.Name)"
            & sc.exe stop $d.Name 2>&1 | Out-Null
            $o = & sc.exe config $d.Name start= disabled 2>&1
            if ($LASTEXITCODE -ne 0) { throw "sc.exe: $o" }
        }
        'ServiceEnable'     { Set-Service -Name $d.Name -StartupType Manual -ErrorAction Stop }
        'FirewallEnable'    { Set-NetFirewallProfile -Name $d.Profile -Enabled True -ErrorAction Stop }
        'FirewallRuleDisable' { Disable-NetFirewallRule -Name $d.Name -ErrorAction Stop }
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
                'IpAddress' { Remove-MpPreference -ExclusionIpAddress $d.Value -ErrorAction Stop }
            }
        }
        'MpAllowRemove'     { Remove-MpPreference -ThreatIDDefaultAction_Ids $d.Id -ErrorAction Stop }
        'MpThreatRemove'    { Remove-MpThreat -ErrorAction Stop }
        'MpHarden'          { Set-MpPreference -PUAProtection Enabled -MAPSReporting Advanced -SubmitSamplesConsent SendSafeSamples -ErrorAction Stop }
        'DefenderEnable'    { Set-MpPreference -DisableRealtimeMonitoring $false -DisableBehaviorMonitoring $false -DisableIOAVProtection $false -DisableScriptScanning $false -ErrorAction Stop }
        'HostsReset'        {
            Initialize-Quarantine
            Copy-Item -LiteralPath $hostsPath -Destination (Join-Path $QDir 'hosts.backup') -Force -ErrorAction Stop
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
        default { throw 'no automatic fix' }
    }
}

function New-SafetyRestorePoint {
    Write-Host '  Creating a System Restore point first...'
    if (-not (Get-Command Checkpoint-Computer -ErrorAction SilentlyContinue)) {
        Write-Host '  (not available in this PowerShell version - quarantine and .reg backups still protect you)' -ForegroundColor Yellow
        return
    }
    $srKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
    $oldFreq = (Get-ItemProperty -LiteralPath $srKey -ErrorAction SilentlyContinue).SystemRestorePointCreationFrequency
    try {
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
        Set-ItemProperty -LiteralPath $srKey -Name SystemRestorePointCreationFrequency -Value 0 -Type DWord -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description "SecurityCleaner $Stamp" -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        Write-Host '  Restore point created.' -ForegroundColor Green
    } catch {
        Write-Host "  Could not create a restore point ($_). Quarantine and .reg backups still protect you." -ForegroundColor Yellow
    } finally {
        if ($null -eq $oldFreq) { Remove-ItemProperty -LiteralPath $srKey -Name SystemRestorePointCreationFrequency -ErrorAction SilentlyContinue }
        else { Set-ItemProperty -LiteralPath $srKey -Name SystemRestorePointCreationFrequency -Value $oldFreq -ErrorAction SilentlyContinue }
    }
}

# ---------------------------------------------------------------- auto mode
# Confirmed threats (High) that do not remove files are fixed automatically (all reversible).
# Everything that moves or deletes files, and every uncertain (Medium) item, waits for ONE approval at the end.

function Invoke-FixSafe($f) {
    try { Invoke-Fix $f; return 'done' }
    catch { if ("$_" -like 'skipped for safety*') { return "protected: $_" } else { return "failed: $_" } }
}

# ---------------------------------------------------------------- strict mode (-Strict)
# Acts ONLY on confirmed threats, verifies every file is not used by any running program, service or task
# before removing it, never deletes (quarantine only), and writes a detailed report of every operation.

$script:Ops = New-Object System.Collections.Generic.List[object]
function Write-Op([string]$Action, [string]$Target, [string]$Result, [string]$Detail = '') {
    $script:Ops.Add([pscustomobject]@{ Time = (Get-Date -Format 'HH:mm:ss'); Action = $Action; Target = $Target; Result = $Result; Detail = $Detail })
    $c = 'Green'; if ($Result -like 'SKIPPED*') { $c = 'Cyan' } elseif ($Result -like 'FAILED*') { $c = 'Red' }
    Write-Host ("  [{0}] {1}: {2}" -f $Result, $Action, $Target) -ForegroundColor $c
    if ($Detail) { Write-Host "      $Detail" -ForegroundColor DarkGray }
}

# Every file currently used by a running process (loaded module), a service or a scheduled task
function Get-ActiveFileIndex([int[]]$IgnorePids) {
    $idx = @{}
    $addRef = { param($p, $who) if ($p) { $k = $p.Trim('"').ToLowerInvariant(); if (-not $idx.ContainsKey($k)) { $idx[$k] = @() }; $idx[$k] += $who } }
    foreach ($pr in Get-Process -ErrorAction SilentlyContinue) {
        if ($pr.Id -in $IgnorePids -or $pr.Id -le 4) { continue }
        try { foreach ($m in $pr.Modules) { & $addRef $m.FileName "loaded by running program $($pr.ProcessName) (PID $($pr.Id))" } } catch { }
        try { if ($pr.Path) { & $addRef $pr.Path "running program $($pr.ProcessName) (PID $($pr.Id))" } } catch { }
    }
    foreach ($s in Get-CimInstance Win32_Service -ErrorAction SilentlyContinue) {
        foreach ($f in Get-ReferencedFiles $s.PathName) { & $addRef $f "used by service $($s.Name)" }
    }
    foreach ($t in Get-ScheduledTask -ErrorAction SilentlyContinue) {
        foreach ($a in @($t.Actions)) {
            if ($a.PSObject.Properties['Execute'] -and $a.Execute) {
                foreach ($f in Get-ReferencedFiles "`"$($a.Execute.Trim('"'))`" $($a.Arguments)") { & $addRef $f "used by scheduled task $($t.TaskPath)$($t.TaskName)" }
            }
        }
    }
    return $idx
}

if ($Strict) {
    Write-Section 'STRICT cleaning - confirmed threats only, nothing is deleted'
    New-SafetyRestorePoint
    $killCats = '^(Crypto miner|Fake system process|Malicious script running|Mining pool connection)$'
    $fileCats = '^(Disguised file|Crypto miner|Fake system process|Malicious shortcut|Known threat \(database\))$'

    # 1. stop confirmed malicious processes
    $killed = @()
    foreach ($f in @($Findings | Where-Object { $_.Severity -eq 'High' -and $_.Action -eq 'KillProcess' -and $_.Category -match $killCats })) {
        $r = Invoke-FixSafe $f
        if ($r -eq 'done') { $killed += [int]$f.Data.Pid; Write-Op 'Stop malicious process' $f.Item 'DONE' "$($f.Category): $($f.Detail)" }
        else { Write-Op 'Stop malicious process' $f.Item ("SKIPPED - $r") }
    }

    # 2. quarantine confirmed malicious files - only if nothing legitimate is using them
    Write-Host '  Checking which files are in use by programs, services and tasks...'
    $active = Get-ActiveFileIndex $killed
    foreach ($f in @($Findings | Where-Object { $_.Severity -eq 'High' -and $_.Action -eq 'Quarantine' -and $_.Category -match $fileCats })) {
        $p = [string]$f.Data.Path
        $refs = $active[$p.ToLowerInvariant()]
        if ($refs) {
            Write-Op 'Quarantine file' $p 'SKIPPED - in use' ("Still used by: " + (($refs | Select-Object -Unique) -join '; ') + ". Not touched to avoid breaking anything. Run Start-MpWDOScan to remove it safely.")
            continue
        }
        $r = Invoke-FixSafe $f
        if ($r -eq 'done') { Write-Op 'Quarantine file' $p 'DONE' "$($f.Category): $($f.Detail) | Technical: $($f.Tech)" }
        else { Write-Op 'Quarantine file' $p ("SKIPPED - $r") }
    }

    # 3. turn protection back on (only switches protection ON, never off)
    foreach ($f in @($Findings | Where-Object { $_.Severity -eq 'High' -and $_.Action -in 'DefenderEnable', 'FirewallEnable' })) {
        $r = Invoke-FixSafe $f
        Write-Op 'Re-enable protection' $f.Item ($(if ($r -eq 'done') { 'DONE' } else { "SKIPPED - $r" }))
    }

    # 4. threats confirmed by antivirus signatures (Defender quarantines them, restorable from Windows Security)
    if ($mpOk -and @($Findings | Where-Object { $_.Action -eq 'MpThreatRemove' }).Count -gt 0) {
        try {
            foreach ($det in @(Get-MpThreatDetection -ErrorAction Stop)) {
                foreach ($res in @($det.Resources)) { if ([string]$res -match '^file:_(.+)$') { Add-ThreatDbEntry $Matches[1] 'Defender detection' "ThreatID $($det.ThreatID)" } }
            }
        } catch { }
        try { Remove-MpThreat -ErrorAction Stop; Write-Op 'Remove threats detected by Defender' 'Microsoft Defender' 'DONE' 'Signature-confirmed detections sent to Defender quarantine' }
        catch { Write-Op 'Remove threats detected by Defender' 'Microsoft Defender' "FAILED - $_" }
    }

    # 5. temporary files and caches only (in-use files are skipped automatically; Recycle Bin is NOT emptied)
    if ($CleanJunk) {
        $script:JunkCount = 0; $script:JunkFreed = 0
        Clear-JunkFiles -NoPrompt
        Write-Op 'Delete temporary/cache files' 'Temp, crash dumps, error reports, shader/browser/Discord/FiveM caches' 'DONE' ("{0} files, {1} freed. Files in use were skipped. Recycle Bin not touched." -f $script:JunkCount, (Format-Size $script:JunkFreed))
    }

    # 6. everything else is reported only
    $handled = @($script:Ops | ForEach-Object { $_.Target })
    $reportOnly = @($Findings | Where-Object { $_.Severity -ne 'Info' -and $handled -notcontains $_.Item -and $handled -notcontains [string]$_.Data.Path -and
        $_.Action -ne 'MpThreatRemove' -and -not ($_.Action -eq 'KillProcess' -and $_.Category -match $killCats -and $_.Severity -eq 'High') })

    # ---- detailed report
    $done = @($script:Ops | Where-Object Result -eq 'DONE')
    $skipped = @($script:Ops | Where-Object { $_.Result -notlike 'DONE*' })
    $rep = New-Object System.Collections.Generic.List[string]
    $rep.Add("SECURITY CLEANER v$Version - DETAILED STRICT REPORT")
    $rep.Add("Computer: $env:COMPUTERNAME   Started: $Stamp   Finished: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
    $rep.Add('')
    $rep.Add('RULES APPLIED')
    $rep.Add('  - Windows folder, Microsoft-signed files, Program Files, installed programs, critical services/processes: never touched')
    $rep.Add('  - Only confirmed threats were acted on: disguised programs (verified by file header), known miners, fake system')
    $rep.Add('    processes, malicious shortcuts, and antivirus signature detections')
    $rep.Add('  - Every file was checked against running programs, services and scheduled tasks before removal; files in use were skipped')
    $rep.Add('  - Nothing was deleted: files were moved to quarantine; only temporary/cache files were deleted')
    $rep.Add('  - A System Restore point was created before any change')
    $rep.Add('')
    $rep.Add(("SUMMARY: findings High={0} Medium={1}   actions done={2}   skipped={3}   report-only={4}" -f $high.Count, $med.Count, $done.Count, $skipped.Count, $reportOnly.Count))
    $rep.Add('')
    $rep.Add('ACTIONS PERFORMED')
    if ($done.Count -eq 0) { $rep.Add('  (none)') }
    foreach ($o in $done) { $rep.Add("  $($o.Time)  $($o.Action): $($o.Target)"); if ($o.Detail) { $rep.Add("            $($o.Detail)") } }
    $rep.Add('')
    $rep.Add('SKIPPED FOR SAFETY')
    if ($skipped.Count -eq 0) { $rep.Add('  (none)') }
    foreach ($o in $skipped) { $rep.Add("  $($o.Time)  $($o.Action): $($o.Target)  -> $($o.Result)"); if ($o.Detail) { $rep.Add("            $($o.Detail)") } }
    $rep.Add('')
    $rep.Add('FOUND BUT NOT CHANGED (not 100% confirmed - review these yourself)')
    if ($reportOnly.Count -eq 0) { $rep.Add('  (none)') }
    foreach ($f in $reportOnly) {
        $rep.Add("  [$($f.Severity)] $($f.Category): $($f.Item)")
        if ($f.Detail) { $rep.Add("            Reason: $($f.Detail)") }
        if ($f.Tech) { $rep.Add("            Technical: $($f.Tech)") }
    }
    if ($script:CrackedGames -and $script:CrackedGames.Count -gt 0) {
        $rep.Add(''); $rep.Add('CRACKED GAMES / PROGRAMS (not touched)')
        foreach ($g in $script:CrackedGames) { $rep.Add("  $($g.Path)   (crack file: $($g.Indicator))") }
    }
    $rep.Add('')
    $rep.Add('PROTECTION AGAINST NEW / UNKNOWN THREATS')
    $rep.Add("  Threat database: $ThreatDbFile  (new entries added this run: $($script:ThreatDbAdded), total: $($script:ThreatDb.Count))")
    $rep.Add('  Every confirmed threat is stored by SHA256 and recognised instantly in future scans, even if renamed')
    if ($script:CloudHardened) { $rep.Add('  Defender cloud protection raised to High (real-time analysis of new, unknown files)') }
    $rep.Add('  For the deepest rootkit check run (restarts the PC, ~15 min):  Start-MpWDOScan')
    $rep.Add('')
    $rep.Add('UNDO')
    $rep.Add("  Quarantine and backups: $QDir")
    $rep.Add('  Restore quarantined files: .\Scan-And-Clean.ps1 -Restore')
    $rep.Add('  Restore the whole system: rstrui.exe -> restore point "SecurityCleaner"')
    $rep.Add('  Defender quarantine: Windows Security -> Virus & threat protection -> Protection history')
    $repFile = Join-Path $Desktop "SecurityReport_$Stamp.txt"
    $rep | Out-File -LiteralPath $repFile -Encoding UTF8

    Write-Section 'Done'
    Write-Host ("  Actions done: {0}   Skipped for safety: {1}   Found but not changed: {2}" -f $done.Count, $skipped.Count, $reportOnly.Count) -ForegroundColor Green
    Write-Host "  Detailed report: $repFile" -ForegroundColor Green
    Write-Host '  Restart the PC to finish.' -ForegroundColor Cyan
}

if ($Auto) {
    Write-Section 'Automatic cleaning (nothing is deleted in this step)'
    New-SafetyRestorePoint
    $autoActions = @('KillProcess','WmiRemove','TaskDisable','ServiceDisable','RegDeleteValue','RegSetValue','MpExclusionRemove',
                     'MpAllowRemove','FirewallRuleDisable','HostsReset','ProxyDisable')
    $alwaysSafe  = @('DefenderEnable','MpHarden','FirewallEnable')   # only turn protection back ON
    $order = @{ KillProcess = 0; WmiRemove = 1; TaskDisable = 1; ServiceDisable = 1; RegDeleteValue = 1; RegSetValue = 1 }
    $autoList = @($Findings | Where-Object { $_.Action -and $_.Severity -ne 'Info' -and
        ($_.Action -in $alwaysSafe -or ($_.Severity -eq 'High' -and $_.Action -in $autoActions)) } |
        Sort-Object @{ Expression = { $o = $order[$_.Action]; if ($null -eq $o) { 2 } else { $o } } }, Id)
    if ($autoList.Count -eq 0) { Write-Host '  Nothing to fix automatically.' -ForegroundColor Green }
    foreach ($f in $autoList) {
        $r = Invoke-FixSafe $f
        $c = 'Green'; if ($r -like 'failed*') { $c = 'Red' } elseif ($r -like 'protected*') { $c = 'Cyan' }
        Write-Host ("  [{0}] {1}: {2}" -f $r, $f.FixText, $f.Item) -ForegroundColor $c
    }

    # ---- final step: one approval for everything that removes files or is not certain
    $final = New-Object System.Collections.Generic.List[object]
    foreach ($f in @($Findings | Where-Object { $_.Action -and $_.Severity -ne 'Info' -and $autoList -notcontains $_ } |
                     Sort-Object @{ Expression = { if ($_.Severity -eq 'High') { 0 } else { 1 } } }, Id)) {
        $what = $f.FixText
        if ($f.Action -eq 'Quarantine') { $what = 'Move to quarantine (restorable)' }
        if ($f.Action -eq 'MpThreatRemove') { $what = 'Let Defender remove detected threats' }
        $final.Add([pscustomobject]@{ Sev = $f.Severity; What = $what; Item = $f.Item; Why = "$($f.Category): $($f.Detail)"; Tech = $f.Tech; Finding = $f; Kind = 'fix' })
    }
    if ($CleanJunk) {
        $final.Add([pscustomobject]@{ Sev = 'Info'; What = 'Delete temporary/cache files'; Item = 'Temp, crash dumps, error reports, shader/browser/Discord/FiveM caches'
            Why = 'Only temporary files that Windows and apps recreate. Your files, passwords and settings are not touched.'; Finding = $null; Kind = 'junk' })
        $final.Add([pscustomobject]@{ Sev = 'Info'; What = 'Empty the Recycle Bin'; Item = 'Recycle Bin'
            Why = 'Permanently deletes what is in the Recycle Bin. Skip it if you may need something from there.'; Finding = $null; Kind = 'bin' })
    }

    if ($final.Count -gt 0) {
        Write-Section 'FINAL STEP - your approval is needed'
        Write-Host '  These items remove or move files, or are not 100% certain. Read the reason for each one:' -ForegroundColor Yellow
        for ($i = 0; $i -lt $final.Count; $i++) {
            $x = $final[$i]
            $c = @{ High = 'Red'; Medium = 'Yellow'; Info = 'Gray' }[$x.Sev]
            Write-Host ''
            Write-Host ("  {0,2}. [{1}] {2}" -f ($i + 1), $x.Sev, $x.What) -ForegroundColor $c
            Write-Host ("      Item:   {0}" -f $x.Item)
            $why = $x.Why; if ($why.Length -gt 300) { $why = $why.Substring(0, 300) + '...' }
            Write-Host ("      Reason: {0}" -f $why) -ForegroundColor DarkGray
            if ($x.PSObject.Properties['Tech'] -and $x.Tech) { Write-Host ("      Technical: {0}" -f $x.Tech) -ForegroundColor DarkGray }
        }
        Write-Host ''
        Write-Host '  y       = approve ALL items above' -ForegroundColor Cyan
        Write-Host '  n       = approve nothing (leave everything as it is)' -ForegroundColor Cyan
        Write-Host '  numbers = approve all EXCEPT these, e.g.  3,5,7' -ForegroundColor Cyan
        $ans = (Read-Host '  Your choice').Trim()
        $skip = @()
        $go = $true
        if ($ans -match '^[nN]') { $go = $false }
        elseif ($ans -match '^[0-9 ,]+$') { $skip = @($ans -split '[ ,]+' | Where-Object { $_ } | ForEach-Object { [int]$_ }) }
        elseif ($ans -notmatch '^[yY]') { $go = $false; Write-Host '  Not understood - nothing was changed.' -ForegroundColor Yellow }
        if ($go) {
            $wantJunk = $false; $wantBin = $false
            for ($i = 0; $i -lt $final.Count; $i++) {
                if ($skip -contains ($i + 1)) { continue }
                $x = $final[$i]
                if ($x.Kind -eq 'junk') { $wantJunk = $true; continue }
                if ($x.Kind -eq 'bin') { $wantBin = $true; continue }
                $r = Invoke-FixSafe $x.Finding
                $c = 'Green'; if ($r -like 'failed*') { $c = 'Red' } elseif ($r -like 'protected*') { $c = 'Cyan' }
                Write-Host ("  {0,2}. [{1}] {2}" -f ($i + 1), $r, $x.Item) -ForegroundColor $c
            }
            if ($wantJunk) { Clear-JunkFiles -NoPrompt -EmptyRecycleBin:$wantBin }
            elseif ($wantBin) { try { Clear-RecycleBin -Force -ErrorAction Stop; Write-Host '  Recycle Bin emptied' } catch { } }
        }
    }
    Write-Host ''
    if (Test-Path -LiteralPath $QDir) { Write-Host "  Quarantine and backups: $QDir  (undo: .\Scan-And-Clean.ps1 -Restore)" }
    if ($script:CrackedGames -and $script:CrackedGames.Count -gt 0) {
        Write-Host ''
        Write-Host '  CRACKED GAMES / PROGRAMS FOUND (not deleted - the tool never deletes folders itself):' -ForegroundColor Yellow
        foreach ($g in $script:CrackedGames) {
            Write-Host "    $($g.Path)" -ForegroundColor Yellow
            Write-Host "      Technical: crack file $($g.Indicator)" -ForegroundColor DarkGray
        }
        Write-Host '  If you want them gone, uninstall them, or paste this command (PERMANENT, check the list first):' -ForegroundColor Yellow
        Write-Host ('  ' + (($script:CrackedGames | ForEach-Object { "Remove-Item -LiteralPath '" + ($_.Path -replace "'", "''") + "' -Recurse -Force" }) -join '; '))
    }
    Write-Host '  Done. Restart the PC to finish.' -ForegroundColor Green
    if ($high.Count -gt 0) { Write-Host '  High items were found - for the deepest check later run:  Start-MpWDOScan  (restarts the PC)' -ForegroundColor Yellow }
}

$fixable = @($Findings | Where-Object { $_.Severity -ne 'Info' -and $_.Action })
if (-not $Clean -and -not $Auto -and -not $Strict -and $fixable.Count -gt 0) {
    $ans = Read-Host "`nFound $($fixable.Count) item(s) that can be cleaned. Start cleaning now? (y/n)"
    if ($ans -match '^[yY]') { $Clean = $true }
}

if ($Clean -and -not $Auto -and -not $Strict -and $fixable.Count -gt 0) {
    Write-Section 'Cleaning'
    New-SafetyRestorePoint
    Write-Host '  For each item: y = fix, n = skip, a = fix this and all remaining, q = stop' -ForegroundColor Cyan
    if ($AutoFixHigh) { Write-Host '  -AutoFixHigh: High items are fixed without asking.' -ForegroundColor Cyan }
    $all = $false; $fixed = 0; $failed = 0; $skippedSafe = 0
    # order: stop processes first, then remove persistence, then quarantine files
    $order = @{ KillProcess = 0; WmiRemove = 1; TaskDisable = 1; ServiceDisable = 1; RegDeleteValue = 1; RegSetValue = 1; Quarantine = 2 }
    $sorted = $fixable | Sort-Object @{ Expression = { $o = $order[$_.Action]; if ($null -eq $o) { 3 } else { $o } } }, @{ Expression = { if ($_.Severity -eq 'High') { 0 } else { 1 } } }, Id
    foreach ($f in $sorted) {
        Write-Host ''
        $c = 'Yellow'; if ($f.Severity -eq 'High') { $c = 'Red' }
        Write-Host ("#{0} [{1}] {2}: {3}" -f $f.Id, $f.Severity, $f.Category, $f.Item) -ForegroundColor $c
        if ($f.Detail) { Write-Host "    $($f.Detail)" -ForegroundColor DarkGray }
        if (-not $all -and -not ($AutoFixHigh -and $f.Severity -eq 'High')) {
            $ans = Read-Host "    $($f.FixText)? (y/n/a/q)"
            if ($ans -match '^[qQ]') { break }
            if ($ans -match '^[aA]') { $all = $true }
            elseif ($ans -notmatch '^[yY]') { continue }
        }
        try { Invoke-Fix $f; $fixed++; Write-Host '    done' -ForegroundColor Green }
        catch {
            if ("$_" -like 'skipped for safety*') { $skippedSafe++; Write-Host "    $_" -ForegroundColor Cyan }
            else { $failed++; Write-Host "    failed: $_" -ForegroundColor Red }
        }
    }
    if ($mpOk) {
        Write-Host ''
        Write-Host '  Final Defender clean-up...'
        try { Remove-MpThreat -ErrorAction SilentlyContinue } catch { }
    }
    Write-Host ''
    Write-Host "  Fixed: $fixed   Failed: $failed   Protected (not touched): $skippedSafe" -ForegroundColor Green
    if (Test-Path -LiteralPath $QDir) { Write-Host "  Quarantine and backups: $QDir  (undo with Restore.bat)" }
    Write-Host '  Restart the PC, then run the scan again to confirm it is clean.' -ForegroundColor Cyan
}

if ($CleanJunk -and -not $Auto -and -not $Strict) { Clear-JunkFiles }

if ($mpOk) {
    $doOffline = $OfflineScan
    if (-not $doOffline -and -not $Auto -and -not $Strict -and ($high.Count -gt 0)) {
        $ans = Read-Host "`nHigh items were found. Run Microsoft Defender OFFLINE scan now? It restarts the PC immediately (~15 min). (y/n)"
        if ($ans -match '^[yY]') { $doOffline = $true }
    }
    if ($doOffline) {
        Write-Host '  Save your work. Restarting into Defender Offline scan in 15 seconds...' -ForegroundColor Yellow
        Start-Sleep -Seconds 15
        try { Stop-Transcript | Out-Null } catch { }
        Start-MpWDOScan
    }
}

Write-Host ''
Write-Host 'IMPORTANT: cracked games and fake tools usually contain password stealers.' -ForegroundColor Yellow
Write-Host 'From ANOTHER clean device (phone), change passwords for: email, Discord, Steam,' -ForegroundColor Yellow
Write-Host 'Rockstar/CFX, banks. Log out all sessions, turn on 2FA, and deauthorize all Steam devices.' -ForegroundColor Yellow
Write-Host 'If High items keep coming back after cleaning, back up your files and reset Windows.' -ForegroundColor Yellow
try { Stop-Transcript | Out-Null } catch { }
