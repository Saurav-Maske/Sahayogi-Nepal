insert into districts (name, province, lat, lng)
values ('Kailali', 'Sudurpashchim', 28.6869, 80.5934)
on conflict (name) do update set province = excluded.province, lat = excluded.lat, lng = excluded.lng;

insert into app_settings (key, value) values
  ('district', '{
      "name": "Kailali",
      "center": {"lat": 28.6869, "lng": 80.5934},
      "bounds": {"south": 28.40, "west": 80.35, "north": 29.00, "east": 81.20},
      "default_zoom": 11
   }'::jsonb),
  ('central_inventory', '{"label": "central_inventory", "lat": 28.6930, "lng": 80.5980}'::jsonb)
on conflict (key) do update set value = excluded.value;