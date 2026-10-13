import express from 'express';
import cors from 'cors';
import crypto from 'crypto';
import { z } from 'zod';
import Razorpay from 'razorpay';
import Stripe from 'stripe';
import { createClient } from '@supabase/supabase-js';
import { sendMail } from './mailer.js';

const { SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY } = process.env;
const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });
// client acting AS the logged-in user (so auth.uid() + RLS work inside the DB functions)
const asUser = (token) => createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  auth: { persistSession: false }, global: { headers: { Authorization: `Bearer ${token}` } } });
const razor = process.env.RAZORPAY_KEY_ID ? new Razorpay({ key_id: process.env.RAZORPAY_KEY_ID, key_secret: process.env.RAZORPAY_KEY_SECRET }) : null;
const stripe = process.env.STRIPE_SECRET_KEY ? new Stripe(process.env.STRIPE_SECRET_KEY) : null;
const PAYMENTS_ON = process.env.PAYMENTS_ENABLED === 'true'; // false = bookings confirm without payment (temporary)
const minor = (n) => Math.round(Number(n) * 100); // numeric(12,2) -> paise/cents

const app = express();
app.use(cors({ origin: (process.env.ALLOWED_ORIGINS || '*').split(',') }));

// ---------- Webhooks (raw body, signature verified) ----------
async function once(provider, id) {
  const { error } = await admin.from('payment_webhook_events').insert({ id, provider });
  return !error; // duplicate id => already processed
}
async function settle(provider, providerOrderId) {
  const { data: po } = await admin.from('payment_orders').select('booking_id').eq('provider', provider).eq('provider_order_id', providerOrderId).maybeSingle();
  if (!po?.booking_id) return;
  const { data: ok } = await admin.rpc('finalize_paid_booking', { p_booking: po.booking_id, p_payment_ref: providerOrderId });
  if (!ok) return; // already finalized / expired
  await notify(po.booking_id);
}
async function notify(bookingId) {
  const { data: bk } = await admin.from('bookings').select('customer_id,total_amount,currency,status,businesses(name)').eq('id', bookingId).single();
  const { data: u } = await admin.auth.admin.getUserById(bk.customer_id);
  if (u?.user?.email) {
    const msg = bk.status === 'confirmed' ? 'Booking confirmed' : 'Booking received - awaiting property confirmation';
    sendMail(u.user.email, `${msg} - Grand Aurum`, `<h2>${msg}</h2><p>${bk.businesses.name}</p><p>Total: ${bk.total_amount} ${bk.currency}</p>`).catch(console.error);
  }
}
app.post('/webhooks/razorpay', express.raw({ type: '*/*' }), async (req, res) => {
  const sig = req.get('x-razorpay-signature') || '';
  const exp = crypto.createHmac('sha256', process.env.RAZORPAY_WEBHOOK_SECRET).update(req.body).digest('hex');
  if (sig.length !== exp.length || !crypto.timingSafeEqual(Buffer.from(sig), Buffer.from(exp))) return res.sendStatus(400);
  const ev = JSON.parse(req.body.toString());
  const id = req.get('x-razorpay-event-id') || crypto.createHash('sha1').update(req.body).digest('hex');
  if (!(await once('razorpay', id))) return res.sendStatus(200);
  if (ev.event === 'order.paid' || ev.event === 'payment.captured')
    await settle('razorpay', ev.payload.payment?.entity?.order_id ?? ev.payload.order?.entity?.id);
  res.sendStatus(200);
});
app.post('/webhooks/stripe', express.raw({ type: '*/*' }), async (req, res) => {
  let ev;
  try { ev = stripe.webhooks.constructEvent(req.body, req.get('stripe-signature'), process.env.STRIPE_WEBHOOK_SECRET); } catch { return res.sendStatus(400); }
  if (!(await once('stripe', ev.id))) return res.sendStatus(200);
  if (ev.type === 'payment_intent.succeeded') await settle('stripe', ev.data.object.id);
  res.sendStatus(200);
});

app.use(express.json());
app.get('/health', (_, r) => r.send('ok'));

const auth = async (req, res, next) => {
  const token = (req.get('authorization') || '').replace('Bearer ', '');
  const { data } = await admin.auth.getUser(token);
  if (!data?.user) return res.status(401).json({ error: 'unauthorized' });
  req.user = data.user; req.token = token; next();
};

// ---------- Booking: DB function calculates everything, API only creates the payment order ----------
const schema = z.object({
  business_id: z.string().uuid(), room_type_id: z.string().uuid().optional(), check_in: z.string().optional(),
  nights: z.number().int().min(1).max(30).optional(), table_id: z.string().uuid().optional(),
  slot_start: z.string().datetime().optional(), guests: z.number().int().min(1).max(50).default(2),
  offer_code: z.string().max(40).optional(), idempotency_key: z.string().max(80).optional() });

app.post('/bookings', auth, async (req, res) => {
  const p = schema.safeParse(req.body); if (!p.success) return res.status(400).json(p.error.flatten());
  const b = p.data;
  const { data: bk, error } = await asUser(req.token).rpc('create_booking', {
    p_business: b.business_id, p_room_type: b.room_type_id ?? null, p_check_in: b.check_in ?? null, p_nights: b.nights ?? null,
    p_table: b.table_id ?? null, p_slot_start: b.slot_start ?? null, p_guests: b.guests,
    p_offer_code: b.offer_code ?? null, p_idempotency_key: b.idempotency_key ?? null });
  if (error) return res.status(400).json({ error: error.message });

  if (!PAYMENTS_ON) { // temporary: no payment collected, booking is finalized directly
    if (bk.status === 'pending_payment') {
      await admin.rpc('finalize_paid_booking', { p_booking: bk.id, p_payment_ref: 'payments-disabled' });
      await notify(bk.id);
    }
    const { data: fresh } = await admin.from('bookings').select('*').eq('id', bk.id).single();
    return res.json({ booking: fresh, payment: null });
  }

  // retry-safe: reuse existing payment order for this booking
  const { data: existing } = await admin.from('payment_orders').select('*').eq('booking_id', bk.id).eq('status', 'created').maybeSingle();
  let provider, orderId, clientSecret;
  if (existing) { provider = existing.provider; orderId = existing.provider_order_id; }
  else if (bk.currency === 'INR') {
    const o = await razor.orders.create({ amount: minor(bk.total_amount), currency: 'INR', receipt: bk.id.slice(0, 40) });
    provider = 'razorpay'; orderId = o.id;
  } else {
    const pi = await stripe.paymentIntents.create({ amount: minor(bk.total_amount), currency: 'usd', metadata: { booking_id: bk.id } });
    provider = 'stripe'; orderId = pi.id; clientSecret = pi.client_secret;
  }
  if (!existing) await admin.from('payment_orders').insert({ booking_id: bk.id, provider, provider_order_id: orderId, amount: bk.total_amount, currency: bk.currency, status: 'created' });
  res.json({ booking: bk, payment: { provider, order_id: orderId, client_secret: clientSecret, razorpay_key: process.env.RAZORPAY_KEY_ID } });
});

app.post('/bookings/:id/cancel', auth, async (req, res) => {
  const { data, error } = await asUser(req.token).rpc('cancel_booking', { p_booking: req.params.id });
  if (error) return res.status(400).json({ error: error.message });
  res.json({ booking: data }); // refunds: handled manually / provider dashboard in v1
});

// ---------- Admin: approve business -> email owner ----------
app.post('/admin/businesses/:id/approve', auth, async (req, res) => {
  const { data: isAdmin } = await asUser(req.token).rpc('is_admin');
  if (!isAdmin) return res.sendStatus(403);
  const { data: biz } = await admin.from('businesses').update({ status: 'approved' }).eq('id', req.params.id).select('id,name').single();
  if (!biz) return res.sendStatus(404);
  const { data: owners } = await admin.from('business_members').select('user_id').eq('business_id', biz.id).eq('member_role', 'owner');
  for (const o of owners ?? []) {
    const { data: u } = await admin.auth.admin.getUserById(o.user_id);
    await admin.from('notifications').insert({ user_id: o.user_id, title: 'Business approved', body: `${biz.name} is now live.` });
    if (u?.user?.email) sendMail(u.user.email, 'Your business is approved', `<p>${biz.name} is now live on Grand Aurum.</p>`).catch(console.error);
  }
  res.json({ ok: true });
});

// ---------- Cron: release unpaid bookings ----------
app.post('/jobs/expire', async (req, res) => {
  if (req.get('x-job-secret') !== process.env.JOB_SECRET) return res.sendStatus(403);
  const { data } = await admin.rpc('expire_pending_bookings'); res.json({ expired: data });
});

app.listen(process.env.PORT || 3000);
