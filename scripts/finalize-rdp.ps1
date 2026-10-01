# ============================================================================
#  finalize-rdp.ps1 — dijalankan setelah sesi berakhir (selalu, apa pun hasilnya):
#   1) baca device ID + MagicDNS dari tailscale status (SEBELUM logout)
#   2) tailscale logout
#   3) hapus device dari tailnet via Tailscale API — OTOMATIS:
#        - TAILSCALE_CLIENT_ID + TAILSCALE_CLIENT_SECRET (OAuth, disarankan)
#        - atau TAILSCALE_API_TOKEN (API key klasik)
#      Kalau dua-duanya tidak ada: node dibiarkan (device key ephemeral =
#      autohapus; key non-ephemeral = harus dihapus manual / set secret).
#   4) verifikasi device benar-benar hilang dari tailnet
# ============================================================================
$ErrorActionPreference = 'Continue'
function Log([string]$m) { Write-Host "[XyRDP:fin] $m" }

$tsExe = Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'
$self = $null
if (Test-Path $tsExe) {
  try { $self = (& $tsExe status --json 2>$null | ConvertFrom-Json).Self } catch {}
  Log 'tailscale logout...'
  & $tsExe logout 2>&1 | Out-Null
} else { Log 'tailscale tidak ada — skip' }

# ---------- token API: OAuth client (disarankan) atau API key klasik ----------
function Get-TsToken {
  if ($env:TAILSCALE_CLIENT_ID -and $env:TAILSCALE_CLIENT_SECRET) {
    try {
      $r = Invoke-RestMethod -Uri 'https://api.tailscale.com/api/v2/oauth/token' -Method POST -TimeoutSec 30 -Body @{
        client_id     = $env:TAILSCALE_CLIENT_ID
        client_secret = $env:TAILSCALE_CLIENT_SECRET
        grant_type    = 'client_credentials'
      }
      if ($r -and $r.access_token) { Log 'token API didapat via OAuth client'; return $r.access_token }
    } catch { Log "OAuth token gagal: $($_.Exception.Message)" }
  }
  if ($env:TAILSCALE_API_TOKEN) { Log 'token API dari TAILSCALE_API_TOKEN (klasik)'; return $env:TAILSCALE_API_TOKEN }
  return $null
}

# nama tailnet = domain MagicDNS (mis. tail01cd7c.ts.net dari xyrdp-42.tail01cd7c.ts.net)
function Get-Tailnet([string]$dnsName) {
  if ($dnsName -and $dnsName.Contains('.')) { return ($dnsName -split '\.', 2)[1].TrimEnd('.') }
  return '-'
}

# ---------- hapus device dari tailnet (retry 3x) ----------
$deleted = $false
if ($self -and $self.ID) {
  $tok = Get-TsToken
  if (-not $tok) {
    Log 'TAILSCALE_API_TOKEN / TAILSCALE_CLIENT_ID+SECRET belum di-set.'
    Log '  -> Kalau auth key EPHEMERAL: node autohapus sendiri setelah logout (aman).'
    Log '  -> Kalau key reusable non-ephemeral: node nyangkut "offline" di console.'
    Log '     Fix: Settings repo -> Secrets -> tambah TAILSCALE_API_TOKEN (Tailscale'
    Log '     admin console -> Settings -> Keys -> API access tokens, scope'
    Log '     devices:write), ATAU OAuth client (scope device:core) lewat'
    Log '     TAILSCALE_CLIENT_ID + TAILSCALE_CLIENT_SECRET.'
  } else {
    $tailnet = Get-Tailnet $self.DNSName
    $hdrs = @{ Authorization = "Bearer $tok" }
    for ($attempt = 1; $attempt -le 3 -and -not $deleted; $attempt++) {
      try {
        $devs = Invoke-RestMethod -Uri "https://api.tailscale.com/api/v2/tailnet/$tailnet/devices" -Headers $hdrs -TimeoutSec 30
        $mine = @($devs.devices | Where-Object { $_.id -eq $self.ID })
        if ($mine.Count -eq 0) {
          Log "device $($self.ID) sudah tidak ada di tailnet (autohapus ephemeral)"; $deleted = $true; break
        }
        $name = $mine[0].name
        Invoke-RestMethod -Method Delete -Uri "https://api.tailscale.com/api/v2/tailnet/$tailnet/devices/$($self.ID)" -Headers $hdrs -TimeoutSec 30 | Out-Null
        # verifikasi
        Start-Sleep -Seconds 2
        $after = Invoke-RestMethod -Uri "https://api.tailscale.com/api/v2/tailnet/$tailnet/devices" -Headers $hdrs -TimeoutSec 30
        if (@($after.devices | Where-Object { $_.id -eq $self.ID }).Count -eq 0) {
          Log "device '$name' DIHAPUS dari tailnet (terverifikasi)"
        } else {
          Log "device '$name' dihapus tapi masih terlihat (cache API, coba lagi)"
        }
        $deleted = $true
      } catch {
        Log "hapus device percobaan $attempt gagal: $($_.Exception.Message)"
        Start-Sleep -Seconds 3
      }
    }
    if (-not $deleted) { Log 'device tailscale belum bisa dihapus (tidak kritis — node akan offline sendiri)' }
  }
} else {
  Log 'device id tailscale tidak diketahui (tailscale tidak jalan?) — skip hapus'
}

Log 'selesai. VM akan dihancurkan GitHub setelah job ini berakhir.'
exit 0
