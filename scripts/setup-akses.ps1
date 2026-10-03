# ============================================================================
#  setup-akses.ps1 — akses masuk TANPA Tailscale (v2)
# ----------------------------------------------------------------------------
#  Dua jalur, bisa jalan bareng ("keduanya"):
#
#   1) RUSTDESK  — remote desktop app (klien di PC kamu, gratis, tanpa VPN)
#        - installer dari winget (fallback: GitHub releases rustdesk/rustdesk)
#        - dipasang sebagai service (mode unattended, bisa sampai layar login)
#        - password permanen = RDP_PASSWORD (satu password untuk semua)
#        - server rendezvous/relay memakai server PUBLIK bawaan RustDesk
#          (rs-ny.rustdesk.com / rs-sg.rustdesk.com) -> TIDAK self-host apa pun
#
#   2) TUNNEL TCP ke port 3389 — buat Remote Desktop Connection (mstsc) biasa
#        - bore   : bore.pub, tanpa akun, tanpa daftar  (default)
#        - ngrok  : butuh NGROK_AUTHTOKEN (akun gratis)  (lebih stabil)
#      URL: bore.pub:<port> atau <x>.tcp.ngrok.io:<port>
#
#  Hasil (RustDesk ID + host:port tunnel) ditulis ke out/rdp-status.json dan
#  muncul di dashboard web. Tanpa password apa pun di file itu.
# ============================================================================

$XyTag = 'XyRDP:akses'
. "$PSScriptRoot/lib-common.ps1"

$u        = if ($env:RDP_USER) { $env:RDP_USER } else { 'xyadmin' }
$pw       = $env:RDP_PASSWORD
$localPort = 3389
$work     = 'C:\XyRDP\akses'
New-Item -ItemType Directory -Path $work -Force | Out-Null

$mode = if ($env:AKSES) { $env:AKSES.Trim().ToLower() } else { 'keduanya' }
if (@('rustdesk', 'rd', 'keduanya', 'both', 'dua', 'tunnel', 'rdp') -notcontains $mode) { $mode = 'keduanya' }
if (@('both', 'dua') -contains $mode) { $mode = 'keduanya' }
$useRd     = ($mode -eq 'keduanya' -or $mode -eq 'rustdesk' -or $mode -eq 'rd')
$useTunnel = ($mode -eq 'keduanya' -or $mode -eq 'tunnel' -or $mode -eq 'rdp')

$prov = if ($env:TUNNEL_PROVIDER) { $env:TUNNEL_PROVIDER.Trim().ToLower() } else { 'otomatis' }
if (@('otomatis', 'auto', 'bore', 'ngrok') -notcontains $prov) { $prov = 'otomatis' }
$ngrokTok = if ($env:NGROK_AUTHTOKEN) { $env:NGROK_AUTHTOKEN } else { $env:NGROK_TOKEN }

Log "mode akses = $mode | provider tunnel = $prov | RustDesk=$useRd | Tunnel=$useTunnel"

# ============================================================================
#  helper: jalankan perintah eksternal dengan TIMEOUT KERAS
#  (pelajaran dari validasi 2026-10-03: `Start-Process --silent-install -Wait`
#   menggantung selamanya karena installer RustDesk menyalakan proses anak;
#   -Wait menunggu seluruh process tree -> job bisa nyangkut berjam-jam)
# ============================================================================
function Invoke-Cmd([string]$FilePath, [string[]]$Arguments, [int]$TimeoutSec = 60) {
  $tag = [guid]::NewGuid().ToString('N').Substring(0, 8)
  $outF = Join-Path $work "cmd-$tag.out"
  $errF = Join-Path $work "cmd-$tag.err"
  $res = @{ ok = $false; timeout = $false; code = $null; out = ''; err = '' }
  try {
    $p = Start-Process -FilePath $FilePath -ArgumentList $Arguments -PassThru -NoNewWindow `
         -RedirectStandardOutput $outF -RedirectStandardError $errF -ErrorAction Stop
    try {
      $p | Wait-Process -Timeout $TimeoutSec -ErrorAction Stop
      $res.ok = $true
      $res.code = $p.ExitCode
    } catch {
      $res.timeout = $true
      try { $p | Stop-Process -Force -ErrorAction SilentlyContinue } catch {}
    }
  } catch { $res.err = $_.Exception.Message }
  if (Test-Path $outF) { $res.out = (Get-Content $outF -Raw -ErrorAction SilentlyContinue) }
  if (Test-Path $errF) { $res.err = "$($res.err)`n$(Get-Content $errF -Raw -ErrorAction SilentlyContinue)" }
  return $res
}

# matikan aplikasi tray RustDesk (kalau ada) supaya CLI & service bersih
function Stop-RustDeskTray {
  try {
    $apps = Get-Process -Name 'rustdesk' -ErrorAction SilentlyContinue |
            Where-Object { $_.Path -and $_.Path -like '*RustDesk*' -and $_.SessionId -ne 0 }
    if ($apps) { $apps | Stop-Process -Force -ErrorAction SilentlyContinue; Start-Sleep -Seconds 2 }
  } catch {}
}

# ============================================================================
#  BAGIAN 1 — RUSTDESK
# ============================================================================
function Find-RustDesk {
  $cands = @(
    (Join-Path $env:ProgramFiles 'RustDesk\rustdesk.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'RustDesk\rustdesk.exe'),
    (Join-Path $env:LOCALAPPDATA 'Programs\RustDesk\rustdesk.exe')
  )
  foreach ($c in $cands) { if ($c -and (Test-Path $c)) { return $c } }
  foreach ($roots in @('C:\Program Files', 'C:\Program Files (x86)')) {
    try {
      $g = Get-ChildItem $roots -Recurse -Depth 3 -Filter 'rustdesk.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
      if ($g) { return $g.FullName }
    } catch {}
  }
  $cmd = Get-Command rustdesk.exe -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  return $null
}

# tunggu sabar sampai binary RustDesk muncul (installer bisa asinkron)
function Wait-RustDeskFiles([int]$maxSec = 300) {
  $t0 = Get-Date
  while (((Get-Date) - $t0).TotalSeconds -lt $maxSec) {
    if (Find-RustDesk) { return $true }
    Start-Sleep -Seconds 10
  }
  return [bool](Find-RustDesk)
}

function Install-RustDesk {
  # Urutan: MSI (paling andal: msiexec menunggu sampai selesai) -> winget -> exe
  $msi = Get-GhAssetUrl 'rustdesk/rustdesk' '^rustdesk-[0-9.]+-x86_64\.msi$'
  if ($msi) {
    $msiFile = Join-Path $work $msi.name
    if (Get-File $msi.url $msiFile 300) {
      Log "  install MSI: $($msi.name) ($($msi.tag))..."
      $r = Invoke-Cmd 'msiexec.exe' @('/i', $msiFile, '/qn', '/norestart', '/l*v', (Join-Path $work 'msi.log')) 600
      if ($r.timeout) { Log '  msiexec TIMEOUT 600s — lanjut verifikasi berkas' }
      else { Log "  msiexec selesai (exit=$($r.code))" }
      if (Wait-RustDeskFiles 120) { return $true }
    } else { Log '  unduh MSI gagal' }
  }
  $wg = Get-Command winget -ErrorAction SilentlyContinue
  if ($wg) {
    Log '  mencoba winget (RustDesk.RustDesk)...'
    $r = Invoke-Cmd 'winget' @('install','-e','--id','RustDesk.RustDesk','--source','winget',
                                '--accept-source-agreements','--accept-package-agreements','--disable-interactivity') 300
    if ($r.timeout) { Log '  winget TIMEOUT 300s — lanjut ke installer exe' }
    else { Log ("  winget: " + (Log-Tail "$($r.out)$($r.err)" 1)) }
    Stop-RustDeskTray
    if (Wait-RustDeskFiles 60) { return $true }
  }
  # fallback terakhir: installer exe (asinkron; tunggu sampai 5 menit)
  $asset = Get-GhAssetUrl 'rustdesk/rustdesk' '^rustdesk-[0-9.]+-x86_64\.exe$'
  if (-not $asset) { Log '  tidak menemukan installer RustDesk di GitHub releases'; return $false }
  $exe = Join-Path $work $asset.name
  if (-not (Get-File $asset.url $exe 300)) { Log '  unduh installer RustDesk gagal'; return $false }
  Log "  install exe: $($asset.name) ($($asset.tag))..."
  $r = Invoke-Cmd $exe @('--silent-install') 420
  if ($r.timeout) { Log '  installer exe TIMEOUT 420s — verifikasi berkas' }
  else { Log "  installer exe selesai (exit=$($r.code))" }
  Stop-RustDeskTray
  return (Wait-RustDeskFiles 300)
}

$rdStatus = 'skip'; $rdId = ''; $rdServer = 'rs-ny.rustdesk.com / rs-sg.rustdesk.com (server publik RustDesk)'
if ($useRd) {
  Log 'RUSTDESK: menyiapkan...'
  $rdExe = Find-RustDesk
  if (-not $rdExe) { Install-RustDesk | Out-Null; $rdExe = Find-RustDesk }
  if (-not $rdExe) {
    Log '  GAGAL: RustDesk tidak terpasang (sesi tetap jalan lewat tunnel bila ada)'
    $rdStatus = 'gagal'
  } else {
    Log "  terpasang: $rdExe"
    # service (mode unattended: bisa konek walau belum ada user login)
    $svcOk = $false
    try {
      if (-not (Get-Service -Name 'RustDesk' -ErrorAction SilentlyContinue)) {
        $r = Invoke-Cmd $rdExe @('--install-service') 90
        if ($r.timeout) { Log '  --install-service TIMEOUT 90s' }
      }
      for ($i = 0; $i -lt 20; $i++) {
        $svc = Get-Service -Name 'RustDesk' -ErrorAction SilentlyContinue
        if ($svc) { break }
        Start-Sleep -Seconds 3
      }
      $svc = Get-Service -Name 'RustDesk' -ErrorAction SilentlyContinue
      if ($svc) {
        Set-Service -Name 'RustDesk' -StartupType Automatic -ErrorAction SilentlyContinue
        Start-Service -Name 'RustDesk' -ErrorAction SilentlyContinue
        $svcOk = $true
        Log '  service RustDesk: aktif (mode unattended)'
      } else { Log '  service RustDesk belum terdaftar (lanjut; password/ID tetap dicoba)' }
    } catch { Log "  service RustDesk (tidak kritis): $($_.Exception.Message)" }

    # password permanen = password RDP (biar user hanya perlu 1 password)
    $pwOk = $false
    for ($i = 1; $i -le 3 -and -not $pwOk; $i++) {
      $r = Invoke-Cmd $rdExe @('--password', $pw) 30
      if (-not $r.timeout) { $pwOk = $true } else { Log "  --password TIMEOUT (coba $i/3)"; Start-Sleep -Seconds 3 }
    }
    Log "  password permanen di-set: $(if ($pwOk) { 'ok' } else { 'PERLU CEK MANUAL' })"

    # opsional (lanjutan): server sendiri/terdekat lewat env RD_SERVER
    if ($env:RD_SERVER) {
      try {
        $toml = "# XyRDP`nrendezvous_server = '$($env:RD_SERVER)'`n`n[options]`nrelay-server = '$($env:RD_SERVER)'`n"
        foreach ($p in @(
          'C:\Windows\System32\config\systemprofile\AppData\Roaming\RustDesk\config',
          'C:\Windows\ServiceProfiles\LocalService\AppData\Roaming\RustDesk\config',
          (Join-Path $env:APPDATA 'RustDesk\config')
        )) {
          New-Item -ItemType Directory -Path $p -Force | Out-Null
          Set-Content -Path (Join-Path $p 'RustDesk2.toml') -Value $toml -Encoding utf8
        }
        $rdServer = "$($env:RD_SERVER) (RD_SERVER dari input workflow)"
        Log "  server RustDesk diset: $($env:RD_SERVER) — klien kamu harus pakai server yang sama!"
        Restart-Service -Name 'RustDesk' -Force -ErrorAction SilentlyContinue
      } catch { Log "  set server RustDesk gagal (tidak kritis): $($_.Exception.Message)" }
    }

    # ambil ID (perlu beberapa detik setelah service register ke server)
    for ($i = 1; $i -le 12 -and -not $rdId; $i++) {
      $r = Invoke-Cmd $rdExe @('--get-id') 25
      if ($r.out) {
        foreach ($line in ($r.out -split "`r?`n")) {
          $clean = ($line -replace '\s', '').Trim()
          if ($clean -match '^[0-9]{6,12}$') { $rdId = $clean; break }
        }
      }
      if (-not $rdId) { Start-Sleep -Seconds 5 }
    }
    if ($rdId) {
      Log "  RUSTDESK ID : $rdId"
      Log "  (klien RustDesk kamu -> masukkan ID di atas + password, tanpa VPN)"
      $rdStatus = 'ok'
      # auto-start untuk user RDP
      Open-DefaultHive | Out-Null
      if ($script:HiveLoaded) {
        Set-Reg ($script:DefReg + '\Software\Microsoft\Windows\CurrentVersion\Run') 'RustDesk' $rdExe 'String' | Out-Null
        Close-DefaultHive
      }
      try { Start-Process -FilePath $rdExe -ErrorAction SilentlyContinue } catch {}
    } else {
      Log '  ID RustDesk belum keluar setelah 100 detik (server publik lambat / diblokir).'
      Log '  Cek manual di VM: rustdesk.exe --get-id'
      $rdStatus = 'gagal-id'
    }
  }
}

# ============================================================================
#  BAGIAN 2 — TUNNEL TCP (RDP 3389)
# ============================================================================
function Wait-Tunnel([string]$logFile, [string]$regex, [int]$timeoutSec = 90) {
  for ($i = 0; $i -lt $timeoutSec; $i++) {
    if (Test-Path $logFile) {
      $txt = Get-Content $logFile -Raw -ErrorAction SilentlyContinue
      if ($txt) {
        $m = [regex]::Match($txt, $regex, 'IgnoreCase')
        if ($m.Success) { return $m }
      }
    }
    Start-Sleep -Seconds 1
  }
  return $null
}

function Start-Bore {
  Log '  bore: siapkan binary...'
  $dir = Join-Path $work 'bore'
  $boreExe = Join-Path $dir 'bore.exe'
  if (-not (Test-Path $boreExe)) {
    $asset = Get-GhAssetUrl 'ekzhang/bore' 'x86_64-pc-windows-msvc\.zip$'
    if (-not $asset) { $asset = @{ url = 'https://github.com/ekzhang/bore/releases/download/v0.6.0/bore-v0.6.0-x86_64-pc-windows-msvc.zip'; tag = 'v0.6.0'; name = 'bore-v0.6.0-x86_64-pc-windows-msvc.zip' } }
    $zip = Join-Path $work 'bore.zip'
    if (-not (Get-File $asset.url $zip 180)) { Log '  unduh bore gagal'; return $null }
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    Expand-Archive -Path $zip -DestinationPath $dir -Force
    # zip bisa punya subfolder
    if (-not (Test-Path $boreExe)) {
      $g = Get-ChildItem $dir -Recurse -Filter 'bore.exe' | Select-Object -First 1
      if ($g) { $boreExe = $g.FullName }
    }
  }
  if (-not (Test-Path $boreExe)) { Log '  bore.exe tidak ada'; return $null }
  $logF = Join-Path $work 'bore.log'
  Remove-Item $logF -ErrorAction SilentlyContinue
  Log "  mulai: bore local $localPort --to bore.pub (local-host 127.0.0.1)"
  # --local-host 127.0.0.1: jangan biarkan 'localhost' jatuh ke ::1 (RDP Windows
  # tidak selalu listen di IPv6 -> koneksi lewat tunnel akan di-reset)
  $p = Start-Process -FilePath $boreExe -ArgumentList @('local', "$localPort", '--local-host', '127.0.0.1', '--to', 'bore.pub') `
        -RedirectStandardOutput $logF -RedirectStandardError (Join-Path $work 'bore.err') -PassThru -WindowStyle Hidden
  $m = Wait-Tunnel $logF 'listening at\s+([^\s:]+):(\d+)' 90
  if (-not $m) { try { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch {}; Log '  bore: tidak dapat endpoint (timeout)'; return $null }
  Log "  TUNNEL : $($m.Groups[1].Value):$($m.Groups[2].Value) (bore, tanpa akun)"
  return @{ provider = 'bore'; host = $m.Groups[1].Value; port = [int]$m.Groups[2].Value; pid = $p.Id; log = $logF }
}

function Start-Ngrok {
  if (-not $ngrokTok) { Log '  ngrok: NGROK_AUTHTOKEN tidak di-set — dilewati'; return $null }
  $dir = Join-Path $work 'ngrok'
  New-Item -ItemType Directory -Path $dir -Force | Out-Null
  $ngrokExe = Join-Path $dir 'ngrok.exe'
  if (-not (Test-Path $ngrokExe)) {
    $zip = Join-Path $work 'ngrok.zip'
    if (-not (Get-File 'https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-windows-amd64.zip' $zip 180)) { Log '  unduh ngrok gagal'; return $null }
    Expand-Archive -Path $zip -DestinationPath $dir -Force
  }
  if (-not (Test-Path $ngrokExe)) { Log '  ngrok.exe tidak ada'; return $null }
  try { & $ngrokExe config add-authtoken $ngrokTok 2>&1 | Out-Null } catch { Log "  ngrok authtoken: $($_.Exception.Message)" }
  $logF = Join-Path $work 'ngrok.log'
  Remove-Item $logF -ErrorAction SilentlyContinue
  Log "  mulai: ngrok tcp 127.0.0.1:$localPort"
  $p = Start-Process -FilePath $ngrokExe -ArgumentList @('tcp', "127.0.0.1:$localPort", '--log=stdout', '--log-format=json') `
        -RedirectStandardOutput $logF -RedirectStandardError (Join-Path $work 'ngrok.err') -PassThru -WindowStyle Hidden
  $m = Wait-Tunnel $logF 'tcp://([^":\s]+):(\d+)' 90
  if (-not $m) { try { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch {}; Log '  ngrok: tidak dapat endpoint (timeout / token salah)'; return $null }
  Log "  TUNNEL : $($m.Groups[1].Value):$($m.Groups[2].Value) (ngrok)"
  return @{ provider = 'ngrok'; host = $m.Groups[1].Value; port = [int]$m.Groups[2].Value; pid = $p.Id; log = $logF }
}

$tunStatus = 'skip'; $tun = $null; $localOk = $false; $stOk = 'skip'
if ($useTunnel) {
  Log "TUNNEL TCP (RDP $localPort): menyiapkan..."
  if ($prov -eq 'ngrok') { $tun = Start-Ngrok }
  elseif ($prov -eq 'bore') { $tun = Start-Bore }
  else {
    # otomatis: ngrok kalau ada token (lebih stabil), lalu bore (tanpa akun)
    if ($ngrokTok) { $tun = Start-Ngrok }
    if (-not $tun) { $tun = Start-Bore }
    if (-not $tun -and -not $ngrokTok) { Log '  (tips: set secret NGROK_AUTHTOKEN untuk jalur kedua yang lebih stabil)' }
  }
  if ($tun) {
    $tunStatus = 'ok'
    Log '  RDP lewat tunnel: buka Remote Desktop Connection ke alamat di atas'

    # --- diagnostik: RDP di VM benar-benar mendengarkan? ---
    try {
      $ns = (netstat -ano | Select-String ':3389' | Select-Object -First 4) -join ' | '
      Log "  netstat :3389 -> $ns"
    } catch {}
    $localOk = $false
    try {
      $tc = New-Object System.Net.Sockets.TcpClient
      $localOk = $tc.ConnectAsync('127.0.0.1', $localPort).Wait(5000)
      $tc.Close()
    } catch {}
    Log "  RDP lokal 127.0.0.1:$localPort -> $(if ($localOk) { 'TERBUKA' } else { 'TERTUTUP (RDP mungkin belum jalan!)' })"

    # --- self-test end-to-end: tembak handshake X.224 lewat endpoint publik ---
    $stOk = 'gagal'
    try {
      $cr = [byte[]](0x03,0x00,0x00,0x13, 0x0e,0xe0,0x00,0x00,0x00,0x00,0x00,
                     0x01,0x00,0x08,0x00,0x03,0x00,0x00,0x00)
      $c2 = New-Object System.Net.Sockets.TcpClient
      if ($c2.ConnectAsync($tun.host, $tun.port).Wait(15000)) {
        $ns2 = $c2.GetStream()
        $ns2.Write($cr, 0, $cr.Length); $ns2.Flush()
        $buf = New-Object byte[] 64
        $c2.ReceiveTimeout = 15000
        $n = $ns2.Read($buf, 0, $buf.Length)
        $hex = (($buf[0..([Math]::Min($n,8)-1)] | ForEach-Object { $_.ToString('x2') }) -join ' ')
        Log "  self-test tunnel: balasan $n byte [$hex]"
        if ($n -ge 6 -and $buf[0] -eq 0x03 -and $buf[1] -eq 0x00 -and $buf[5] -in @(0xd0, 0xcf)) {
          $stOk = 'ok'
          Log "  SELF-TEST OK — $($tun.host):$($tun.port) benar-benar sampai ke port 3389 VM (X.224 Connection Confirm)"
        } else { Log '  self-test: balasan bukan X.224 Connection Confirm (cek lagi)' }
        $c2.Close()
      } else { Log "  self-test: tidak bisa connect ke $($tun.host):$($tun.port)" }
    } catch { Log "  self-test error: $($_.Exception.Message)" }
  } else {
    $tunStatus = 'gagal'
    Log '  GAGAL membuat tunnel. Sesi tetap jalan — pakai jalur RustDesk.'
  }
}

# ============================================================================
#  RANGKUMAN -> out/rdp-status.json
# ============================================================================
$aksesObj = [ordered]@{
  mode     = $mode
  rustdesk = [ordered]@{
    status  = $rdStatus
    service = $svcOk
    id      = $rdId
    server = $rdServer
    client = 'Unduh app RustDesk (gratis) -> masukkan ID + password'
  }
  tunnel   = [ordered]@{
    status     = $tunStatus
    provider   = if ($tun) { $tun.provider } else { '' }
    host       = if ($tun) { $tun.host } else { '' }
    port       = if ($tun) { $tun.port } else { 0 }
    address    = if ($tun) { "$($tun.host):$($tun.port)" } else { '' }
    rdp_local  = if ($tun) { if ($localOk) { 'terbuka' } else { 'tertutup' } } else { '' }
    selftest   = if ($tun) { $stOk } else { '' }
    note       = 'Isi Host+Port ini di XyDesk Remote (Koneksi RDP) atau mstsc; user ' + $u
  }
}
Update-Status @{ akses = $aksesObj } | Out-Null
$aksesObj | ConvertTo-Json -Depth 8 | Out-File -Append -Encoding utf8 $env:GITHUB_STEP_SUMMARY

Log "SELESAI — rustdesk=$rdStatus$(if ($rdId) { " ($rdId)" }) tunnel=$tunStatus$(if ($tun) { " ($($tun.host):$($tun.port))" })"
exit 0
