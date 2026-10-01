# ============================================================================
#  setup-extras.ps1 — XyRDP MODE EKSTRA (dijalankan SETELAH setup-rdp.ps1)
# ----------------------------------------------------------------------------
#  Runner: windows-latest (Windows Server 2022), dijalankan sebagai Administrator.
#  Semua langkah BEST-EFFORT: satu langkah gagal TIDAK mematikan sesi.
#
#  Isi:
#   1) Baca konfigurasi dari repo: assets/rdp-extras.json  (bisa diubah dari web)
#   2) LIGHTSHOT   — install otomatis (winget -> installer langsung), auto-run
#   3) TRANSLUCENT — EnableTransparency + TranslucentTB (portable -> winget)
#   4) WALLPAPER   — assets/wallpaper.* di repo (atau WALLPAPER_URL),
#                     dipasang ke profil Default (user RDP) + sesi live
#   5) XYDESK HOST — jalankan https://rdp.xydesk.my.id/host.ps1 otomatis
#   6) VERIFIKASI  — user RDP dipastikan anggota grup Administrators
#   7) Rangkum hasil ke out/rdp-status.json (dibaca dashboard web)
#
#  Catatan: VM ini sekali-pakai. Semua setting per-user ditulis ke profil
#  Default (C:\Users\Default\NTUSER.DAT) supaya OTOMATIS aktif begitu user
#  RDP login pertama kali — bukan cuma untuk akun runner.
# ============================================================================

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'
function Log([string]$m) { Write-Host "[XyRDP:ekstra] $m" }

try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13 } catch {}

$u = if ($env:RDP_USER) { $env:RDP_USER } else { 'xyadmin' }

# ---------- 0. Master switch ----------
$master = $true
if ($env:EXTRAS) {
  $e = $env:EXTRAS.Trim().ToLower()
  if (@('tidak','0','false','no','off','skip','none') -contains $e) { $master = $false }
}
if (-not $master) { Log "EXTRAS='$env:EXTRAS' — semua langkah ekstra dilewati."; exit 0 }

# ---------- 1. Konfigurasi (repo: assets/rdp-extras.json) ----------
function Get-B([object]$o, [string]$n, [bool]$d) {
  $p = $o.PSObject.Properties[$n]
  if ($p -and $null -ne $p.Value) { return [bool]$p.Value }
  return $d
}
function Get-S([object]$o, [string]$n, [string]$d) {
  $p = $o.PSObject.Properties[$n]
  if ($p -and $null -ne $p.Value -and "$($p.Value)".Trim()) { return "$($p.Value)".Trim() }
  return $d
}

$cfg = [pscustomobject]@{
  lightshot       = $true
  translucent     = $true
  translucent_mode= 'clear'   # normal | opaque | clear | blur | acrylic
  wallpaper       = $true
  wallpaper_file  = 'wallpaper.jpg'
  xydesk_host     = $true
}
$cfgPath = Join-Path $env:GITHUB_WORKSPACE 'assets\rdp-extras.json'
if (Test-Path $cfgPath) {
  try {
    $j = Get-Content $cfgPath -Raw | ConvertFrom-Json
    $cfg.lightshot        = Get-B $j 'lightshot'        $true
    $cfg.translucent      = Get-B $j 'translucent'      $true
    $cfg.translucent_mode = (Get-S $j 'translucent_mode' 'clear').ToLower()
    $cfg.wallpaper        = Get-B $j 'wallpaper'        $true
    $cfg.wallpaper_file   = (Get-S $j 'wallpaper_file'  'wallpaper.jpg').ToLower()
    $cfg.xydesk_host      = Get-B $j 'xydesk_host'      $true
    Log "konfigurasi dibaca dari assets/rdp-extras.json"
  } catch { Log "rdp-extras.json tidak bisa dibaca ($($_.Exception.Message)) — pakai default" }
} else {
  Log "assets/rdp-extras.json tidak ada — pakai default (semua ekstra aktif)"
}
if ($env:WALLPAPER_URL) { Log "WALLPAPER_URL diisi dari input workflow — override file di repo" }
Log "mode=$($cfg.translucent_mode) | lightshot=$($cfg.lightshot) | translucent=$($cfg.translucent) | wallpaper=$($cfg.wallpaper) | xydesk_host=$($cfg.xydesk_host)"

# ---------- Helper: profil Default (HKU hive) ----------
$DefHive   = 'HKU\XyRDP_Def'
$DefReg    = 'Registry::HKEY_USERS\XyRDP_Def'
$HiveLoaded = $false
function Open-DefaultHive {
  if ($script:HiveLoaded) { return $true }
  try {
    & reg load $script:DefHive 'C:\Users\Default\NTUSER.DAT' 2>&1 | Out-Null
    Start-Sleep -Milliseconds 500
    if (Test-Path $script:DefReg) { $script:HiveLoaded = $true; Log 'profil Default di-load (setting akan ikut user RDP saat login pertama)' }
    return $script:HiveLoaded
  } catch { Log "gagal load profil Default: $($_.Exception.Message)"; return $false }
}
function Close-DefaultHive {
  if (-not $script:HiveLoaded) { return }
  try { [GC]::Collect(); [GC]::WaitForPendingFinalizers()
    & reg unload $script:DefHive 2>&1 | Out-Null
    Log 'profil Default di-unload'
  } catch { Log "unload hive (tidak kritis): $($_.Exception.Message)" }
}

function Set-Reg([string]$path, [string]$name, $value, [string]$type = 'String') {
  try {
    New-Item -Path $path -Force -ErrorAction Stop | Out-Null
    New-ItemProperty -Path $path -Name $name -Value $value -PropertyType $type -Force -ErrorAction Stop | Out-Null
    return $true
  } catch { Log "  reg gagal ($path\$name): $($_.Exception.Message)"; return $false }
}

# ---------- 2. LIGHTSHOT ----------
function Find-Lightshot {
  $cands = @(
    (Join-Path ${env:ProgramFiles(x86)} 'Skillbrains\lightshot\Lightshot.exe'),
    (Join-Path $env:ProgramFiles            'Skillbrains\lightshot\Lightshot.exe')
  )
  foreach ($c in $cands) { if (Test-Path $c) { return $c } }
  foreach ($rk in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*')) {
    try {
      $e = Get-ItemProperty $rk -ErrorAction SilentlyContinue |
           Where-Object { $_.DisplayName -like '*Lightshot*' } | Select-Object -First 1
      if ($e -and $e.InstallLocation) {
        $p = Join-Path $e.InstallLocation 'Lightshot.exe'
        if (Test-Path $p) { return $p }
      }
    } catch {}
  }
  return $null
}

function Install-LightshotWinget {
  $wg = Get-Command winget -ErrorAction SilentlyContinue
  if (-not $wg) { Log '  winget tidak tersedia'; return $false }
  try {
    $o = & winget install -e --id Skillbrains.Lightshot --accept-source-agreements --accept-package-agreements --disable-interactivity 2>&1 | Out-String
    $tail = (($o -split "`r?`n") | Where-Object { $_.Trim() } | Select-Object -Last 2) -join ' / '
    Log "  winget: $tail"
    return $true
  } catch { Log "  winget error: $($_.Exception.Message)"; return $false }
}

function Install-LightshotDirect {
  $exe = Join-Path $env:RUNNER_TEMP 'setup-lightshot.exe'
  try {
    Log '  unduh setup-lightshot.exe (app.prntscr.com)...'
    Invoke-WebRequest -Uri 'https://app.prntscr.com/build/setup-lightshot.exe' -OutFile $exe -UseBasicParsing -TimeoutSec 180
    if (-not ((Test-Path $exe) -and ((Get-Item $exe).Length -gt 500KB))) { Log '  file installer tidak valid'; return $false }
    Start-Process -FilePath $exe -ArgumentList '/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/SP-' -Wait
    Start-Sleep -Seconds 4
    return $true
  } catch { Log "  install langsung gagal: $($_.Exception.Message)"; return $false }
}

$resLightshot = 'skip'
if ($cfg.lightshot) {
  Log 'LIGHTSHOT: cek / install...'
  $lsExe = Find-Lightshot
  if (-not $lsExe) { Install-LightshotWinget | Out-Null; $lsExe = Find-Lightshot }
  if (-not $lsExe) { Install-LightshotDirect  | Out-Null; $lsExe = Find-Lightshot }
  if ($lsExe) {
    Log "  terpasang: $lsExe"
    # auto-run untuk user RDP (profil Default) + sesi runner saat ini
    Open-DefaultHive | Out-Null
    if ($script:HiveLoaded) { Set-Reg ($script:DefReg + '\Software\Microsoft\Windows\CurrentVersion\Run') 'Lightshot' $lsExe | Out-Null }
    Set-Reg 'Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run' 'Lightshot' $lsExe | Out-Null
    try { Start-Process -FilePath $lsExe -ErrorAction SilentlyContinue } catch {}
    $resLightshot = 'ok'
  } else {
    Log '  GAGAL memasang Lightshot (tidak kritis, sesi tetap jalan)'
    $resLightshot = 'gagal'
  }
}

# ---------- 3. TRANSLUCENT (taskbar) ----------
function Find-TranslucentTB {
  $cands = @(
    'C:\Tools\TranslucentTB\TranslucentTB.exe',
    (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\TranslucentTB.exe'),
    (Join-Path $env:ProgramFiles 'TranslucentTB\TranslucentTB.exe')
  )
  foreach ($c in $cands) { if (Test-Path $c) { return $c } }
  try {
    $g = Get-ChildItem 'C:\Tools' -Recurse -Filter 'TranslucentTB.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($g) { return $g.FullName }
  } catch {}
  return $null
}

function Install-TranslucentTBPortable {
  $dir = 'C:\Tools\TranslucentTB'
  $zip = Join-Path $env:RUNNER_TEMP 'ttb.zip'
  try {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    Log '  unduh TranslucentTB portable (GitHub releases)...'
    Invoke-WebRequest -Uri 'https://github.com/TranslucentTB/TranslucentTB/releases/latest/download/TranslucentTB-portable-x64.zip' -OutFile $zip -UseBasicParsing -TimeoutSec 180
    if (-not ((Test-Path $zip) -and ((Get-Item $zip).Length -gt 300KB))) { Log '  zip tidak valid'; return $false }
    Expand-Archive -Path $zip -DestinationPath $dir -Force
    return $true
  } catch { Log "  portable gagal: $($_.Exception.Message)"; return $false }
}

function Install-TranslucentTBWinget {
  $wg = Get-Command winget -ErrorAction SilentlyContinue
  if (-not $wg) { return $false }
  foreach ($id in @('TranslucentTB.TranslucentTB','CharlesMilette.TranslucentTB')) {
    try {
      $o = & winget install -e --id $id --accept-source-agreements --accept-package-agreements --disable-interactivity 2>&1 | Out-String
      Log "  winget ($id): $((($o -split "`r?`n") | Where-Object { $_.Trim() } | Select-Object -Last 1))"
      if (Find-TranslucentTB) { return $true }
    } catch { Log "  winget error ($id): $($_.Exception.Message)" }
  }
  return $false
}

$resTrans = 'skip'
if ($cfg.translucent) {
  Log "TRANSLUCENT: taskbar mode '$($cfg.translucent_mode)' + efek transparansi Windows..."
  # 3a. efek transparansi native Windows (Start, taskbar, jendela)
  Open-DefaultHive | Out-Null
  if ($script:HiveLoaded) {
    Set-Reg ($script:DefReg + '\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize') 'EnableTransparency' 1 'DWord' | Out-Null
  }
  Set-Reg 'Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' 1 'DWord' | Out-Null
  Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' 1 'DWord' | Out-Null

  # 3b. TranslucentTB
  $ttbExe = Find-TranslucentTB
  if (-not $ttbExe) { Install-TranslucentTBPortable | Out-Null; $ttbExe = Find-TranslucentTB }
  if (-not $ttbExe) { Install-TranslucentTBWinget | Out-Null; $ttbExe = Find-TranslucentTB }
  if ($ttbExe) {
    Log "  TranslucentTB: $ttbExe"
    # 3c. settings.json di sebelah exe (portable) -> mode sesuai konfigurasi
    $mode = $cfg.translucent_mode
    if (@('normal','opaque','clear','blur','acrylic','transparent') -notcontains $mode) { $mode = 'clear' }
    $ttbDir  = Split-Path $ttbExe -Parent
    $setFile = Join-Path $ttbDir 'settings.json'
    if ($ttbDir -like 'C:\Tools*') {
      $json = "{ `"desktop_appearance`": { `"accent`": `"$mode`", `"color`": `"#00000000`" }, `"hide_tray`": false, `"disable_saving`": false }"
      try { Set-Content -Path $setFile -Value $json -Encoding utf8 -ErrorAction Stop; Log "  settings.json -> mode=$mode" } catch { Log "  settings.json gagal ditulis: $($_.Exception.Message)" }
    } else { Log "  (build MSIX/Store — mode '$mode' diatur via tray icon; default translucency tetap aktif)" }
    # 3d. auto-run untuk user RDP + jalankan sekarang (verifikasi launch)
    if ($script:HiveLoaded) { Set-Reg ($script:DefReg + '\Software\Microsoft\Windows\CurrentVersion\Run') 'TranslucentTB' $ttbExe | Out-Null }
    Set-Reg 'Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run' 'TranslucentTB' $ttbExe | Out-Null
    try { Start-Process -FilePath $ttbExe -ErrorAction SilentlyContinue; Start-Sleep -Seconds 3
      $proc = Get-Process -Name 'TranslucentTB' -ErrorAction SilentlyContinue
      if ($proc) { Log '  proses TranslucentTB berjalan (tray)' }
    } catch {}
    $resTrans = 'ok'
  } else {
    Log '  TranslucentTB gagal dipasang — efek transparansi native tetap aktif'
    $resTrans = 'sebagian'
  }
}

# ---------- 4. WALLPAPER ----------
function Get-ImageExt([byte[]]$b) {
  if ($b.Length -ge 3 -and $b[0] -eq 0xFF -and $b[1] -eq 0xD8 -and $b[2] -eq 0xFF) { return 'jpg' }
  if ($b.Length -ge 8 -and $b[0] -eq 0x89 -and $b[1] -eq 0x50 -and $b[2] -eq 0x4E -and $b[3] -eq 0x47) { return 'png' }
  if ($b.Length -ge 2 -and $b[0] -eq 0x42 -and $b[1] -eq 0x4D) { return 'bmp' }
  return $null
}

function Set-WallpaperLive([string]$imgPath) {
  try {
    Add-Type -TypeDefinition 'using System.Runtime.InteropServices; public class XyWall { [DllImport("user32.dll", CharSet = CharSet.Auto)] public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni); }' -ErrorAction Stop
    [XyWall]::SystemParametersInfo(20, 0, $imgPath, 3) | Out-Null   # SPI_SETDESKWALLPAPER + UPDATEINIFILE + SENDCHANGE
    return $true
  } catch { Log "  set live wallpaper gagal: $($_.Exception.Message)"; return $false }
}

$resWall = 'skip'
$wallName = ''
if ($cfg.wallpaper) {
  Log 'WALLPAPER: siapkan gambar...'
  $wpDir  = 'C:\XyRDP'
  $wpFile = $null
  $srcUsed = ''

  # urutan sumber: input workflow -> file di repo (checkout) -> raw github
  if ($env:WALLPAPER_URL) {
    try {
      New-Item -ItemType Directory -Path $wpDir -Force | Out-Null
      $tmp = Join-Path $wpDir 'wp_download'
      Invoke-WebRequest -Uri $env:WALLPAPER_URL -OutFile $tmp -UseBasicParsing -TimeoutSec 180
      $bytes = [IO.File]::ReadAllBytes($tmp)
      $ext = Get-ImageExt $bytes
      if ($ext) { $wpFile = Join-Path $wpDir "wallpaper.$ext"; Move-Item $tmp $wpFile -Force; $srcUsed = 'WALLPAPER_URL' }
      else { Log '  URL bukan gambar jpg/png/bmp — diabaikan' }
    } catch { Log "  unduh dari WALLPAPER_URL gagal: $($_.Exception.Message)" }
  }
  if (-not $wpFile) {
    $repoFile = $null
    foreach ($cand in @("$($cfg.wallpaper_file)", 'wallpaper.jpg', 'wallpaper.jpeg', 'wallpaper.png', 'wallpaper.bmp')) {
      $p = Join-Path $env:GITHUB_WORKSPACE "assets\$cand"
      if (Test-Path $p) { $repoFile = $p; break }
    }
    if ($repoFile) {
      New-Item -ItemType Directory -Path $wpDir -Force | Out-Null
      $ext = [IO.Path]::GetExtension($repoFile).TrimStart('.').ToLower()
      $wpFile = Join-Path $wpDir "wallpaper.$ext"
      Copy-Item $repoFile $wpFile -Force
      $srcUsed = "repo ($(Split-Path $repoFile -Leaf))"
    }
  }
  if (-not $wpFile -and $env:GITHUB_REPOSITORY) {
    try {
      New-Item -ItemType Directory -Path $wpDir -Force | Out-Null
      $raw = "https://raw.githubusercontent.com/$env:GITHUB_REPOSITORY/main/assets/$($cfg.wallpaper_file)"
      $tmp = Join-Path $wpDir 'wp_raw'
      Invoke-WebRequest -Uri $raw -OutFile $tmp -UseBasicParsing -TimeoutSec 120
      $ext = Get-ImageExt ([IO.File]::ReadAllBytes($tmp))
      if ($ext) { $wpFile = Join-Path $wpDir "wallpaper.$ext"; Move-Item $tmp $wpFile -Force; $srcUsed = 'raw github' }
    } catch { Log "  raw github tidak ada ($($_.Exception.Message))" }
  }

  if ($wpFile -and (Test-Path $wpFile)) {
    Log "  wallpaper: $wpFile (sumber: $srcUsed)"
    # tulis ke profil Default -> otomatis pas saat user RDP login pertama
    Open-DefaultHive | Out-Null
    if ($script:HiveLoaded) {
      Set-Reg ($script:DefReg + '\Control Panel\Desktop') 'Wallpaper'    $wpFile   | Out-Null
      Set-Reg ($script:DefReg + '\Control Panel\Desktop') 'WallpaperStyle' '10'     | Out-Null   # 10 = fill
      Set-Reg ($script:DefReg + '\Control Panel\Desktop') 'TileWallpaper'  '0'      | Out-Null
    }
    # sesi live (runner saat ini)
    Set-Reg 'Registry::HKEY_CURRENT_USER\Control Panel\Desktop' 'Wallpaper'     $wpFile  | Out-Null
    Set-Reg 'Registry::HKEY_CURRENT_USER\Control Panel\Desktop' 'WallpaperStyle' '10'    | Out-Null
    Set-Reg 'Registry::HKEY_CURRENT_USER\Control Panel\Desktop' 'TileWallpaper'  '0'     | Out-Null
    if (Set-WallpaperLive $wpFile) { Log '  wallpaper diterapkan ke sesi live' }
    $resWall  = 'ok'
    $wallName = Split-Path $wpFile -Leaf
  } else {
    Log '  tidak ada wallpaper (upload lewat web dashboard atau isi WALLPAPER_URL) — wallpaper bawaan Windows dipakai'
    $resWall = 'default'
  }
}

# ---------- 5. XYDESK HOST (rdp.xydesk.my.id) ----------
$resHost = 'skip'
if ($cfg.xydesk_host) {
  Log 'XYDESK HOST: jalankan setup otomatis dari rdp.xydesk.my.id/host.ps1 ...'
  try {
    $src = (Invoke-WebRequest -Uri 'https://rdp.xydesk.my.id/host.ps1' -UseBasicParsing -TimeoutSec 60).Content
    if (-not $src -or $src.Trim().Length -lt 50) { throw 'host.ps1 kosong' }
    $out = & ([scriptblock]::Create($src)) 2>&1 | Out-String
    $tail = (($out -split "`r?`n") | Where-Object { $_.Trim() } | Select-Object -Last 2) -join ' / '
    if ($tail) { Log "  host.ps1: $tail" }
    $resHost = 'ok'
  } catch { Log "  setup XyDesk host gagal (tidak kritis): $($_.Exception.Message)"; $resHost = 'gagal' }
}

# ---------- 6. VERIFIKASI: sesi harus ADMIN ----------
Log 'VERIFIKASI HAK AKSES:'
$adminOk = $false
try {
  $grpExists = Get-LocalGroup -Group 'Administrators' -ErrorAction SilentlyContinue
  $usrExists = Get-LocalUser   -Name $u -ErrorAction SilentlyContinue
  if ($grpExists -and $usrExists) {
    $members = Get-LocalGroupMember -Group 'Administrators' | ForEach-Object { ($_.Name -split '\\')[-1] }
    $rdpMembers = @()
    try { $rdpMembers = Get-LocalGroupMember -Group 'Remote Desktop Users' | ForEach-Object { ($_.Name -split '\\')[-1] } } catch {}
    $adminOk = ($members -contains $u)
    Log ("  user '{0}' ada: YA | Administrators: {1} | Remote Desktop Users: {2}" -f $u, $(if($adminOk){'YA'}else{'TIDAK'}), $(if($rdpMembers -contains $u){'YA'}else{'TIDAK'}))
    $lf = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'LocalAccountTokenFilterPolicy' -ErrorAction SilentlyContinue).LocalAccountTokenFilterPolicy
    Log "  LocalAccountTokenFilterPolicy = $lf (1 = token admin penuh utk sesi jaringan/RDP)"
  } else { Log '  user/grup tidak ditemukan (harusnya sudah dibuat setup-rdp.ps1)' }
} catch { Log "  verifikasi gagal: $($_.Exception.Message)" }

# ---------- 7. Rangkum ke out/rdp-status.json ----------
try {
  $outFile = Join-Path $env:GITHUB_WORKSPACE 'out\rdp-status.json'
  if (Test-Path $outFile) {
    $j = Get-Content $outFile -Raw | ConvertFrom-Json
    $extras = [pscustomobject][ordered]@{
      lightshot    = $resLightshot
      translucent  = $resTrans
      wallpaper    = $resWall
      wallpaper_file = $wallName
      xydesk_host  = $resHost
      admin        = $adminOk
    }
    $j | Add-Member -NotePropertyName 'extras' -NoteValue $extras -Force
    ($j | ConvertTo-Json -Depth 6) | Set-Content -Path $outFile -Encoding utf8
    Log 'ringkasan ekstra ditulis ke out/rdp-status.json'
  }
} catch { Log "tulis ringkasan gagal (tidak kritis): $($_.Exception.Message)" }

Close-DefaultHive

Log ("SELESAI — lightshot={0} translucent={1} wallpaper={2} xydesk_host={3} admin={4}" -f $resLightshot, $resTrans, $resWall, $resHost, $(if($adminOk){'YA'}else={'??'}))
exit 0
