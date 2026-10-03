# ============================================================================
#  keepalive.ps1 — tahan job (dan VM-nya) tetap hidup selama DUR menit,
#  minus buffer supaya cleanup selesai sebelum batas keras 360 menit.
#
#  Tiap 5 menit menulis heartbeat ke log: status akses (RustDesk ID +
#  tunnel), jumlah sesi RDP aktif, sisa waktu. Tiap 30 menit status ikut
#  di-publish ulang ke branch `status` supaya dashboard tetap segar.
# ============================================================================

$XyTag = 'XyRDP:alive'
. "$PSScriptRoot/lib-common.ps1"

$dur = [int]($env:DUR -replace '\D', ''); if ($dur -lt 10) { $dur = 360 }; if ($dur -gt 355) { $dur = 355 }
$buffer = if ($dur -ge 15) { 6 } else { 2 }
$stop = (Get-Date).AddMinutes($dur - $buffer)
Log "menahan sesi sampai $($stop.ToString('HH:mm:ss')) UTC ($dur menit total, buffer cleanup $buffer menit)"

$nextPublish = (Get-Date).AddMinutes(30)
while ((Get-Date) -lt $stop) {
  $left = ($stop - (Get-Date)).ToString('hh\:mm')

  # info akses dari status file (sudah diisi setup-akses.ps1)
  $rdId = '?'; $tun = '?'
  $st = Read-Status
  if ($st -and $st.akses) {
    if ($st.akses.rustdesk -and $st.akses.rustdesk.id) { $rdId = $st.akses.rustdesk.id }
    if ($st.akses.tunnel -and $st.akses.tunnel.address) { $tun = $st.akses.tunnel.address }
  }

  # sesi RDP aktif
  $sess = 0
  try {
    $q = (quser 2>$null)
    if ($q) { $sess = @($q | Select-Object -Skip 1 | Where-Object { $_ -match '\S' }).Count }
  } catch {}

  # klien RustDesk yang sedang terhubung (proses tambahan selain service)
  $rdProc = 0
  try { $rdProc = @(Get-Process -Name 'rustdesk' -ErrorAction SilentlyContinue).Count } catch {}

  # kesehatan tunnel: handshake X.224 langsung ke endpoint publik (10 detik)
  $tunHealth = ''
  if ($tun -and $tun -match '^(?<h>[^:]+):(?<p>\d+)$') {
    $hr = Test-RdpHandshake $Matches['h'] ([int]$Matches['p']) 10000
    $tunHealth = if ($hr.ok) { 'ok' } else { 'gagal' }
    # PENTING: Update-Status mengganti key level atas — jadi ambil objek akses
    # utuh dulu, ubah selftest-nya, baru tulis balik (jangan kirim potongan).
    $stNow = Read-Status
    if ($stNow -and $stNow.akses -and $stNow.akses.tunnel) {
      if ("$($stNow.akses.tunnel.selftest)" -ne $tunHealth) {
        $stNow.akses.tunnel | Add-Member -NotePropertyName 'selftest' -NotePropertyValue $tunHealth -Force
        try { Update-Status @{ akses = $stNow.akses } | Out-Null } catch {}
      }
    }
  }

  Log "hidup • RustDesk=$rdId • tunnel=$tun$(if ($tunHealth) { " ($tunHealth)" }) • sesi RDP=$sess • proses RD=$rdProc • sisa=$left"

  # publish ulang status tiap 30 menit (heartbeat untuk dashboard)
  if ((Get-Date) -ge $nextPublish) {
    try {
      Update-Status @{ heartbeat_at = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') } | Out-Null
      & "$PSScriptRoot/publish-status.ps1" -Active $true | Out-Null
      Log 'heartbeat: status di-publish ulang'
    } catch { Log "publish heartbeat gagal (tidak kritis): $($_.Exception.Message)" }
    $nextPublish = (Get-Date).AddMinutes(30)
  }

  Start-Sleep -Seconds 300
}
Log 'durasi inti habis — lanjut ke cleanup. Sesi akan mati bersama job.'
exit 0
