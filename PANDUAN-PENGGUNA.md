# XyRDP — pemberitahuan jeda

**Dashboard:** [xyrdp-dash.vercel.app](https://xyrdp-dash.vercel.app) · **Status dan langkah aman:** [xyrdp-dash.vercel.app/panduan](https://xyrdp-dash.vercel.app/panduan)

> **Sesi RDP baru dijeda.** Jangan buat repo/secret baru atau jalankan workflow XyRDP dari salinan lama untuk melewati jeda. Job pada repo template utama sekarang dilewati sebelum runner dibuat; run yang sudah berjalan tidak dibatalkan otomatis.

## Kenapa dijeda?

Ketentuan GitHub Actions membatasi GitHub-hosted runner untuk pengembangan, pengujian, deployment, atau publikasi software yang berkaitan dengan repo. Menahan runner Windows hingga enam jam sebagai desktop RDP umum berisiko dianggap penggunaan di luar batas. GitHub menyebut job, Actions, repo, bahkan akun dapat dibatasi atau disuspend. Login admin, repo privat, secret lengkap, dan Tailscale tidak mengubah tujuan pemakaian tersebut. Baca [ketentuan resmi Actions](https://docs.github.com/en/site-policy/github-terms/github-terms-for-additional-products-and-features#actions).

## Jika kamu memiliki repo hasil template lama

Salinan template bersifat mandiri, jadi tidak menerima perubahan repo utama secara otomatis. Untuk mencegah workflow lama dijalankan:

1. Buka repo XyRDP milikmu di GitHub.
2. Pilih tab **Actions**.
3. Pilih workflow XyRDP di daftar kiri.
4. Buka menu **…** lalu pilih **Disable workflow**.
5. Jangan membuat akun atau repo lain untuk menghindari pembatasan.

Dashboard pusat menolak permintaan start baru, tetapi tidak dapat menimpa workflow lama yang disalin ke repo pengguna dan dijalankan langsung dari GitHub.

## Jika akun GitHub sudah disuspend

1. Pemilik akun membaca email/banner GitHub dan mencatat alasan serta workflow/repo yang disebutkan.
2. Hentikan penggunaan runner sebagai desktop umum. Jangan membuat akun alternatif atau mencoba menyamarkan workflow.
3. Ajukan banding/permintaan pemulihan lewat [form resmi GitHub](https://support.github.com/contact/reinstatement). Ceritakan fakta dengan jujur dan sebutkan tindakan koreksi. Tidak ada jaminan hasil; keputusan ada pada GitHub.
4. Ikuti balasan di tiket yang sama. Jangan membuka banyak tiket sekaligus.
5. Jangan kirim password, PAT, OAuth secret, atau Tailscale auth key ke chat, issue, screenshot, atau form publik.

## Amankan secret dan Tailscale jika tidak lagi dipakai

- Di repo lama, buka **Settings → Secrets and variables → Actions**. Hapus secret yang tidak akan digunakan. GitHub tidak dapat menampilkan kembali nilai secret yang tersimpan.
- Di [Tailscale Admin → Settings → Keys](https://login.tailscale.com/admin/settings/keys), revoke auth key yang tidak dibutuhkan. Di bagian **Machines**, hapus node sesi lama/non-ephemeral yang tidak lagi diperlukan.
- Jangan buat auth key baru untuk memulai workflow yang dijeda. Key kosong/salah biasanya menyebabkan setup atau koneksi gagal; itu saja tidak menjelaskan keputusan suspend akun.

## Wallpaper dan status teknis

Skrip lama dapat menulis status “berhasil” tanpa mengecek hasil panggilan Windows dan bisa mengatur profil runner/default, bukan desktop RDP yang benar-benar dilihat pengguna. Karena sesi baru dijeda, wallpaper belum diperbaiki atau dites ulang pada host interaktif yang sesuai. Jangan unggah ulang dengan harapan sesi baru akan memakai gambar saat jeda masih aktif.

Jika membutuhkan remote desktop, gunakan layanan Windows/remote desktop terkelola yang secara eksplisit mengizinkan akses interaktif sesuai paketnya. Setelah host tersebut dipilih, panduan Tailscale, aplikasi HP, pengelolaan key, dan wallpaper perlu dibuat ulang untuk host itu—bukan untuk GitHub Actions.

## Komunitas

- [Join Saluran XyVerse Technology Global di WhatsApp](https://whatsapp.com/channel/0029VbB7nwuJZg3ym6UQ4Z1L)
- [Gabung Grup XyCloud di WhatsApp](https://chat.whatsapp.com/DpROBXmeUHJGcXecfxP6n7?s=cl&p=a&ilr=2&amv=0)
- [Kembali ke dashboard](https://xyrdp-dash.vercel.app)
