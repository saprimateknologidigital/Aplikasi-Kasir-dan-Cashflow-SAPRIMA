# Menyambungkan Tera ke Supabase

Panduan ini dipakai sekali saja untuk menyiapkan database. Setelah itu aplikasi di Vercel langsung menyimpan data ke Supabase.

## Cara kerjanya

- **Satu akun owner = satu bisnis.** Owner login pakai email dan kata sandi (Supabase Auth). Semua data bisnis itu ditandai dengan ID akun owner.
- **Setiap HP kasir diaktifkan sekali oleh owner.** Owner login di HP itu satu kali. Setelah itu kasir cukup memilih terminal dan memasukkan PIN seperti biasa.
- **Data disimpan di Supabase:** pengguna/PIN, cabang (POS), kategori, produk, stok, transaksi, shift, dan kas.
- **Yang tetap disimpan di HP saja:** keranjang yang sedang diisi, pesanan tersimpan (open bill), dan siapa kasir yang sedang login di HP itu.
- **Realtime:** transaksi, stok, dan shift dari satu HP langsung muncul di HP lain.
- **Offline:** kalau internet putus, transaksi tetap tersimpan di HP (antrean). Begitu online lagi, antrean dikirim otomatis. Setiap transaksi punya ID unik dan setiap perubahan stok punya nomor unik, jadi pengiriman ulang tidak membuat data dobel.
- **Keamanan:** Row Level Security (RLS) aktif di semua tabel. Akun bisnis A hanya bisa membaca dan mengubah baris milik bisnis A.

## Langkah 1: Jalankan skema database

1. Buka [Supabase Dashboard](https://supabase.com/dashboard), pilih project **ksmcncvbfwaaeiilpkni**.
2. Menu kiri: **SQL Editor** → **New query**.
3. Buka file [`schema.sql`](schema.sql), salin **seluruh** isinya, tempel di editor.
4. Klik **Run**. Hasil yang benar: `Success. No rows returned`.

File ini aman dijalankan ulang kalau nanti ada perubahan skema.

Cek hasilnya di **Table Editor**: harus ada tabel `businesses`, `branches`, `staff`, `categories`, `products`, `stock`, `transactions`, `shifts`, `cash_movements`, dan `applied_ops`. Semuanya berlabel RLS enabled.

## Langkah 2: Atur alamat aplikasi (untuk email konfirmasi)

1. Menu **Authentication** → **URL Configuration**.
2. **Site URL**: isi alamat Vercel, misalnya `https://nama-app.vercel.app`.
3. **Redirect URLs**: tambahkan alamat yang sama.

Langkah ini perlu supaya link di email konfirmasi pendaftaran membuka aplikasi kamu.

## Langkah 3: Buat akun owner

Pilih salah satu:

- **Lewat dashboard (paling cepat):** **Authentication** → **Users** → **Add user** → **Create new user**. Isi email dan kata sandi, centang **Auto Confirm User**, lalu simpan.
- **Lewat aplikasi:** di layar "Masuk akun bisnis" klik **Belum punya akun? Daftar**. Supabase akan mengirim email konfirmasi. Klik link-nya, lalu masuk.

## Langkah 4: Isi data contoh dan coba

1. Buka aplikasi di Vercel, lalu masuk dengan akun owner.
2. Karena akun masih kosong, muncul layar **Siapkan bisnis**:
   - **Isi data contoh**: data Teh Poci Mas Endow (2 cabang, 3 pengguna, 14 menu, riwayat transaksi 14 hari) dikirim ke Supabase.
   - **Mulai dari kosong**: isi nama usaha, nama owner, dan PIN owner. Aplikasi membuat 1 cabang (POS-01) dan 1 kategori "Umum".
3. Pilih terminal, pilih pengguna, lalu masukkan PIN. PIN data contoh: Endow (Owner) `111111`, Ibik `222222`, Sari `333333`.

Untuk mengulang dari awal: login sebagai Owner, lalu klik **Reset data contoh** di menu samping. Semua data bisnis diganti dengan data contoh, dan HP lain ikut memuat ulang.

## Langkah 5: Uji sinkron dan offline

- **Dua HP:** buka aplikasi di HP kedua dan login dengan akun owner yang sama. Buat transaksi di HP pertama, lalu buka Laporan di HP kedua. Transaksinya langsung muncul.
- **Offline:** di HP kasir, nyalakan mode pesawat lalu buat transaksi tunai. Label di atas berubah jadi "Offline · N menunggu". Matikan mode pesawat, label kembali "Tersinkron", dan transaksinya muncul di HP lain.

Agar aplikasi bisa dibuka ulang saat offline, buka aplikasi sekali dalam keadaan online dulu, supaya halamannya tersimpan oleh service worker.

## Menambah kasir atau cabang (sementara, lewat Table Editor)

Aplikasi belum punya layar untuk mengelola kasir dan cabang. Sementara ini tambahkan lewat **Table Editor**:

- **Kasir baru**: buka tabel `staff` → **Insert row**. Isi:
  - `business_id`: salin dari tabel `businesses`
  - `id`: kode unik, misalnya `u4`
  - `nama`
  - `role`: `Kasir` atau `Owner`
  - `pin`: 6 angka

  PIN otomatis diubah jadi hash dan kolom `pin` dikosongkan lagi. Nanti untuk ganti PIN, cukup isi kolom `pin` lagi.
- **Cabang baru**: buka tabel `branches` → **Insert row**. Isi `business_id`, `id` (misalnya `03`), `nama`, `pos` (misalnya `POS-03`), dan `alamat`.

## Catatan keamanan

- Di kode hanya ada **Project URL** dan **publishable key**. Keduanya memang dirancang untuk dipakai di aplikasi web. Yang melindungi data adalah RLS.
- **Jangan pernah** menaruh `service_role` key, secret key, atau password database di kode atau di repo.
- Kalau tidak ingin orang lain bisa mendaftar bisnis baru, matikan pendaftaran: **Authentication** → **Sign In / Providers** → nonaktifkan **Allow new users to sign up**.
