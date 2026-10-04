# XyRDP — status layanan

> ## ⛔ Sesi RDP baru dijeda
> Sejak **4 Oktober 2026**, dashboard dan workflow utama memblokir permintaan RDP baru. **Jangan membuat repo/secret baru atau menjalankan workflow salinan lama.** Jeda ini tidak membatalkan run yang sudah berjalan. Ini bukan solusi untuk menghindari suspend; tujuannya menghentikan penggunaan baru sementara risiko kebijakan ditangani.
>
> GitHub membatasi GitHub-hosted Actions runner untuk pengembangan, pengujian, deployment, atau publikasi software yang terkait dengan repo. Menawarkan runner Windows enam jam sebagai desktop RDP umum berisiko melanggar ketentuan dan dapat menyebabkan Actions/repo dibatasi atau akun disuspend. Lihat [ketentuan resmi Actions](https://docs.github.com/en/site-policy/github-terms/github-terms-for-additional-products-and-features#actions).

Dashboard: [xyrdp-dash.vercel.app](https://xyrdp-dash.vercel.app) · Panduan keselamatan: [xyrdp-dash.vercel.app/panduan](https://xyrdp-dash.vercel.app/panduan)

## Yang berlaku sekarang

- Tombol dashboard, endpoint API, dan job workflow pada repo template utama memblokir sesi baru. Job workflow baru dilewati sebelum runner dialokasikan.
- Run yang sudah berjalan tidak dibatalkan otomatis; perubahan ini tidak mengirim perintah stop.
- Login dashboard masih dapat digunakan untuk memantau status/run lama dan mengelola pengaturan repo lama. Jangan membuat salinan repo baru untuk mencoba melewati jeda.
- Repo yang dibuat dari template adalah salinan mandiri. **Salinan lama tidak menerima pembaruan ini otomatis**; pemiliknya perlu menonaktifkan workflow secara manual di `Actions → pilih workflow XyRDP → menu … → Disable workflow`.
- Dashboard hanya dapat memeriksa *nama* secrets GitHub, bukan membaca nilainya. Pemeriksaan secret, admin login, repo privat, atau Tailscale key tidak membuat penggunaan runner sebagai layanan RDP menjadi sesuai kebijakan.

## Jika akun GitHub disuspend

1. Jangan membuat akun alternatif, repo baru, atau memindahkan workflow untuk menghindari pembatasan.
2. Pemilik akun membaca email/banner GitHub dan mencatat alasan, waktu, serta repo/workflow yang disebutkan.
3. Jika XyRDP dipakai sebagai desktop umum, hentikan penggunaan tersebut. Jelaskan tindakan koreksi dengan jujur; jangan mengirim password, PAT, atau Tailscale auth key.
4. Ajukan peninjauan melalui [Appeal and Reinstatement resmi GitHub](https://support.github.com/contact/reinstatement). Ikuti respons di tiket yang sama; hasil dan pemulihan akun ditentukan GitHub.
5. Jika sudah tidak memakai aksesnya, revoke auth key di [Tailscale Admin → Settings → Keys](https://login.tailscale.com/admin/settings/keys), hapus mesin non-ephemeral yang tidak diperlukan, dan hapus secret repo yang tak lagi digunakan di `Settings → Secrets and variables → Actions`.

Alasan spesifik hanya dapat dipastikan dari notifikasi GitHub dan jawaban Support. Secret hilang biasanya membuat workflow/koneksi gagal; itu saja tidak menjelaskan keputusan suspend.

## Catatan teknis dan yang belum diperbaiki

- **Wallpaper:** skrip lama dapat mencatat “berhasil” tanpa memeriksa hasil panggilan Windows, dan pengaturan profil dapat hanya mengenai runner/default, bukan sesi RDP yang benar-benar dilihat pengguna. Jadi log sukses lama belum membuktikan wallpaper tampil. Tidak ada retest/perbaikan wallpaper yang diterapkan selama RDP dijeda.
- **Tailscale setup:** panduan create-key, Play Store, dan penyimpanan secret sengaja tidak mengarahkan pengguna membuat sesi baru di GitHub Actions. Setelah host Windows/remote desktop yang secara eksplisit mengizinkan akses interaktif dipilih, onboarding dapat dirancang ulang dan diuji dari awal.
- **Grafis pada implementasi lama:** Mesa adalah render software CPU, bukan GPU fisik. Catatan ini hanya mendokumentasikan kode lama; sesi baru tidak tersedia.

## Struktur proyek

| Path | Peran |
|---|---|
| `.github/workflows/rdp-6h.yml` | Workflow template utama, dijeda pada tingkat job sebelum runner dialokasikan |
| `deploy/vercel/api/index.js` | API dashboard; menolak permintaan repo/sesi baru selama jeda |
| `deploy/vercel/assets/index.html` | UI dashboard dan pemberitahuan status |
| `deploy/vercel/assets/panduan.html` | Panduan jeda, perlindungan akun, dan appeal |
| `scripts/setup-rdp.ps1` | Setup Windows lama; tidak dijalankan selama workflow dijeda |
| `scripts/setup-win10.ps1` | Personalisasi Windows lama; wallpaper belum dianggap tervalidasi |
| `scripts/setup-akses.ps1` | Setup akses lama; jangan dispatch selama jeda |
| `assets/rdp-extras.json` | Pengaturan lama dashboard/workflow |

## Rahasia admin dan keamanan repo

Sandi admin dashboard, OAuth secret, GitHub token, dan Cloudflare secret hanya boleh disimpan sebagai environment variables sensitif di Vercel. Jangan commit atau kirim nilainya lewat chat, issue, screenshot, atau log. Jika pernah terekspos, rotasi di layanan pemiliknya. Jangan mengirim nilai `RDP_PASSWORD` atau `TAILSCALE_AUTH_KEY` kepada pengelola dashboard.

## Komunitas

- [Join Saluran XyVerse Technology Global (WhatsApp)](https://whatsapp.com/channel/0029VbB7nwuJZg3ym6UQ4Z1L)
- [Gabung Grup XyCloud (WhatsApp)](https://chat.whatsapp.com/DpROBXmeUHJGcXecfxP6n7?s=cl&p=a&ilr=2&amv=0)

<sub>XyRDP adalah proyek komunitas dan bukan produk resmi GitHub, Microsoft, Cloudflare, Tailscale, atau XyDesk.</sub>
