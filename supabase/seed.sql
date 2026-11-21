-- FICTIONAL demo data only. Demo auth users: scripts/seed-demo-users.mjs
insert into inventory_lots (item_type, unit, source, provider_name, provider_contact, received_qty, available_qty, phase, condition) values
 ('rice','kg','donation','Demo Donor Co','+9779800000001',500,500,'ready_to_ship','good'),
 ('blankets','pcs','supplier_import','Demo Supplier','+9779800000002',200,200,'processing','new'),
 ('water','l','donation','Demo Donor Two','+9779800000003',1000,1000,'received','sealed');

insert into requests (kind, status, requester_name, requester_phone, district, location, urgency, notes) values
 ('resource_request','pending_admin_review','Demo Requester A','+9779800000010','Kavrepalanchok', st_setsrid(st_makepoint(85.55,27.62),4326)::geography,'high','Demo: food needed'),
 ('donation_offer','pending_admin_review','Demo Donor B','+9779800000011','Kathmandu', st_setsrid(st_makepoint(85.32,27.71),4326)::geography,'normal','Demo: donating blankets'),
 ('manpower_request','pending_admin_review','Demo Requester C','+9779800000012','Sindhupalchok', st_setsrid(st_makepoint(85.69,27.95),4326)::geography,'critical','Demo: 3 volunteers needed');

insert into request_items (request_id, item_type, qty, unit)
 select id,
   case kind when 'resource_request' then 'rice' when 'donation_offer' then 'blankets' else 'volunteers' end,
   case kind when 'resource_request' then 50 when 'donation_offer' then 40 else 3 end,
   case kind when 'resource_request' then 'kg' when 'donation_offer' then 'pcs' else 'people' end
 from requests;
