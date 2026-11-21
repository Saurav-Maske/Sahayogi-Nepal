create extension if not exists postgis with schema extensions;
create extension if not exists pgcrypto with schema extensions;

create type user_role as enum ('volunteer','admin');
create type volunteer_type as enum ('manpower','driver','doctor');
create type review_status as enum ('submitted','under_review','approved','declined');
create type request_kind as enum ('resource_request','manpower_request','donation_offer',
  'healthcare_request','transport_request');
create type request_status as enum ('pending_admin_review','approved','declined','awaiting_assignment',
  'assigned','in_progress','fulfilled','partially_fulfilled','cancelled');
create type item_type as enum ('food','cloth','temp_shelter','medical_supplies','drinking_water');
create type assignment_type as enum ('manpower','delivery','pickup','healthcare','transport');
create type assignment_state as enum ('offered','accepted','declined','expired','en_route_to_pickup',
  'picked_up','en_route_to_destination','delivered','disputed','cancelled');
create type inventory_phase as enum ('received','processing','ready_to_ship','reserved','dispatched',
  'consumed','returned','adjusted');

create table districts (
  id serial primary key, name text unique not null, province text,
  lat double precision not null, lng double precision not null   
);

create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null, email text, phone text,
  role user_role not null default 'volunteer',
  volunteer_type volunteer_type,                                
  categories text[] not null default '{}' check (categories <@ array['A','B','C']),
  account_status text not null default 'active' check (account_status in ('active','suspended')),
  created_at timestamptz not null default now()
);

create table volunteer_applications (                            
  id uuid primary key default gen_random_uuid(),
  profile_id uuid references profiles(id),                       
  full_name text not null, email text not null, phone text not null,
  volunteer_type volunteer_type not null,
  citizenship_no text not null, citizenship_photo_path text not null,
  license_no text, license_photo_path text,
  service_card_no text, service_card_photo_path text,
  review_status review_status not null default 'submitted',
  review_note text, reviewed_by uuid references profiles(id), reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  check (volunteer_type <> 'driver' or (license_no is not null and license_photo_path is not null)),
  check (volunteer_type <> 'doctor' or (service_card_no is not null and service_card_photo_path is not null))
);

create or replace function is_admin() returns boolean
language sql stable security definer set search_path = public, extensions as $$
  select exists (select 1 from profiles
                 where id = auth.uid() and role = 'admin' and account_status = 'active');
$$;

create table app_settings (key text primary key, value jsonb not null);

create table requests (
  id uuid primary key default gen_random_uuid(),
  public_ref text unique not null default upper(substr(replace(gen_random_uuid()::text,'-',''),1,8)),
  kind request_kind not null,
  status request_status not null default 'pending_admin_review',
  requester_name text not null, requester_phone text not null,
  requester_profile_id uuid references profiles(id),         
  district_id int not null references districts(id),            
  location extensions.geography(Point,4326) not null,
  address_note text,
  urgency text not null default 'normal' check (urgency in ('low','normal','high','critical')),
  notes text, volunteers_needed int check (volunteers_needed is null or volunteers_needed > 0),
  decline_reason text,
  tracking_token_hash text not null,
  approved_at timestamptz, picked_up_at timestamptz, fulfilled_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index requests_location_gix on requests using gist (location);
create index requests_status_idx on requests (status, created_at);
create index requests_pickup_idx on requests (picked_up_at) where picked_up_at is not null;
create index requests_fulfil_idx on requests (fulfilled_at) where fulfilled_at is not null;

create table request_items (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references requests(id) on delete cascade,
  item_type item_type not null,
  requested_qty numeric(12,2) not null check (requested_qty > 0),
  approved_qty numeric(12,2) check (approved_qty >= 0),         
  donor_qty numeric(12,2) check (donor_qty >= 0),                
  confirmed_qty numeric(12,2) check (confirmed_qty >= 0),        
  unit text not null default 'unit'
);
create index request_items_req_idx on request_items (request_id);

create table inventory_lots (
  id uuid primary key default gen_random_uuid(),
  item_type item_type not null, unit text not null default 'unit',
  quantity numeric(12,2) not null check (quantity >= 0),
  reserved_qty numeric(12,2) not null default 0 check (reserved_qty >= 0),
  phase inventory_phase not null default 'received',             
  provider_name text, provider_contact text,                    
  source_request_id uuid references requests(id),
  condition_note text, created_by uuid references profiles(id),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  check (reserved_qty <= quantity)                               
);

create table inventory_movements (                               
  id uuid primary key default gen_random_uuid(),
  lot_id uuid not null references inventory_lots(id),
  from_phase inventory_phase, to_phase inventory_phase not null,
  quantity numeric(12,2) not null, reason text,
  actor_id uuid, request_id uuid, assignment_id uuid,
  created_at timestamptz not null default now()
);

create table inventory_reservations (
  id uuid primary key default gen_random_uuid(),
  request_item_id uuid not null references request_items(id) on delete cascade,
  lot_id uuid not null references inventory_lots(id),
  quantity numeric(12,2) not null check (quantity > 0),
  status text not null default 'active' check (status in ('active','dispatched','released')),
  created_at timestamptz not null default now()
);

create view inventory_available with (security_invoker = true) as
  select item_type, sum(quantity - reserved_qty) as available_qty
  from inventory_lots where phase = 'ready_to_ship' group by item_type;

create table assignments (                                        
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references requests(id) on delete cascade,
  assignment_type assignment_type not null,
  required_tier text not null check (required_tier in ('A','B','C')),
  state assignment_state not null default 'offered',
  volunteer_id uuid references profiles(id),
  declined_by uuid[] not null default '{}',
  offered_at timestamptz not null default now(),
  escalate_at timestamptz,                                       
  accepted_at timestamptz, completed_at timestamptz,
  route_snapshot jsonb not null default '[]',                    
  items_snapshot jsonb not null default '[]',                     
  created_at timestamptz not null default now()
);
create index assignments_open_idx on assignments (state, required_tier) where volunteer_id is null;
create index assignments_vol_idx on assignments (volunteer_id);

create table assignment_events (
  id bigint generated always as identity primary key,
  assignment_id uuid not null references assignments(id) on delete cascade,
  event_type text not null, actor_id uuid, payload jsonb, created_at timestamptz not null default now()
);

create table otp_challenges (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid not null references assignments(id) on delete cascade,
  purpose text not null check (purpose in ('pickup','delivery')),
  code_hash text not null,                                        -- bcrypt via crypt(); never store the plain code
  expires_at timestamptz not null, attempts int not null default 0, consumed_at timestamptz,
  created_at timestamptz not null default now()
);

create table incidents (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid references assignments(id), request_id uuid references requests(id),
  incident_type text not null default 'short_delivery',
  reporter_note text, reported_shortfall jsonb,
  status text not null default 'open' check (status in ('open','under_review','resolved','dismissed')),
  resolution text, admin_notes text, created_at timestamptz not null default now()
);

create table volunteer_locations (
  assignment_id uuid primary key references assignments(id) on delete cascade,
  lat double precision not null, lng double precision not null, updated_at timestamptz not null default now()
);

create table device_tokens (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references profiles(id) on delete cascade,
  token text unique not null, platform text check (platform in ('android','ios','web')),
  last_seen_at timestamptz not null default now()
);

create table audit_logs (
  id bigint generated always as identity primary key,
  actor_id uuid, action text not null, entity text not null, entity_id uuid,
  detail jsonb, created_at timestamptz not null default now()
);

alter table profiles enable row level security;
alter table volunteer_applications enable row level security;
alter table requests enable row level security;
alter table request_items enable row level security;
alter table inventory_lots enable row level security;
alter table inventory_movements enable row level security;
alter table inventory_reservations enable row level security;
alter table assignments enable row level security;
alter table assignment_events enable row level security;
alter table otp_challenges enable row level security;            
alter table incidents enable row level security;
alter table volunteer_locations enable row level security;
alter table device_tokens enable row level security;
alter table audit_logs enable row level security;
alter table app_settings enable row level security;
alter table districts enable row level security;

create policy districts_read on districts for select using (true);

create policy profiles_read on profiles for select using (id = auth.uid() or is_admin());
create policy profiles_admin on profiles for update using (is_admin());

create policy apps_admin on volunteer_applications for select using (is_admin());
create policy requests_admin on requests for select using (is_admin());
create policy items_admin on request_items for select using (is_admin());
create policy lots_admin on inventory_lots for select using (is_admin());
create policy moves_admin on inventory_movements for select using (is_admin());
create policy resv_admin on inventory_reservations for select using (is_admin());
create policy events_admin on assignment_events for select using (is_admin());
create policy incidents_admin on incidents for select using (is_admin());
create policy audit_admin on audit_logs for select using (is_admin());
create policy vloc_admin on volunteer_locations for select using (is_admin());

create policy assignments_read on assignments for select using (volunteer_id = auth.uid() or is_admin());
create policy tokens_own on device_tokens for all using (profile_id = auth.uid()) with check (profile_id = auth.uid());

alter publication supabase_realtime add table incidents;