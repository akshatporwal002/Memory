-- Engram shared-library sync foundation.
-- Apply through the Supabase CLI/dashboard after creating an Auth-enabled project.
-- This migration intentionally exposes no service-role secret and grants nothing to anon.

create table if not exists public.engram_libraries (
    id uuid primary key,
    owner_id uuid not null references auth.users(id) on delete cascade,
    schema_version integer not null check (schema_version >= 1),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (id, owner_id)
);

create table if not exists public.engram_sync_operations (
    id uuid primary key,
    library_id uuid not null,
    owner_id uuid not null references auth.users(id) on delete cascade,
    device_id uuid not null,
    client_sequence bigint not null check (client_sequence > 0),
    operation_kind text not null check (operation_kind in (
        'librarySnapshot', 'deckUpsert', 'noteUpsert', 'cardUpsert', 'reviewRecorded',
        'reviewCorrected', 'settingsChanged', 'mediaReference', 'tombstone'
    )),
    payload bytea not null check (octet_length(payload) > 0),
    payload_format text not null,
    created_at timestamptz not null,
    server_cursor bigint generated always as identity unique,
    constraint engram_sync_operations_library_owner_fkey
        foreign key (library_id, owner_id) references public.engram_libraries(id, owner_id) on delete cascade,
    constraint engram_sync_operations_device_sequence_unique unique (library_id, device_id, client_sequence)
);

create table if not exists public.engram_sync_checkpoints (
    library_id uuid not null,
    owner_id uuid not null references auth.users(id) on delete cascade,
    device_id uuid not null,
    cursor bigint not null default 0 check (cursor >= 0),
    updated_at timestamptz not null default now(),
    primary key (library_id, device_id),
    constraint engram_sync_checkpoints_library_owner_fkey
        foreign key (library_id, owner_id) references public.engram_libraries(id, owner_id) on delete cascade
);

create index if not exists engram_sync_operations_library_cursor_idx
    on public.engram_sync_operations (library_id, server_cursor);
create index if not exists engram_sync_operations_owner_library_idx
    on public.engram_sync_operations (owner_id, library_id);

alter table public.engram_libraries enable row level security;
alter table public.engram_sync_operations enable row level security;
alter table public.engram_sync_checkpoints enable row level security;

revoke all on table public.engram_libraries, public.engram_sync_operations, public.engram_sync_checkpoints from anon, authenticated;
grant select, insert, update on table public.engram_libraries to authenticated;
grant select, insert on table public.engram_sync_operations to authenticated;
grant select, insert, update on table public.engram_sync_checkpoints to authenticated;

create policy "Authenticated users manage their own Engram libraries"
on public.engram_libraries for all to authenticated
using ((select auth.uid()) = owner_id)
with check ((select auth.uid()) = owner_id);

create policy "Authenticated users read their own Engram operation log"
on public.engram_sync_operations for select to authenticated
using ((select auth.uid()) = owner_id);

create policy "Authenticated users append operations to their own library"
on public.engram_sync_operations for insert to authenticated
with check ((select auth.uid()) = owner_id);

create policy "Authenticated users manage their own device checkpoints"
on public.engram_sync_checkpoints for all to authenticated
using ((select auth.uid()) = owner_id)
with check ((select auth.uid()) = owner_id);
