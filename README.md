# Grand Aurum - Render API
Database pehle se Supabase me bana hua hai (create_booking, finalize_paid_booking, cancel_booking, expire_pending_bookings). Koi migration run nahi karni.
1. GitHub par push -> Render > New > Blueprint (render.yaml). Env vars bharein (SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY, Gmail, Razorpay, Stripe).
2. Gmail API: Google Cloud > Gmail API enable > OAuth client > refresh token (scope gmail.send). GMAIL_SENDER = aapka Gmail.
3. Payments abhi band hain (PAYMENTS_ENABLED=false): booking seedhe confirm hoti hai. Payment chalu karne ke liye PAYMENTS_ENABLED=true karein.
4. Webhooks: Razorpay -> https://<render-url>/webhooks/razorpay (order.paid, payment.captured); Stripe -> /webhooks/stripe (payment_intent.succeeded).
5. Cron job expire-pending-bookings me API_URL aur JOB_SECRET (web service wala) daalein.
Secrets kabhi chat/GitHub me paste na karein.
