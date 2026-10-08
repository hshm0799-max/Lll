# Grand Aurum - Flutter customer app (Android)

Backend: Supabase project `fmdokknyscrpeoerupao` (migrations already applied): Auth, Postgres + RLS, Realtime.

## APK banane ke 2 tareeke
1. GitHub Actions (Flutter install kiye bina): is folder ko GitHub repo me daalein -> Actions -> "Build Android APK" -> Run workflow -> artifact `grand-aurum-apk` download karein.
2. Local: `flutter create --platforms=android --org com.grandaurum --project-name grand_aurum .`
   phir `android/app/src/main/AndroidManifest.xml` me `<uses-permission android:name="android.permission.INTERNET"/>` jodein,
   phir `flutter pub get && flutter build apk --release`.

Keys override: `--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_KEY=...` (sirf publishable key, secret key kabhi nahi).

## Pehli baar
- Supabase Dashboard > Authentication: testing ke liye "Confirm email" band kar sakte hain.
- App me signup karein, phir `supabase/seed_demo.sql` (OWNER_USER_ID badalkar) chalayein to demo hotels dikhenge.
- Admin banane ke liye SQL editor me: `insert into public.user_roles (user_id, role) values ('<your id>', 'admin');`

## Roles aur staff (naya)
- Koi bhi user app me "Register your hotel or restaurant" se property bhej sakta hai (status pending). Admin approve karta hai
  (SQL editor me: `update public.businesses set status='approved' where id='<id>';` - sirf admin kar sakta hai).
- Staff add karna (abhi SQL se; app me invite screen baad me): 
  `insert into public.business_members (business_id, user_id, member_role, member_status, permissions) values ('<business>', '<staff user id>', 'staff', 'active', '{kitchen}');`
  Permissions: bookings, checkin, tables, kitchen, housekeeping. Chef ko sirf `{kitchen}` do - wo rates ya bookings nahi dekh sakta.
- Owner/manager ko sab permissions apne aap milti hain.
- Payment webhook se confirm hone par: auto-accept ON ho to booking seedha confirmed (voucher QR), OFF ho to owner Confirm karta hai.
