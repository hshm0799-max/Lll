import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import 'menu_order_page.dart';

class BusinessPage extends StatefulWidget {
  const BusinessPage({super.key, required this.business});
  final Map<String, dynamic> business;

  @override
  State<BusinessPage> createState() => _BusinessPageState();
}

class _BusinessPageState extends State<BusinessPage> {
  List<Map<String, dynamic>> _rooms = [];
  List<Map<String, dynamic>> _tables = [];
  bool _loading = true;
  bool _busy = false;
  String? _roomType;
  String? _table;
  DateTime? _checkIn;
  int _nights = 1;
  DateTime? _slot;
  final _offer = TextEditingController();

  String get _id => widget.business['id'] as String;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rooms = await db.from('room_types').select('id, name, capacity, price_per_night, currency').eq('business_id', _id).eq('is_active', true);
    final tables = await db.rpc('table_live_status', params: {'p_business': _id});
    if (!mounted) return;
    setState(() {
      _rooms = List<Map<String, dynamic>>.from(rooms);
      _tables = List<Map<String, dynamic>>.from(tables);
      _loading = false;
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(context: context, initialDate: now.add(const Duration(days: 1)), firstDate: now, lastDate: now.add(const Duration(days: 365)));
    if (d != null) setState(() => _checkIn = d);
  }

  Future<void> _pickSlot() async {
    final now = DateTime.now();
    final d = await showDatePicker(context: context, initialDate: now, firstDate: now, lastDate: now.add(const Duration(days: 90)));
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 20, minute: 0));
    if (t != null) setState(() => _slot = DateTime(d.year, d.month, d.day, t.hour, t.minute));
  }

  String _ymd(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _reserve() async {
    setState(() => _busy = true);
    try {
      // Price, offer and platform fee are all calculated on the server. The app only sends choices.
      final booking = await db.rpc('create_booking', params: {
        'p_business': _id,
        'p_room_type': _roomType,
        'p_check_in': _roomType != null && _checkIn != null ? _ymd(_checkIn!) : null,
        'p_nights': _roomType != null ? _nights : null,
        'p_table': _table,
        'p_slot_start': _table != null ? _slot?.toUtc().toIso8601String() : null,
        'p_offer_code': _offer.text.trim().isEmpty ? null : _offer.text.trim(),
        'p_idempotency_key': '${DateTime.now().microsecondsSinceEpoch}',
      });
      final b = Map<String, dynamic>.from(booking as Map);
      final cur = b['currency'] as String;
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Booking held for 30 minutes'),
          content: Text('Total ${money(cur, b['total_amount'] as num)}\n'
              'Offer discount ${money(cur, b['discount_amount'] as num)}, platform fee ${money(cur, b['platform_fee'] as num)}.\n\n'
              'It is confirmed only after your payment is verified.'),
          actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK'))],
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } on PostgrestException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.business;
    final hasChoice = _roomType != null || _table != null;
    final blocked = _busy || (_roomType != null && _checkIn == null) || (_table != null && _slot == null);
    return Scaffold(
      appBar: AppBar(title: Text(b['name'] as String)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('${b['city']}, ${b['country_code']}'),
                if (b['description'] != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(b['description'] as String)),
                if (_rooms.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text('Rooms', style: Theme.of(context).textTheme.titleLarge),
                  for (final r in _rooms)
                    RadioListTile<String>(
                      value: r['id'] as String,
                      groupValue: _roomType,
                      onChanged: (v) => setState(() => _roomType = v),
                      title: Text(r['name'] as String),
                      subtitle: Text('Sleeps ${r['capacity']} \u00b7 ${money(r['currency'] as String, r['price_per_night'] as num)}/night'),
                    ),
                  if (_roomType != null)
                    Row(
                      children: [
                        OutlinedButton.icon(onPressed: _pickDate, icon: const Icon(Icons.calendar_today), label: Text(_checkIn == null ? 'Check-in date' : _ymd(_checkIn!))),
                        const Spacer(),
                        IconButton(onPressed: _nights > 1 ? () => setState(() => _nights--) : null, icon: const Icon(Icons.remove)),
                        Text('$_nights night${_nights > 1 ? 's' : ''}'),
                        IconButton(onPressed: _nights < 30 ? () => setState(() => _nights++) : null, icon: const Icon(Icons.add)),
                      ],
                    ),
                ],
                if (_tables.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text('Tables', style: Theme.of(context).textTheme.titleLarge),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final t in _tables)
                        ChoiceChip(
                          label: Text('${t['label']} \u00b7 ${t['capacity'] ?? '-'} seats \u00b7 ${t['status']}'),
                          avatar: CircleAvatar(radius: 6, backgroundColor: t['status'] == 'available' ? Colors.green : (t['status'] == 'reserved' ? Colors.amber : Colors.red)),
                          selected: _table == t['id'],
                          onSelected: (s) => setState(() => _table = s ? t['id'] as String : null),
                        ),
                    ],
                  ),
                  if (_table != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: OutlinedButton.icon(
                        onPressed: _pickSlot,
                        icon: const Icon(Icons.schedule),
                        label: Text(_slot == null ? 'Choose date and time' : '${_ymd(_slot!)} ${_slot!.hour.toString().padLeft(2, '0')}:${_slot!.minute.toString().padLeft(2, '0')}'),
                      ),
                    ),
                ],
                if (_tables.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => MenuOrderPage(business: b, tables: _tables))),
                      icon: const Icon(Icons.restaurant_menu),
                      label: const Text('Order from the menu'),
                    ),
                  ),
                if (_rooms.isEmpty && _tables.isEmpty) const Padding(padding: EdgeInsets.only(top: 24), child: Text('This business has not added rooms or tables yet.')),
                if (hasChoice) ...[
                  const SizedBox(height: 20),
                  TextField(controller: _offer, decoration: const InputDecoration(labelText: 'Offer code (optional, one per booking)', hintText: 'WELCOME20', border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: blocked ? null : _reserve, child: Text(_busy ? 'Reserving...' : 'Reserve')),
                ],
              ],
            ),
    );
  }
}
