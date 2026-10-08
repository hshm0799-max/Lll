import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

Future<void> _guard(BuildContext context, Future<void> Function() action) async {
  try {
    await action();
  } on PostgrestException catch (e) {
    if (context.mounted) _toast(context, e.message);
  }
}

class BusinessPanelPage extends StatefulWidget {
  const BusinessPanelPage({super.key});

  @override
  State<BusinessPanelPage> createState() => _BusinessPanelPageState();
}

class _BusinessPanelPageState extends State<BusinessPanelPage> {
  List<Map<String, dynamic>>? _memberships;
  int _selected = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await db
        .from('business_members')
        .select('member_role, permissions, businesses(id, name, status, auto_accept, country_code, business_type)')
        .eq('user_id', db.auth.currentUser!.id)
        .eq('member_status', 'active');
    if (mounted) setState(() => _memberships = List<Map<String, dynamic>>.from(rows));
  }

  @override
  Widget build(BuildContext context) {
    final memberships = _memberships;
    if (memberships == null) return const Center(child: CircularProgressIndicator());
    if (memberships.isEmpty) return const Center(child: Text('No business linked to your account.'));
    final m = memberships[_selected >= memberships.length ? 0 : _selected];
    final biz = Map<String, dynamic>.from(m['businesses'] as Map);
    final bizId = biz['id'] as String;
    final role = m['member_role'] as String;
    final perms = List<String>.from(m['permissions'] ?? []);
    final manager = role == 'owner' || role == 'manager';
    bool can(String p) => manager || perms.contains(p);
    final approved = biz['status'] == 'approved';
    final tabs = <MapEntry<String, Widget>>[
      if (can('bookings') || can('checkin')) MapEntry('Bookings', _BookingsTab(bizId: bizId)),
      if (can('bookings') || can('checkin')) MapEntry('Rooms', _RoomsTab(bizId: bizId)),
      if (can('tables')) MapEntry('Tables', _TablesTab(bizId: bizId)),
      if (can('kitchen')) MapEntry('Kitchen', _KitchenTab(bizId: bizId)),
      if (can('housekeeping')) MapEntry('Housekeeping', _HousekeepingTab(bizId: bizId)),
      if (manager) MapEntry('Setup', _SetupTab(bizId: bizId, country: biz['country_code'] as String)),
      if (manager) MapEntry('Settings', _SettingsTab(biz: biz, onChanged: _load)),
    ];
    return DefaultTabController(
      key: ValueKey('$bizId-${tabs.length}'),
      length: tabs.length,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Expanded(child: Text(biz['name'] as String, style: Theme.of(context).textTheme.titleLarge)),
                if (memberships.length > 1)
                  DropdownButton<int>(
                    value: _selected,
                    items: [for (var i = 0; i < memberships.length; i++) DropdownMenuItem(value: i, child: Text((memberships[i]['businesses'] as Map)['name'] as String))],
                    onChanged: (v) => setState(() => _selected = v ?? 0),
                  ),
              ],
            ),
          ),
          if (!approved)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Card(child: ListTile(leading: Icon(Icons.hourglass_top), title: Text('Waiting for admin approval'), subtitle: Text('Customers cannot see your property until it is approved.'))),
            ),
          TabBar(isScrollable: true, tabs: [for (final t in tabs) Tab(text: t.key)]),
          Expanded(child: TabBarView(children: [for (final t in tabs) t.value])),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- bookings
class _BookingsTab extends StatefulWidget {
  const _BookingsTab({required this.bizId});
  final String bizId;

  @override
  State<_BookingsTab> createState() => _BookingsTabState();
}

class _BookingsTabState extends State<_BookingsTab> {
  List<Map<String, dynamic>>? _rows;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _load();
    _channel = db.channel('biz-bookings-${widget.bizId}').onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'bookings', callback: (_) => _load()).subscribe();
  }

  @override
  void dispose() {
    if (_channel != null) db.removeChannel(_channel!);
    super.dispose();
  }

  Future<void> _load() async {
    final rows = await db.from('bookings').select('*').eq('business_id', widget.bizId).order('created_at', ascending: false);
    if (mounted) setState(() => _rows = List<Map<String, dynamic>>.from(rows));
  }

  Future<void> _move(String id, String to) => _guard(context, () async {
        await db.rpc('staff_set_booking_status', params: {'p_booking': id, 'p_to': to});
        await _load();
      });

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    if (rows == null) return const Center(child: CircularProgressIndicator());
    if (rows.isEmpty) return const Center(child: Text('No bookings yet.'));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final b in rows)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(child: Text('#${(b['id'] as String).substring(0, 8)} \u00b7 ${b['kind']}')),
                    Chip(label: Text(statusLabel(b['status'] as String))),
                  ]),
                  Text('${b['stay'] ?? b['slot'] ?? ''}'),
                  Text('Total ${money(b['currency'] as String, b['total_amount'] as num)}'),
                  if (b['voucher_code'] != null) Text('Voucher ${b['voucher_code']}'),
                  Wrap(spacing: 8, children: [
                    if (b['status'] == 'paid') FilledButton(onPressed: () => _move(b['id'] as String, 'confirmed'), child: const Text('Confirm')),
                    if (b['status'] == 'paid') OutlinedButton(onPressed: () => _move(b['id'] as String, 'rejected'), child: const Text('Reject')),
                    if (b['status'] == 'confirmed') FilledButton(onPressed: () => _move(b['id'] as String, 'completed'), child: const Text('Check-out')),
                  ]),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------- room matrix
class _RoomsTab extends StatefulWidget {
  const _RoomsTab({required this.bizId});
  final String bizId;

  @override
  State<_RoomsTab> createState() => _RoomsTabState();
}

class _RoomsTabState extends State<_RoomsTab> {
  List<Map<String, dynamic>>? _rooms;
  List<Map<String, dynamic>> _bookings = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rooms = await db.from('rooms').select('id, room_number, room_types(name)').eq('business_id', widget.bizId).order('room_number');
    final bookings = await db.from('bookings').select('room_id, status, stay').eq('business_id', widget.bizId).not('room_id', 'is', null).inFilter('status', ['pending_payment', 'paid', 'confirmed']);
    if (!mounted) return;
    setState(() {
      _rooms = List<Map<String, dynamic>>.from(rooms);
      _bookings = List<Map<String, dynamic>>.from(bookings);
    });
  }

  // stay is a Postgres daterange like "[2026-10-20,2026-10-22)".
  bool _coversToday(String stay) {
    final parts = stay.substring(1, stay.length - 1).split(',');
    final from = DateTime.parse(parts[0]);
    final to = DateTime.parse(parts[1]);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return !today.isBefore(from) && today.isBefore(to);
  }

  @override
  Widget build(BuildContext context) {
    final rooms = _rooms;
    if (rooms == null) return const Center(child: CircularProgressIndicator());
    if (rooms.isEmpty) return const Center(child: Text('Add rooms in the Setup tab.'));
    return RefreshIndicator(
      onRefresh: _load,
      child: GridView.count(
        padding: const EdgeInsets.all(16),
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        children: [
          for (final r in rooms)
            Builder(builder: (context) {
              final mine = _bookings.where((b) => b['room_id'] == r['id']);
              final today = mine.where((b) => _coversToday(b['stay'] as String));
              final color = today.any((b) => b['status'] == 'confirmed')
                  ? Colors.red
                  : (mine.isNotEmpty ? Colors.amber : Colors.green);
              return Container(
                decoration: BoxDecoration(color: color.withValues(alpha: 0.25), border: Border.all(color: color), borderRadius: BorderRadius.circular(10)),
                child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Text('${r['room_number']}', style: const TextStyle(fontWeight: FontWeight.bold)), Text((r['room_types']?['name'] ?? '') as String, style: const TextStyle(fontSize: 11))])),
              );
            }),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- live tables
class _TablesTab extends StatefulWidget {
  const _TablesTab({required this.bizId});
  final String bizId;

  @override
  State<_TablesTab> createState() => _TablesTabState();
}

class _TablesTabState extends State<_TablesTab> {
  List<Map<String, dynamic>>? _tables;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _load();
    _channel = db.channel('biz-tables-${widget.bizId}').onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'restaurant_tables', callback: (_) => _load()).subscribe();
  }

  @override
  void dispose() {
    if (_channel != null) db.removeChannel(_channel!);
    super.dispose();
  }

  Future<void> _load() async {
    final rows = await db.rpc('table_live_status', params: {'p_business': widget.bizId});
    if (mounted) setState(() => _tables = List<Map<String, dynamic>>.from(rows as List));
  }

  Future<void> _toggle(Map<String, dynamic> t) => _guard(context, () async {
        final next = t['status'] == 'occupied' ? 'available' : 'occupied';
        await db.rpc('staff_set_table_status', params: {'p_table': t['id'], 'p_status': next});
        await _load();
      });

  @override
  Widget build(BuildContext context) {
    final tables = _tables;
    if (tables == null) return const Center(child: CircularProgressIndicator());
    if (tables.isEmpty) return const Center(child: Text('Add tables in the Setup tab.'));
    return GridView.count(
      padding: const EdgeInsets.all(16),
      crossAxisCount: 3,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      children: [
        for (final t in tables)
          InkWell(
            onTap: () => _toggle(t),
            child: Builder(builder: (context) {
              final color = t['status'] == 'available' ? Colors.green : (t['status'] == 'reserved' ? Colors.amber : Colors.red);
              return Container(
                decoration: BoxDecoration(color: color.withValues(alpha: 0.25), border: Border.all(color: color), borderRadius: BorderRadius.circular(10)),
                child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Text('${t['label']}', style: const TextStyle(fontWeight: FontWeight.bold)), Text('${t['status']}', style: const TextStyle(fontSize: 11))])),
              );
            }),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------- kitchen (KDS)
class _KitchenTab extends StatelessWidget {
  const _KitchenTab({required this.bizId});
  final String bizId;

  static const _next = {'new': 'preparing', 'preparing': 'ready', 'ready': 'served'};
  static const _label = {'new': 'Start preparing', 'preparing': 'Mark ready', 'ready': 'Mark served'};

  @override
  Widget build(BuildContext context) {
    final stream = db.from('orders').stream(primaryKey: ['id']).eq('business_id', bizId).order('created_at');
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.hasError) return const Center(child: Text('Could not load orders.'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final orders = snap.data!.where((o) => o['status'] != 'served' && o['status'] != 'cancelled').toList();
        if (orders.isEmpty) return const Center(child: Text('No active orders.'));
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final o in orders)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [Expanded(child: Text('Order #${(o['id'] as String).substring(0, 8)}')), Chip(label: Text('${o['status']}'))]),
                      FutureBuilder<List<dynamic>>(
                        future: db.from('order_items').select('name, quantity').eq('order_id', o['id']),
                        builder: (context, items) {
                          if (!items.hasData) return const Text('...');
                          return Text(items.data!.map((i) => '${i['quantity']} x ${i['name']}').join('\n'));
                        },
                      ),
                      const SizedBox(height: 8),
                      Wrap(spacing: 8, children: [
                        if (_next[o['status']] != null)
                          FilledButton(
                            onPressed: () => _guard(context, () async {
                              await db.rpc('set_order_status', params: {'p_order': o['id'], 'p_to': _next[o['status']]});
                            }),
                            child: Text(_label[o['status']]!),
                          ),
                        if (o['status'] == 'new' || o['status'] == 'preparing')
                          OutlinedButton(onPressed: () => _guard(context, () async => db.rpc('set_order_status', params: {'p_order': o['id'], 'p_to': 'cancelled'})), child: const Text('Cancel')),
                      ]),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------- housekeeping
class _HousekeepingTab extends StatefulWidget {
  const _HousekeepingTab({required this.bizId});
  final String bizId;

  @override
  State<_HousekeepingTab> createState() => _HousekeepingTabState();
}

class _HousekeepingTabState extends State<_HousekeepingTab> {
  List<Map<String, dynamic>>? _tasks;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _load();
    _channel = db.channel('biz-hk-${widget.bizId}').onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'housekeeping_tasks', callback: (_) => _load()).subscribe();
  }

  @override
  void dispose() {
    if (_channel != null) db.removeChannel(_channel!);
    super.dispose();
  }

  Future<void> _load() async {
    final rows = await db.from('housekeeping_tasks').select('id, kind, status, rooms(room_number)').eq('business_id', widget.bizId).neq('status', 'done').order('created_at');
    if (mounted) setState(() => _tasks = List<Map<String, dynamic>>.from(rows));
  }

  Future<void> _advance(Map<String, dynamic> t) => _guard(context, () async {
        final done = t['status'] == 'in_progress';
        await db.from('housekeeping_tasks').update({'status': done ? 'done' : 'in_progress', if (done) 'done_at': DateTime.now().toUtc().toIso8601String()}).eq('id', t['id']);
        await _load();
      });

  @override
  Widget build(BuildContext context) {
    final tasks = _tasks;
    if (tasks == null) return const Center(child: CircularProgressIndicator());
    if (tasks.isEmpty) return const Center(child: Text('No open housekeeping tasks.'));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final t in tasks)
          Card(
            child: ListTile(
              leading: Icon(t['kind'] == 'clean' ? Icons.cleaning_services : Icons.bed),
              title: Text('Room ${t['rooms']?['room_number'] ?? '-'} \u00b7 ${t['kind'] == 'clean' ? 'Clean after check-out' : 'Prepare for guest'}'),
              subtitle: Text('${t['status']}'),
              trailing: FilledButton(onPressed: () => _advance(t), child: Text(t['status'] == 'in_progress' ? 'Done' : 'Start')),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------- setup (configurator)
class _SetupTab extends StatefulWidget {
  const _SetupTab({required this.bizId, required this.country});
  final String bizId;
  final String country;

  @override
  State<_SetupTab> createState() => _SetupTabState();
}

class _SetupTabState extends State<_SetupTab> {
  final _roomName = TextEditingController();
  final _roomPrice = TextEditingController();
  final _roomCount = TextEditingController(text: '1');
  final _roomPrefix = TextEditingController(text: '10');
  final _tableLabel = TextEditingController();
  final _tableSeats = TextEditingController(text: '4');
  final _dishName = TextEditingController();
  final _dishPrice = TextEditingController();

  String get _currency => widget.country == 'US' ? 'USD' : 'INR';

  Widget _input(TextEditingController c, String label, {bool number = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(controller: c, keyboardType: number ? TextInputType.number : null, decoration: InputDecoration(labelText: label, border: const OutlineInputBorder())),
      );

  Future<void> _addRoomType() => _guard(context, () async {
        final price = num.tryParse(_roomPrice.text.trim());
        final count = int.tryParse(_roomCount.text.trim()) ?? 0;
        if (_roomName.text.trim().isEmpty || price == null || count < 1) {
          _toast(context, 'Add a name, a price and the number of rooms');
          return;
        }
        final rt = await db.from('room_types').insert({'business_id': widget.bizId, 'name': _roomName.text.trim(), 'price_per_night': price, 'currency': _currency}).select('id').single();
        await db.from('rooms').insert([
          for (var i = 1; i <= count; i++) {'business_id': widget.bizId, 'room_type_id': rt['id'], 'room_number': '${_roomPrefix.text.trim()}$i'},
        ]);
        if (mounted) _toast(context, 'Added $count room(s)');
      });

  Future<void> _addTable() => _guard(context, () async {
        if (_tableLabel.text.trim().isEmpty) {
          _toast(context, 'Add a table name');
          return;
        }
        await db.from('restaurant_tables').insert({'business_id': widget.bizId, 'label': _tableLabel.text.trim(), 'capacity': int.tryParse(_tableSeats.text.trim()) ?? 2});
        if (mounted) _toast(context, 'Table added');
      });

  Future<void> _addDish() => _guard(context, () async {
        final price = num.tryParse(_dishPrice.text.trim());
        if (_dishName.text.trim().isEmpty || price == null) {
          _toast(context, 'Add a dish name and a price');
          return;
        }
        final existing = await db.from('menu_categories').select('id').eq('business_id', widget.bizId).eq('name', 'Menu').maybeSingle();
        final categoryId = existing?['id'] ?? (await db.from('menu_categories').insert({'business_id': widget.bizId, 'name': 'Menu'}).select('id').single())['id'];
        await db.from('menu_items').insert({'business_id': widget.bizId, 'category_id': categoryId, 'name': _dishName.text.trim(), 'price': price, 'currency': _currency});
        if (mounted) _toast(context, 'Dish added');
      });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Add rooms ($_currency)', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _input(_roomName, 'Room type, for example Deluxe'),
          _input(_roomPrice, 'Price per night', number: true),
          _input(_roomCount, 'How many rooms of this type', number: true),
          _input(_roomPrefix, 'Room number prefix, for example 10 gives 101, 102'),
          FilledButton(onPressed: _addRoomType, child: const Text('Add rooms')),
        ]))),
        Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Add a table', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _input(_tableLabel, 'Table name, for example Table 1'),
          _input(_tableSeats, 'Seats', number: true),
          FilledButton(onPressed: _addTable, child: const Text('Add table')),
        ]))),
        Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Add a menu item ($_currency)', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _input(_dishName, 'Dish name'),
          _input(_dishPrice, 'Price', number: true),
          FilledButton(onPressed: _addDish, child: const Text('Add dish')),
        ]))),
      ],
    );
  }
}

// ---------------------------------------------------------------- settings
class _SettingsTab extends StatefulWidget {
  const _SettingsTab({required this.biz, required this.onChanged});
  final Map<String, dynamic> biz;
  final Future<void> Function() onChanged;

  @override
  State<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<_SettingsTab> {
  late bool _auto = widget.biz['auto_accept'] == true;

  Future<void> _set(bool v) => _guard(context, () async {
        await db.from('businesses').update({'auto_accept': v}).eq('id', widget.biz['id']);
        setState(() => _auto = v);
        await widget.onChanged();
      });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SwitchListTile(
          value: _auto,
          onChanged: _set,
          title: const Text('Auto-accept paid bookings'),
          subtitle: const Text('Off means you review and confirm each paid booking yourself.'),
        ),
      ],
    );
  }
}
