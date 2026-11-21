-- Sahayogi Nepal: baseline schema. Person 2 owns all migrations.
create extension if not exists postgis;
create extension if not exists pgcrypto;

create type request_kind as enum ('resource_request','manpower_request','donation_offer','healthcare_request','transport_request');
create type request_status as enum ('pending_admin_review','approved','declined','awaiting_assignment','assigned','in_progress','fulfilled','partially_fulfilled','cancelled');
create type assignment_state as enum ('offered','accepted','declined','expired','en_route_to_pickup','picked_up','en_route_to_destination','delivered','disputed','cancelled');
create type assignment_type as enum ('general','transport','healthcare','resource_delivery','donation_pickup');
create type inventory_phase as enum ('received','processing','ready_to_ship','reserved','dispatched','consumed','returned','adjusted');
create type app_role as enum ('admin','volunteer');
create type review_status as enum ('submitted','under_review','approved','declined');
create type incident_status as enum ('open','under_review','resolved','dismissed');

create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null, email text, phone text,
  role app_role not null default 'volunteer',
  account_status text not null default 'active' check (account_status in ('active','suspended')),
  categories text[] not null default '{}' check (categories <@ array['A','B','C']),
  created_at timestamptz not null default now()
);

create table volunteer_applications (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid references profiles(id),
  name text not null, email text not null, phone text not null,
  volunteer_type text not null check (volunteer_type in ('general','driver','healthcare')),
  identity_number text,
  document_paths text[] not null default '{}',
  review_status review_status not null default 'submitted',
  reviewer_id uuid references profiles(id), review_reason text,
  created_at timestamptz not null default now(), reviewed_at timestamptz
);

create table requests (
  id uuid primary key default gen_random_uuid(),
  public_ref text not null unique default ('SN-' || upper(substr(encode(gen_random_bytes(6),'hex'),1,8))),
  tracking_token_hash text,
  kind request_kind not null,
  status request_status not null default 'pending_admin_review',
  requester_name text not null, requester_phone text not null,
  district text not null,
  location geography(Point,4326),
  urgency text not null default 'normal' check (urgency in ('low','normal','high','critical')),
  notes text, decline_reason text,
  created_by uuid references profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  fulfilled_at timestamptz, picked_up_at timestamptz
);
create index requests_location_gix on requests using gist(location);
create index requests_status_idx on requests(status, created_at);

create table request_items (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references requests(id) on delete cascade,
  item_type text not null,
  qty numeric not null check (qty > 0),
  unit text not null,
  approved_qty numeric check (approved_qty >= 0),
  fulfilled_qty numeric check (fulfilled_qty >= 0)
);
create index request_items_req_idx on request_items(request_id);

create table assignments (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references requests(id),
  assignment_type assignment_type not null,
  required_category text not null check (required_category in ('A','B','C')),
  volunteer_id uuid references profiles(id),
  state assignment_state not null default 'offered',
  route_snapshot jsonb not null default '{}',
  offered_at timestamptz not null default now(),
  escalate_at timestamptz,
  accepted_at timestamptz, completed_at timestamptz
);
create index assignments_state_idx on assignments(state, required_category);

create table assignment_events (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid not null references assignments(id) on delete cascade,
  event_type text not null, actor_id uuid, payload jsonb not null default '{}',
  created_at timestamptz not null default now()
);

create table inventory_lots (
  id uuid primary key default gen_random_uuid(),
  item_type text not null, unit text not null,
  source text, provider_name text, provider_contact text,
  received_qty numeric not null check (received_qty >= 0),
  available_qty numeric not null check (available_qty >= 0),
  phase inventory_phase not null default 'received',
  condition text, expiry_date date,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

create table inventory_movements (
  id uuid primary key default gen_random_uuid(),
  lot_id uuid not null references inventory_lots(id),
  request_id uuid references requests(id),
  assignment_id uuid references assignments(id),
  from_phase inventory_phase, to_phase inventory_phase not null,
  quantity numeric not null, reason text, actor_id uuid,
  created_at timestamptz not null default now()
);

create table otp_challenges (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid not null references assignments(id),
  purpose text not null check (purpose in ('pickup','delivery')),
  code_hash text not null, expires_at timestamptz not null,
  attempts int not null default 0, consumed_at timestamptz
);

create table incidents (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid references assignments(id),
  reporter text, incident_type text not null, reported_qty numeric,
  status incident_status not null default 'open',
  resolution text, admin_notes text,
  created_at timestamptz not null default now()
);

create table device_tokens (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references profiles(id) on delete cascade,
  fcm_token text not null unique, platform text, last_seen_at timestamptz not null default now()
);

create table audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid, action text not null, entity text not null, entity_id uuid,
  before jsonb, after jsonb, created_at timestamptz not null default now()
);

create or replace function is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles where id = auth.uid() and role = 'admin' and account_status = 'active');
$$;

alter table profiles enable row level security;
alter table volunteer_applications enable row level security;
alter table requests enable row level security;
alter table request_items enable row level security;
alter table assignments enable row level security;
alter table assignment_events enable row level security;
alter table inventory_lots enable row level security;
alter table inventory_movements enable row level security;
alter table otp_challenges enable row level security;   -- no policies => service role only
alter table incidents enable row level security;
alter table device_tokens enable row level security;
alter table audit_logs enable row level security;

create policy profiles_self on profiles for select using (id = auth.uid() or is_admin());
create policy profiles_admin_write on profiles for all using (is_admin()) with check (is_admin());
create policy vapps_admin on volunteer_applications for all using (is_admin()) with check (is_admin());
create policy requests_admin on requests for all using (is_admin()) with check (is_admin());
create policy requests_own on requests for select using (created_by = auth.uid());
-- Anonymous INSERT intentionally NOT allowed; use the submit-request Edge Function.
create policy items_admin on request_items for all using (is_admin()) with check (is_admin());
create policy assignments_admin on assignments for all using (is_admin()) with check (is_admin());
create policy assignments_mine on assignments for select using (volunteer_id = auth.uid());
create policy assignments_offers on assignments for select using (
  state = 'offered' and volunteer_id is null and exists (
    select 1 from profiles p where p.id = auth.uid() and p.account_status = 'active'
      and required_category = any(p.categories)));
create policy events_admin on assignment_events for select using (is_admin());
create policy inv_lots_admin on inventory_lots for all using (is_admin()) with check (is_admin());
create policy inv_moves_admin on inventory_movements for select using (is_admin());
create policy incidents_admin on incidents for all using (is_admin()) with check (is_admin());
create policy tokens_own on device_tokens for all using (profile_id = auth.uid()) with check (profile_id = auth.uid());
create policy audit_admin on audit_logs for select using (is_admin());

create or replace function claim_assignment(p_assignment_id uuid)
returns assignments language plpgsql security definer set search_path = public as $$
declare a assignments; p profiles;
begin
  select * into p from profiles where id = auth.uid() and account_status = 'active';
  if p.id is null then raise exception 'not_eligible'; end if;
  select * into a from assignments where id = p_assignment_id for update;
  if a.id is null then raise exception 'not_found'; end if;
  if not (a.required_category = any(p.categories)) then raise exception 'not_eligible'; end if;
  if a.state <> 'offered' or a.volunteer_id is not null then raise exception 'already_claimed'; end if;
  update assignments set volunteer_id = p.id, state = 'accepted', accepted_at = now() where id = a.id returning * into a;
  insert into assignment_events(assignment_id, event_type, actor_id) values (a.id, 'accepted', p.id);
  return a;
end $$;
revoke all on function claim_assignment(uuid) from public, anon;
grant execute on function claim_assignment(uuid) to authenticated;

create or replace view public_map_markers as
  select r.id, r.district,
         round(st_y(r.location::geometry)::numeric, 2) as lat,
         round(st_x(r.location::geometry)::numeric, 2) as lng,
         case when r.fulfilled_at is not null then 'fulfilled'
              when r.picked_up_at is not null then 'pickup' else 'open_request' end as marker_type,
         coalesce(r.fulfilled_at, r.picked_up_at, r.created_at) as event_at
  from requests r
  where r.status not in ('pending_admin_review','declined','cancelled')
    and (  (r.fulfilled_at is not null and r.fulfilled_at >= now() - interval '12 hours')
        or (r.picked_up_at is not null and r.fulfilled_at is null and r.picked_up_at >= now() - interval '6 hours')
        or (r.fulfilled_at is null and r.picked_up_at is null));
grant select on public_map_markers to anon, authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('identity-docs', 'identity-docs', false, 5242880, array['image/jpeg','image/png','application/pdf'])
on conflict (id) do nothing;
create policy "identity docs admin read" on storage.objects for select using (bucket_id = 'identity-docs' and is_admin());
-- Uploads: server function returning signed upload URLs (Person 2 TODO).
