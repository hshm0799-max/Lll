import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';

class MenuOrderPage extends StatefulWidget {
  const MenuOrderPage({super.key, required this.business, required this.tables});
  final Map<String, dynamic> business;
  final List<Map<String, dynamic>> tables;

  @override
  State<MenuOrderPage> createState() => _MenuOrderPageState();
}

class _MenuOrderPageState extends State<MenuOrderPage> {
  List<Map<String, dynamic>>? _items;
  final Map<String, int> _qty = {};
  String? _table;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await db.from('menu_items').select('id, name, description, price, currency').eq('business_id', widget.business['id']).eq('is_available', true).order('display_order');
    if (mounted) setState(() => _items = List<Map<String, dynamic>>.from(rows));
  }

  num get _total {
    num t = 0;
    for (final i in _items ?? <Map<String, dynamic>>[]) {
      t += (i['price'] as num) * (_qty[i['id']] ?? 0);
    }
    return t;
  }

  Future<void> _place() async {
    setState(() => _busy = true);
    try {
      final items = [
        for (final e in _qty.entries.where((e) => e.value > 0)) {'id': e.key, 'qty': e.value},
      ];
      // The server prices every item from the menu table. The app never sends prices.
      await db.rpc('place_order', params: {'p_business': widget.business['id'], 'p_table': _table, 'p_items': items});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Order sent to the kitchen')));
      Navigator.of(context).pop();
    } on PostgrestException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final cur = items != null && items.isNotEmpty ? items.first['currency'] as String : 'INR';
    return Scaffold(
      appBar: AppBar(title: Text('Menu \u00b7 ${widget.business['name']}')),
      body: items == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text('Your table'),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final t in widget.tables)
                      ChoiceChip(label: Text('${t['label']}'), selected: _table == t['id'], onSelected: (s) => setState(() => _table = s ? t['id'] as String : null)),
                  ],
                ),
                const SizedBox(height: 12),
                if (items.isEmpty) const Text('The menu is empty.'),
                for (final i in items)
                  Card(
                    child: ListTile(
                      title: Text(i['name'] as String),
                      subtitle: Text(money(i['currency'] as String, i['price'] as num)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(onPressed: (_qty[i['id']] ?? 0) > 0 ? () => setState(() => _qty[i['id'] as String] = _qty[i['id']]! - 1) : null, icon: const Icon(Icons.remove)),
                          Text('${_qty[i['id']] ?? 0}'),
                          IconButton(onPressed: () => setState(() => _qty[i['id'] as String] = (_qty[i['id']] ?? 0) + 1), icon: const Icon(Icons.add)),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                FilledButton(onPressed: _busy || _total == 0 ? null : _place, child: Text(_busy ? 'Sending...' : 'Place order \u00b7 ${money(cur, _total)}')),
              ],
            ),
    );
  }
}
