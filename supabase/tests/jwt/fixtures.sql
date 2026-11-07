-- SYNTHETIC fixtures for JWT tests. UUIDs are in the reserved 0000...0e?? range; emails use the reserved .invalid TLD. No real person or company.
insert into auth.users(id,email,email_confirmed_at) values
 ('00000000-0000-0000-0000-00000000e001','buyer1@jwt-test.invalid',now()),
 ('00000000-0000-0000-0000-00000000e002','buyer2@jwt-test.invalid',now()),
 ('00000000-0000-0000-0000-00000000e0a1','admin1@jwt-test.invalid',now()),
 ('00000000-0000-0000-0000-00000000e0b1','reviewer1@jwt-test.invalid',now()),
 ('00000000-0000-0000-0000-00000000e0b2','reviewer2@jwt-test.invalid',now());
-- auth.users insert fires the profile-creation trigger; then set roles/phones as the table owner with user triggers off (fixture setup only).
alter table public.profiles disable trigger user;
update public.profiles p set full_name=v.n, phone=v.ph, app_role=v.r::app_role from (values
 ('00000000-0000-0000-0000-00000000e001'::uuid,'JWT Buyer One','+000-SYNTH-0001','buyer'),
 ('00000000-0000-0000-0000-00000000e002','JWT Buyer Two','+000-SYNTH-0002','buyer'),
 ('00000000-0000-0000-0000-00000000e0a1','JWT Admin','+000-SYNTH-0003','admin'),
 ('00000000-0000-0000-0000-00000000e0b1','JWT Reviewer','+000-SYNTH-0004','reviewer'),
 ('00000000-0000-0000-0000-00000000e0b2','JWT Reviewer Two','+000-SYNTH-0005','reviewer')) v(i,n,ph,r) where p.id=v.i;
alter table public.profiles enable trigger user;
