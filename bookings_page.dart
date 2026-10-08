import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';

class BookingsPage extends StatefulWidget {
  const BookingsPage({super.key});

  @override
  State<BookingsPage> createState() => _BookingsPageState();
}

class _BookingsPageState extends State<BookingsPage> {
  List<Map<String, dynamic>>? _rows;
  Object? _error;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _load();
    // Live updates: when the payment webhook confirms a booking, this list refreshes itself.
    _channel = db
        .channel('my-bookings')
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'bookings', callback: (_) => _load())
        .subscribe();
  }

  @override
  void dispose() {
    if (_channel != null) db.removeChannel(_channel!);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final rows = await db.from('bookings').select('*, businesses(name)').eq('customer_id', db.auth.currentUser!.id).order('created_at', ascending: false);
      if (!mounted) return;
      setState(() {
        _rows = List<Map<String, dynamic>>.from(rows);
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _cancel(String id) async {
    try {
      await db.rpc('cancel_booking', params: {'p_booking': id});
      await _load();
    } on PostgrestException catch (e) {
      if (mounted) _toast(e.message);
    }
  }

  Future<void> _review(Map<String, dynamic> b) async {
    int rating = 5;
    final comment = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Rate your stay'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 1; i <= 5; i++)
                    IconButton(onPressed: () => setLocal(() => rating = i), icon: Icon(i <= rating ? Icons.star : Icons.star_border, color: const Color(0xFFD4AF37))),
                ],
              ),
              TextField(controller: comment, decoration: const InputDecoration(hintText: 'Tell others about your experience', border: OutlineInputBorder())),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Submit')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await db.from('reviews').insert({
        'booking_id': b['id'],
        'business_id': b['business_id'],
        'customer_id': db.auth.currentUser!.id,
        'rating': rating,
        'comment': comment.text.trim().isEmpty ? null : comment.text.trim(),
      });
      if (mounted) _toast('Thanks for your review');
    } on PostgrestException catch (e) {
      if (mounted) _toast(e.message);
    }
  }

  Color _color(String s) {
    switch (s) {
      case 'confirmed':
      case 'completed':
        return Colors.green;
      case 'pending_payment':
        return Colors.orange;
      case 'rejected':
      case 'cancelled':
      case 'refunded':
        return Colors.grey;
      default:
        return Colors.blue;
    }
  }

  Widget _line(String l, String v, {bool bold = false}) {
    final style = bold ? const TextStyle(fontWeight: FontWeight.bold) : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(l, style: style), Text(v, style: style)]),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return Center(child: TextButton(onPressed: _load, child: const Text('Could not load. Tap to retry')));
    final rows = _rows;
    if (rows == null) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('My bookings', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 12),
          if (rows.isEmpty) const Padding(padding: EdgeInsets.only(top: 40), child: Center(child: Text('No bookings yet. Find a place in Explore.'))),
          for (final b in rows)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text((b['businesses']?['name'] ?? 'Booking') as String, style: Theme.of(context).textTheme.titleMedium)),
                        Chip(label: Text(statusLabel(b['status'] as String)), backgroundColor: _color(b['status'] as String).withValues(alpha: 0.25)),
                      ],
                    ),
                    Text('${b['kind']} \u00b7 ${b['stay'] ?? ''}'.trim()),
                    const Divider(),
                    _line('Booking amount', money(b['currency'] as String, b['booking_amount'] as num)),
                    _line('Offer discount', '-${money(b['currency'] as String, b['discount_amount'] as num)}'),
                    _line('Platform fee', money(b['currency'] as String, b['platform_fee'] as num)),
                    _line('Total', money(b['currency'] as String, b['total_amount'] as num), bold: true),
                    if (b['voucher_code'] != null && b['status'] == 'confirmed')
                      Center(
                        child: Column(
                          children: [
                            const SizedBox(height: 8),
                            Container(color: Colors.white, padding: const EdgeInsets.all(8), child: QrImageView(data: 'GA:${b['voucher_code']}', size: 140)),
                            Text('Voucher ${b['voucher_code']}'),
                          ],
                        ),
                      ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        if (b['status'] == 'pending_payment')
                          FilledButton(onPressed: () => _toast('Payment opens once Razorpay/Stripe are connected.'), child: const Text('Pay now')),
                        if (['pending_payment', 'paid', 'confirmed'].contains(b['status'])) OutlinedButton(onPressed: () => _cancel(b['id'] as String), child: const Text('Cancel')),
                        if (b['status'] == 'completed') OutlinedButton(onPressed: () => _review(b), child: const Text('Review')),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
