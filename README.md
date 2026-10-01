# XyRDP — Windows RDP 6 Jam via GitHub Actions + Tailscale

RDP Windows Server **gratis** pakai runner `windows-latest` GitHub Actions,
diakses lewat **Tailscale** (tidak ada port publik), sesi ditahan **pas 6 jam**
(batas keras job GitHub), lalu VM musnah sendiri.

```
[Kamu] --Tailscale(100.x.x.x)--> [Windows Server 2022 @ GitHub runner] <--diatur-- workflow rdp-6h.yml
                                      └─ RDP :3389, user xyadmin (admin penuh)
```

## Isi repo
| Path | Fungsi |
|---|---|
| `.github/workflows/rdp-6h.yml` | Workflow utama: boot VM, setup RDP, join Tailscale, tahan 6 jam |
| `scripts/setup-rdp.ps1` | MODE BERSIH: bikin admin, buka RDP, join Tailscale (tanpa tweak lain) |
| `scripts/setup-extras.ps1` | MODE EKSTRA: Lightshot + wallpaper + taskbar translucent + XyDesk host auto-setup |
| `scripts/keepalive.ps1` | Loop penahan sesi + heartbeat tiap 5 menit |
| `scripts/publish-status.ps1` | Tulis `rdp-status.json` ke branch `status` (dibaca web) |
| `scripts/finalize-rdp.ps1` | Logout Tailscale + **hapus node dari tailnet** (OAuth/API token) |
| `scripts/cleanup-actions.ps1` | Bersih-bersih: hapus run Actions lama + log-nya (simpan 3 terbaru) |
| `assets/rdp-extras.json` | Konfigurasi ekstra (bisa diubah dari dashboard web) |
| `assets/wallpaper.jpg` | Wallpaper default (ganti lewat dashboard web: upload → pasang) |
| `web/` | Dashboard lokal (Node, tanpa dependency) |
| `deploy/vercel/` | Versi dashboard untuk hosting di Vercel (catch-all function + Basic Auth) |

## Mode ekstra (otomatis setiap sesi)
Setelah VM siap, `setup-extras.ps1` otomatis memasang yang berikut (bisa dimatikan
lewat input workflow **`ekstra: tidak`**, atau per-item di dashboard web):

| Ekstra | Cara kerja |
|---|---|
| **Lightshot** | Install via `winget` (Skillbrains.Lightshot), fallback installer langsung `app.prntscr.com` silent (`/VERYSILENT`). Auto-run saat user login. |
| **Taskbar translucent** | `EnableTransparency=1` (efek transparansi Windows) + **TranslucentTB** (portable dari GitHub releases, fallback winget) mode default `clear` — bisa diganti: blur/acrylic/opaque/normal. |
| **Wallpaper** | Dari `assets/wallpaper.*` di repo (default: `wallpaper.jpg`), atau input workflow `wallpaper_url`. Dipasang ke **profil Default** → otomatis aktif saat user RDP login pertama, plus diterapkan ke sesi live. |
| **XyDesk host** | Menjalankan `https://rdp.xydesk.my.id/host.ps1` otomatis (RDP + QUIC UDP 4433 + AVC444 + audio bridge sesuai halaman host XyDesk). |

Konfigurasi tersimpan di `assets/rdp-extras.json`:
```json
{
  "lightshot": true,           // pasang Lightshot
  "translucent": true,         // taskbar translucent
  "translucent_mode": "clear", // clear | blur | acrylic | opaque | normal
  "wallpaper": true,           // pakai wallpaper dari repo
  "wallpaper_file": "wallpaper.jpg",
  "xydesk_host": true          // jalankan setup host rdp.xydesk.my.id
}
```
Semua itu bisa diubah **dari dashboard web** (panel "Tampilan & Aplikasi"):
upload wallpaper (drag & drop, otomatis dikecilkan maks 1920px) + toggle
translucent/Lightshot/XyDesk host. Dashboard menulis balik ke repo via GitHub API
(pakai `GITHUB_TOKEN` scope `repo`), jadi berlaku di sesi **berikutnya** tanpa
edit file manual. Catatan: VM sekali-pakai — tidak ada yang bisa "di-apply live"
ke sesi yang sedang jalan.

## Setelah sesi selesai — otomatis bersih
Step **Finalize** (selalu jalan, apa pun hasil sesi) melakukan:
1. **Tailscale logout** + **hapus node dari tailnet** — butuh kredensial API
   (lihat di bawah). Tanpa kredensial: node biarkan (key ephemeral = autohapus sendiri).
2. **Status dibersihkan** — `rdp-status.json` di-set `inactive` dan IP/DNS/ID XyDesk
   **dihapus** dari file publik (tidak ada jejak IP nyangkut di branch `status`).
3. **Run Actions lama dihapus** (termasuk log-nya) — simpan 3 run terbaru
   (`KEEP_RUNS`). Butuh secret `CLEANUP_TOKEN` (PAT scope `repo`).

Kredensial Tailscale (pilih salah satu, set di Settings repo → Secrets):
| Secret | Cara dapat |
|---|---|
| `TAILSCALE_CLIENT_ID` + `TAILSCALE_CLIENT_SECRET` | Tailscale admin console → Settings → OAuth clients (scope **`device:core`** / devices write). **Disarankan.** |
| `TAILSCALE_API_TOKEN` | Tailscale admin console → Settings → Keys → API access tokens (scope **devices:write**) |
| *(tidak ada)* | Pakai auth key **Ephemeral** → node autohapus otomatis saat logout |

Cek hasilnya di log step Finalize: `device 'xyrdp-42' DIHAPUS dari tailnet (terverifikasi)`.

## XyDesk ID & Password
XyDesk Remote Host pakai **ID PC** (turunan dari IPv4, format `nnn-nnn-nnnn`) +
**password login Windows**. Tiap sesi, `setup-extras.ps1` menghitung ID tersebut
(sama seperti `XyDeskHost-Setup.bat`) dan menulisnya ke `rdp-status.json`, jadi
**dashboard menampilkan XyDesk ID otomatis** (beserta tombol SALIN) di panel
Koneksi. Password-nya = password RDP yang sama (sudah tampil di panel Koneksi).

## Dashboard Vercel (produksi)
URL produksi: **https://xyrdp-dash.vercel.app** — halaman terbuka tanpa login; SEMUA endpoint API butuh sesi.
Login lewat form di web (custom, tanpa dialog browser); cookie `sid` HttpOnly 7 hari. Header `Authorization: Basic`
tetap diterima sebagai fallback untuk curl/skrip. Kredensial dari env `AUTH_USER` / `AUTH_PASS` (bukan dari repo).
UI: tanpa emoji, tanpa alert/confirm bawaan browser; stop sesi pakai tombol konfirmasi dua-klik.

Env vars yang dipakai project `xyrdp-dash` (set via dashboard Vercel → Settings → Environment Variables, atau API):

| Key | Type | Isi |
|---|---|---|
| `GITHUB_TOKEN` | sensitive | PAT dengan scope `repo` (buat dispatch/cancel/read logs) |
| `RDP_PASSWORD` | sensitive | password tetap RDP (sama dgn secret Actions) |
| `AUTH_USER` / `AUTH_PASS` | plain/sensitive | login Basic Auth web |
| `GH_OWNER` `GH_REPO` `GH_WORKFLOW` `GH_BRANCH` `RDP_USER` | plain | `xykal` `XyRDP` `rdp-6h.yml` `main` `xyadmin` |

Redeploy setelah ubah kode:
```bash
cd deploy/vercel && npx vercel deploy --prod --yes --token <VercelToken>
```
Config penting: `vercel.json` pakai `routes` legacy `/(.*) -> /api/index.js` supaya semua path lewat function (auth cookie dipegang aplikasi, bukan popup browser), dan `includeFiles: assets/**` supaya `index.html` ikut ke-bundle ke function.

## Secrets repo (sudah dipasang)
- `RDP_PASSWORD` — password **tetap** untuk user `xyadmin` (dipakai juga sebagai password XyDesk)
- `TAILSCALE_AUTH_KEY` — auth key tailnet (harus `tskey-auth-...`)
- `CLEANUP_TOKEN` — PAT scope `repo` untuk hapus run Actions lama (sudah dipasang)
- `TAILSCALE_API_TOKEN` — *opsional*, kalau mau node dihapus otomatis dari admin console
- `TAILSCALE_CLIENT_ID` + `TAILSCALE_CLIENT_SECRET` — *opsional*, alternatif OAuth (disarankan) untuk hapus node

Password RDP **tidak pernah** muncul di log, commit, atau file status — hanya
disimpan lokal di `web/config.json` (gitignored).

## Cara pakai
1. Install **Tailscale** di PC/HP kamu, login ke **tailnet yang sama** dengan auth key di atas.
2. Buka dashboard:
   ```bash
   cd web && node server.js      # butuh Node >= 18, tidak perlu npm install
   ```
   → http://localhost:4173 → tombol **NYALAKAN RDP**.
   (atau manual: Actions → “XyRDP - Windows RDP 6 Jam” → Run workflow)
3. Tunggu ±2–4 menit. Setelah status **LIVE**, dashboard menampilkan **IP Tailscale**.
4. Remote Desktop Connection → alamat `100.x.x.x` → login `xyadmin` + password tetap.
5. Sesi mati sendiri mendekati jam ke-6. Mau mati sekarang? tombol **MATIKAN**.

## Mode bersih (default) + mode ekstra (otomatis)
Base = Windows Server **apa adanya**. Yang dilakukan `setup-rdp.ps1` HANYA:
- Buat user `xyadmin` ∈ **Administrators** + Remote Desktop Users (password tetap, tidak expire)
- `LocalAccountTokenFilterPolicy=1` → supaya login jaringan dapat token admin penuh (ini bagian dari “akses admin”, bukan tweak)
- Aktifkan Remote Desktop port 3389 dengan setting default Windows (NLA ON) + rule firewall grup “Remote Desktop”
- Install + join Tailscale, tulis status

Sesi dijamin **ADMINISTRATOR** (bukan user terbatas): user RDP selalu anggota grup
Administrators, token admin penuh aktif, dan `setup-extras.ps1` memverifikasi
keanggotaan grup tiap sesi (hasilnya masuk ke `rdp-status.json` → `extras.admin`
dan tampil di dashboard).

Tidak ada lagi: tweak UAC/Defender/SmartScreen/Chrome/auto-logon, dan cek reputasi
IP sudah dihapus. Semua itu justru menambah variabel; sesuai request, balik ke vanilla.
Di atas base itu, mode ekstra (Lightshot / wallpaper / translucent / XyDesk host)
berjalan otomatis — lihat bagian “Mode ekstra” di atas. Matikan lewat input
workflow `ekstra: tidak` kalau butuh VM benar-benar polos.

## Login Google dari dalam RDP — fakta jujurnya
Google menantang login berdasarkan **perangkat baru + IP datacenter (Azure)**,
bukan karena setting di Windows. VM-nya sekali-pakai, jadi tiap sesi = “perangkat
asing” di mata Google dan prompt verifikasi (notif HP / telepon / SMS) bisa muncul
kapan pun; tidak ada tweak yang bisa menghapus itu.

Yang tetap didukung kalau mau IP keluar yang “bersih”: input `exit_node`
(Advanced, isi manual lewat Actions UI) — jalankan Tailscale di perangkat rumah
lalu advertise exit node; trafik Chrome keluar dari IP residential.

## Batas & risiko yang wajib tahu
- ⚠️ **ToS GitHub**: Actions diperuntukkan build/test, bukan VPS interaktif.
  Suka tidak suka, RDP-an 6 jam-an punya risiko **suspend akun** (public repo +
  tidak agresif menekan risiko, tapi tidak menghilangkan). Jangan pakai akun utama.
- **Kuota**: Windows runner dihitung 2×. Free plan 2000 menit/bulan ⇒ ≈2 sesi 6 jam.
- **6 jam** adalah batas keras runner hosted — tidak bisa lebih; `timeout-minutes: 360`
  + loop berhenti di menit ~354 supaya cleanup rapi (status menjadi `inactive`).
- Repo sengaja **public** (sesuai preferensi untuk hindari suspend). Tidak ada
  rahasia apa pun yang di-commit: token hidup di Secrets + config lokal.
- Ini VM sekali-pakai: apa pun di `C:\` hilang setelah job selesai. Simpan data
  ke Google Drive/OneDrive lewat browser.

## Struktur status (branch `status` → `rdp-status.json`)
```json
{ "active": true, "tailscale_ip": "100.x.y.z", "tailscale_dns": "xyrdp-12.tailnet.ts.net",
  "rdp_user": "xyadmin", "started_at": "...", "expires_at": "...",
  "extras": { "lightshot": "ok", "translucent": "ok", "wallpaper": "ok",
              "wallpaper_file": "wallpaper.jpg", "xydesk_host": "ok",
              "xydesk_id": "168-375-2296", "xydesk_ids": [ { "iface": "...", "ip": "...", "id": "..." } ],
              "admin": true } }
```
Saat sesi mati, `active=false`, `stopped_at` diisi, dan IP/DNS/`xydesk_id` dikosongkan.
Web mem-poll file ini + status run; tidak ada server perantara yang di-hosting.
Panel “Sesi” di dashboard menampilkan ringkasan `extras` (termasuk bukti sesi admin),
dan panel “Koneksi” menampilkan **XyDesk ID** untuk dipakai bersama password RDP.

## Input workflow (Run workflow di Actions UI)
| Input | Isi |
|---|---|
| `durasi_menit` | 15 … 360 (batas keras job GitHub) |
| `ts_hostname` | hostname Tailscale ( dapat suffix nomor run, mis. `xyrdp-42`) |
| `ekstra` | `ya` (default) / `tidak` — master switch Lightshot+wallpaper+translucent+XyDesk host |
| `wallpaper_url` | URL wallpaper sendiri (jpg/png/bmp); kosong = pakai `assets/wallpaper.*` di repo |
| `exit_node` | (lanjutan) Tailscale exit node |

## Troubleshooting
| Gejala | Penyebab umum |
|---|---|
| `ERROR: secret RDP_PASSWORD/TAILSCALE_AUTH_KEY` | Secrets belum diset / nama salah |
| `tidak dapat IP Tailscale` | Auth key kadaluarsa/revoked, atau tailnet butuh “add devices manually”. Buat key baru (recommend centang **Ephemeral** + **Reusable**) |
| RDP connect ditolak | Pastikan Tailscale di perangkatmu login ke tailnet yang sama (`tailscale status` harus melihat `xyrdp-*`) |
| Google tetap minta verifikasi | Wajar untuk IP datacenter — pakai `exit_node` |
| Run kedua “menggantung” | Sengaja: `concurrency` mengantrekan agar tidak 2 VM sekaligus |
| Node Tailscale nyangkut "offline" di console | Set `TAILSCALE_API_TOKEN` (devices:write) atau OAuth `TAILSCALE_CLIENT_ID/SECRET` (device:core), atau pakai auth key **Ephemeral** |
| Log `butuh secret CLEANUP_TOKEN` | Tanpa itu run lama tidak bisa dihapus (GITHUB_TOKEN Actions cuma actions:read). Pasang PAT scope `repo` sebagai `CLEANUP_TOKEN` |
| Log `lightshot=gagal` / `translucent=sebagian` | Tidak fatal — cek log step “Setup ekstra”: winget/website vendor sedang sag atau terganti. Sesi tetap jalan |
| Wallpaper tidak berubah di sesi baru | Cek `assets/wallpaper.jpg` ada di repo & `wallpaper: true` di `rdp-extras.json`; di dashboard panel “Tampilan” harus muncul pratinjau |
| Taskbar tidak translucent | Efek native tetap aktif; TranslucentTB portable butuh Windows 10/11 — kalau gagal, ganti mode lewat tray icon |
| Upload wallpaper error dari dashboard | `GITHUB_TOKEN` Vercel/lokal harus scope `repo` + branch `main`; gambar maks 3 MB setelah dikecilkan |
