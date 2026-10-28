-- =====================================================================
-- Tera Kasir · skema database Supabase
-- Jalankan seluruh file ini di Supabase → SQL Editor → New query → Run.
-- Aman dijalankan ulang (idempotent).
--
-- Model: satu akun owner (auth.users) = satu bisnis.
-- businesses.id = auth.uid() si owner, dan semua tabel lain punya
-- kolom business_id. Row Level Security memastikan setiap akun hanya
-- bisa membaca/mengubah baris dengan business_id miliknya sendiri.
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;

-- ---------- Tabel ----------

create table if not exists public.businesses (
  id          uuid primary key default auth.uid() references auth.users(id) on delete cascade,
  nama        text not null default '',
  footer      text not null default '',
  ig          text not null default '',
  contoh      boolean not null default false,   -- true = berisi data contoh
  versi       int not null default 1,           -- naik saat data di-reset, perangkat lain memuat ulang
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table if not exists public.branches (
  business_id uuid not null references public.businesses(id) on delete cascade,
  id          text not null,                    -- '01', '02', ...
  nama        text not null default '',
  pos         text not null default '',         -- 'POS-01'
  alamat      text not null default '',
  updated_at  timestamptz not null default now(),
  primary key (business_id, id)
);

create table if not exists public.staff (
  business_id uuid not null references public.businesses(id) on delete cascade,
  id          text not null,
  nama        text not null default '',
  role        text not null default 'Kasir' check (role in ('Owner','Kasir')),
  pin         text,                             -- diisi manual lewat Table Editor; trigger langsung mengubahnya jadi pin_hash
  pin_hash    text,                             -- sha256(business_id:id:pin), hex
  warna       text not null default '#2EE59D',
  updated_at  timestamptz not null default now(),
  primary key (business_id, id)
);

create table if not exists public.categories (
  business_id uuid not null references public.businesses(id) on delete cascade,
  id          text not null,
  nama        text not null default '',
  warna       text not null default '#2E9E6E',
  urut        int not null default 0,
  dihapus     boolean not null default false,
  updated_at  timestamptz not null default now(),
  primary key (business_id, id)
);

create table if not exists public.products (
  business_id uuid not null references public.businesses(id) on delete cascade,
  id          text not null,
  nama        text not null default '',
  kat         text,
  jenis       text not null default 'barang' check (jenis in ('barang','jasa')),
  harga       bigint not null default 0,
  hpp         bigint not null default 0,
  min         int not null default 0,
  aktif       boolean not null default true,
  urut        int not null default 0,
  updated_at  timestamptz not null default now(),
  primary key (business_id, id)
);

-- Stok per produk per cabang. Diubah lewat apply_stock_deltas() supaya
-- penjualan dari beberapa HP dijumlahkan, bukan saling menimpa.
create table if not exists public.stock (
  business_id uuid not null references public.businesses(id) on delete cascade,
  product_id  text not null,
  branch_id   text not null,
  qty         int not null default 0,
  updated_at  timestamptz not null default now(),
  primary key (business_id, product_id, branch_id)
);

create table if not exists public.transactions (
  business_id uuid not null references public.businesses(id) on delete cascade,
  id          text not null,                    -- dibuat di HP, jadi kirim ulang tidak membuat data dobel
  no          text not null,
  cab         text not null,
  kasir       text not null default '',
  waktu       bigint not null,                  -- epoch milidetik
  items       jsonb not null default '[]',
  sub         bigint not null default 0,
  disc        bigint not null default 0,
  total       bigint not null default 0,
  metode      text not null default 'Tunai',
  bayar       bigint not null default 0,
  kembali     bigint not null default 0,
  status      text not null default 'Lunas' check (status in ('Lunas','Batal')),
  alasan      text,
  batal_oleh  text,
  pelanggan   text not null default '',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  primary key (business_id, id)
);
create index if not exists transactions_waktu_idx on public.transactions (business_id, waktu desc);

create table if not exists public.shifts (
  business_id  uuid not null references public.businesses(id) on delete cascade,
  branch_id    text not null,
  mulai        bigint not null,                 -- epoch ms saat shift dibuka
  status       text not null default 'open' check (status in ('open','closed')),
  kas_awal     bigint not null default 0,
  dibuka_oleh  text,
  tutup        bigint,
  ditutup_oleh text,
  seharusnya   bigint,
  fisik        bigint,
  selisih      bigint,
  catatan      text,
  updated_at   timestamptz not null default now(),
  primary key (business_id, branch_id, mulai)
);

create table if not exists public.cash_movements (
  business_id uuid not null references public.businesses(id) on delete cascade,
  id          text not null,
  cab         text not null,
  tipe        text not null,                    -- Pengeluaran / Purchasing / Setor tunai / Kas masuk
  nominal     bigint not null default 0,
  ket         text not null default '',
  waktu       bigint not null,
  oleh        text not null default '',
  updated_at  timestamptz not null default now(),
  primary key (business_id, id)
);
create index if not exists cash_movements_waktu_idx on public.cash_movements (business_id, waktu desc);

-- Catatan perubahan stok yang sudah diterapkan, supaya kiriman ulang
-- dari HP yang sempat offline tidak menghitung stok dua kali.
create table if not exists public.applied_ops (
  business_id uuid not null references public.businesses(id) on delete cascade,
  op_id       uuid not null,
  applied_at  timestamptz not null default now(),
  primary key (business_id, op_id)
);

-- ---------- updated_at otomatis ----------

create or replace function public.tera_touch() returns trigger
language plpgsql set search_path = '' as $$
begin new.updated_at := now(); return new; end $$;

do $$ declare t text; begin
  foreach t in array array['businesses','branches','staff','categories','products','stock','transactions','shifts','cash_movements'] loop
    execute format('drop trigger if exists tera_touch on public.%I', t);
    execute format('create trigger tera_touch before update on public.%I for each row execute function public.tera_touch()', t);
  end loop;
end $$;

-- ---------- PIN: simpan hash, bukan angka aslinya ----------

create or replace function public.tera_hash_pin() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.pin is not null and new.pin <> '' then
    new.pin_hash := encode(extensions.digest(new.business_id::text || ':' || new.id || ':' || new.pin, 'sha256'), 'hex');
    new.pin := null;
  end if;
  return new;
end $$;
drop trigger if exists tera_hash_pin on public.staff;
create trigger tera_hash_pin before insert or update on public.staff
  for each row execute function public.tera_hash_pin();

-- ---------- Row Level Security ----------

alter table public.businesses enable row level security;
drop policy if exists "pemilik bisnis" on public.businesses;
create policy "pemilik bisnis" on public.businesses for all to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

do $$ declare t text; begin
  foreach t in array array['branches','staff','categories','products','stock','transactions','shifts','cash_movements','applied_ops'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists "pemilik bisnis" on public.%I', t);
    execute format('create policy "pemilik bisnis" on public.%I for all to authenticated
      using (business_id = (select auth.uid())) with check (business_id = (select auth.uid()))', t);
  end loop;
end $$;

-- Hanya pengguna yang sudah login yang boleh menyentuh tabel; anon tidak sama sekali.
revoke all on public.businesses, public.branches, public.staff, public.categories, public.products,
  public.stock, public.transactions, public.shifts, public.cash_movements, public.applied_ops from anon;
grant select, insert, update, delete on public.businesses, public.branches, public.staff, public.categories,
  public.products, public.stock, public.transactions, public.shifts, public.cash_movements, public.applied_ops to authenticated;

-- ---------- Fungsi yang dipanggil aplikasi ----------

-- Terapkan perubahan stok (delta) sekali saja per op id.
-- ops = [{"op":"<uuid>","product":"p1","branch":"01","delta":-2}, ...]
create or replace function public.apply_stock_deltas(ops jsonb) returns void
language plpgsql security invoker set search_path = '' as $$
declare o jsonb; bid uuid := auth.uid();
begin
  if bid is null then raise exception 'Belum login'; end if;
  for o in select value from jsonb_array_elements(ops) loop
    insert into public.applied_ops (business_id, op_id) values (bid, (o->>'op')::uuid) on conflict do nothing;
    if found then
      insert into public.stock (business_id, product_id, branch_id, qty)
      values (bid, o->>'product', o->>'branch', (o->>'delta')::int)
      on conflict (business_id, product_id, branch_id) do update set qty = public.stock.qty + excluded.qty;
    end if;
  end loop;
end $$;

-- Hapus semua data bisnis milik akun yang login (dipakai tombol "Reset data contoh").
create or replace function public.reset_business_data() returns void
language plpgsql security invoker set search_path = '' as $$
declare bid uuid := auth.uid();
begin
  if bid is null then raise exception 'Belum login'; end if;
  delete from public.cash_movements where business_id = bid;
  delete from public.transactions   where business_id = bid;
  delete from public.shifts         where business_id = bid;
  delete from public.stock          where business_id = bid;
  delete from public.products       where business_id = bid;
  delete from public.categories     where business_id = bid;
  delete from public.staff          where business_id = bid;
  delete from public.branches       where business_id = bid;
  delete from public.applied_ops    where business_id = bid;
end $$;

revoke all on function public.apply_stock_deltas(jsonb), public.reset_business_data() from public, anon;
grant execute on function public.apply_stock_deltas(jsonb), public.reset_business_data() to authenticated;

-- ---------- Realtime ----------

do $$ declare t text; begin
  foreach t in array array['businesses','branches','staff','categories','products','stock','transactions','shifts','cash_movements'] loop
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;
