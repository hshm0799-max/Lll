-- OPTIONAL demo data. Run in the Supabase SQL editor AFTER you sign up once in the app.
-- Replace OWNER_USER_ID with your user id (Authentication > Users). businesses.created_by is required.
with b as (
  insert into public.businesses (name, business_type, description, country_code, city, address, timezone, status, created_by)
  values
    ('Demo Grand Aurum Delhi','hotel_restaurant','Luxury stay with a fine-dining restaurant.','IN','Delhi','Connaught Place','Asia/Kolkata','approved','OWNER_USER_ID'),
    ('Demo Lakeview Palace','hotel','Lake-facing rooms in Udaipur.','IN','Udaipur','Lake Pichola Road','Asia/Kolkata','approved','OWNER_USER_ID'),
    ('Demo Rooftop Grill','restaurant','Rooftop grill and live music.','US','New York','5th Avenue','America/New_York','approved','OWNER_USER_ID')
  returning id, name),
rt as (
  insert into public.room_types (business_id, name, capacity, price_per_night, currency)
  select id, 'Deluxe Room', 2, 4500, 'INR' from b where name = 'Demo Grand Aurum Delhi'
  union all select id, 'Royal Suite', 4, 12000, 'INR' from b where name = 'Demo Grand Aurum Delhi'
  union all select id, 'Lake View Room', 2, 6800, 'INR' from b where name = 'Demo Lakeview Palace'
  returning id, business_id),
r as (
  insert into public.rooms (business_id, room_type_id, room_number)
  select business_id, id, left(id::text, 4) || '-' || n from rt, generate_series(1, 3) as n
  returning id),
t as (
  insert into public.restaurant_tables (business_id, label, capacity)
  select id, 'T' || n, case when n % 2 = 0 then 4 else 2 end from b, generate_series(1, 4) as n where name in ('Demo Grand Aurum Delhi','Demo Rooftop Grill')
  returning id)
insert into public.offers (code, discount_type, discount_value, min_booking_amount, max_discount_amount)
values ('WELCOME20', 'percentage', 20, 0, 500);
