import 'package:flutter/material.dart';

import '../config.dart';
import 'business_page.dart';

class ExplorePage extends StatefulWidget {
  const ExplorePage({super.key});

  @override
  State<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends State<ExplorePage> {
  String _query = '';
  String _country = 'all';
  String _mode = 'stay';
  late Future<List<Map<String, dynamic>>> _future = _load();

  Future<List<Map<String, dynamic>>> _load() async {
    // RLS only returns approved businesses to customers.
    var q = db
        .from('businesses')
        .select('id, name, business_type, city, country_code, description, featured_until, room_types(price_per_night, currency)')
        .eq('status', 'approved')
        .inFilter('business_type', _mode == 'stay' ? ['hotel', 'hotel_restaurant'] : ['restaurant', 'hotel_restaurant']);
    if (_country != 'all') q = q.eq('country_code', _country);
    if (_query.isNotEmpty) q = q.ilike('name', '%$_query%');
    final rows = await q.order('featured_until', ascending: false, nullsFirst: false).order('name');
    return List<Map<String, dynamic>>.from(rows);
  }

  void _reload() => setState(() => _future = _load());

  String _typeLabel(String t) => t == 'hotel_restaurant' ? 'Hotel + Restaurant' : (t == 'hotel' ? 'Hotel' : 'Restaurant');

  bool _featured(Map<String, dynamic> b) {
    final f = b['featured_until'];
    return f != null && DateTime.parse(f as String).isAfter(DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'stay', label: Text('Book a Stay'), icon: Icon(Icons.hotel)),
              ButtonSegment(value: 'dine', label: Text('Dine Out & Order'), icon: Icon(Icons.restaurant)),
            ],
            selected: {_mode},
            onSelectionChanged: (s) {
              _mode = s.first;
              _reload();
            },
          ),
          const SizedBox(height: 12),
          TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search by name', border: OutlineInputBorder()),
            onSubmitted: (v) {
              _query = v.trim();
              _reload();
            },
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final c in const [['all', 'All'], ['IN', 'India'], ['US', 'America']])
                ChoiceChip(
                  label: Text(c[1]),
                  selected: _country == c[0],
                  onSelected: (_) {
                    _country = c[0];
                    _reload();
                  },
                ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
                if (snap.hasError) {
                  return Center(child: TextButton(onPressed: _reload, child: const Text('Could not load. Tap to retry')));
                }
                final rows = snap.data ?? [];
                if (rows.isEmpty) return const Center(child: Text('No approved listings yet.'));
                return RefreshIndicator(
                  onRefresh: () async => _reload(),
                  child: ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final b = rows[i];
                      final rooms = List<Map<String, dynamic>>.from(b['room_types'] ?? []);
                      String price = '';
                      if (_mode == 'stay' && rooms.isNotEmpty) {
                        rooms.sort((x, y) => (x['price_per_night'] as num).compareTo(y['price_per_night'] as num));
                        price = ' \u00b7 from ${money(rooms.first['currency'] as String, rooms.first['price_per_night'] as num)}/night';
                      }
                      return Card(
                        child: ListTile(
                          title: Text('${_featured(b) ? '\u2605 ' : ''}${b['name']}'),
                          subtitle: Text('${_typeLabel(b['business_type'] as String)} \u00b7 ${b['city']}, ${b['country_code']}$price'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => BusinessPage(business: b))),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
