-- Settings every environment needs (local, demo, production). Lives in a migration so
-- `supabase db push` creates them on the hosted project too. ON CONFLICT DO NOTHING keeps
-- any value you later edit in Studio from being overwritten.

-- 'district': pilot-district map config. Public-readable (see settings_public_read policy).
-- Pilot = Kathmandu. Change by UPDATE in a new migration if the team picks another district.
insert into public.app_settings (key, value) values (
  'district',
  '{"name":"Kathmandu","center":{"lat":27.7172,"lng":85.3240},"bounds":{"south":27.62,"west":85.22,"north":27.82,"east":85.44},"zoom":11}'::jsonb
) on conflict (key) do nothing;

-- 'central_inventory': hub that driver routes (driver -> hub -> requester) start from.
-- NOT public: the policy only exposes key = 'district'; service_role / SECURITY DEFINER RPCs read it.
-- PLACEHOLDER coordinates: replace with the real hub location once confirmed.
insert into public.app_settings (key, value) values (
  'central_inventory',
  '{"name":"Central Inventory Hub","lat":27.7050,"lng":85.3200,"address_note":"Placeholder hub location"}'::jsonb
) on conflict (key) do nothing;