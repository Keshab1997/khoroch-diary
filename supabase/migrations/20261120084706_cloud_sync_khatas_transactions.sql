-- Khoroch Diary cloud sync (spec B5). The phone's SQLite stays the source of
-- truth; these tables mirror `khatas` and `transactions` for the signed-in
-- user. Money is integer paise. Entry deletes and khata archives are
-- tombstones (`deleted_at`): the app never hard-deletes, so there is no
-- DELETE policy. `server_updated_at` is the pull cursor and is set by the
-- server only.

create table public.khatas (
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  id text not null check (length(id) between 1 and 64),
  name text not null check (length(name) between 1 and 120),
  opening_balance_paise bigint not null default 0,
  currency text not null default 'INR' check (length(currency) = 3),
  sort_order integer not null default 0,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  server_updated_at timestamptz not null default now(),
  primary key (user_id, id)
);

create table public.transactions (
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  id text not null check (length(id) between 1 and 64),
  khata_id text not null,
  type text not null check (type in ('income', 'expense')),
  amount_paise bigint not null check (amount_paise > 0),
  category_id text not null check (length(category_id) between 1 and 80),
  description text check (description is null or length(description) <= 120),
  occurred_at timestamptz not null,
  note_session_id text,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  server_updated_at timestamptz not null default now(),
  primary key (user_id, id),
  foreign key (user_id, khata_id) references public.khatas (user_id, id)
);

create index transactions_user_khata_idx on public.transactions (user_id, khata_id);
create index khatas_user_pull_idx on public.khatas (user_id, server_updated_at);
create index transactions_user_pull_idx on public.transactions (user_id, server_updated_at);

-- Last write wins by the client's updated_at; on a tie a tombstone beats a
-- revival. A losing write leaves the stored row (and its cursor) untouched.
create function public.khatabook_sync_write()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' then
    if new.user_id is distinct from old.user_id or new.id is distinct from old.id then
      raise exception 'A synced row cannot change owner or id.';
    end if;
    if new.updated_at < old.updated_at
       or (new.updated_at = old.updated_at
           and old.deleted_at is not null and new.deleted_at is null) then
      return old;
    end if;
  end if;
  new.server_updated_at := now();
  return new;
end;
$$;

create trigger khatas_sync_write before insert or update on public.khatas
  for each row execute function public.khatabook_sync_write();
create trigger transactions_sync_write before insert or update on public.transactions
  for each row execute function public.khatabook_sync_write();

alter table public.khatas enable row level security;
alter table public.transactions enable row level security;

revoke all on table public.khatas, public.transactions from anon;
revoke delete, truncate on table public.khatas, public.transactions from authenticated;

create policy khatas_select_own on public.khatas for select to authenticated
  using ((select auth.uid()) = user_id);
create policy khatas_insert_own on public.khatas for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy khatas_update_own on public.khatas for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

create policy transactions_select_own on public.transactions for select to authenticated
  using ((select auth.uid()) = user_id);
create policy transactions_insert_own on public.transactions for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy transactions_update_own on public.transactions for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
