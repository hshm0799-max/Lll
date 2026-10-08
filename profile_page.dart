import 'package:flutter/material.dart';

import '../config.dart';
import 'property_wizard_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, this.onBusinessCreated});
  final VoidCallback? onBusinessCreated;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  String _country = 'IN';
  int _points = 0;
  bool _loaded = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final row = await db.from('profiles').select('full_name, phone, country_code').eq('id', db.auth.currentUser!.id).maybeSingle();
    final pts = await db.rpc('loyalty_balance');
    if (!mounted) return;
    setState(() {
      _name.text = (row?['full_name'] ?? '') as String;
      _phone.text = (row?['phone'] ?? '') as String;
      _country = (row?['country_code'] ?? 'IN') as String;
      _points = (pts as num?)?.toInt() ?? 0;
      _loaded = true;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await db.from('profiles').update({
        'full_name': _name.text.trim(),
        'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        'country_code': _country,
        'preferred_currency': _country == 'US' ? 'USD' : 'INR',
      }).eq('id', db.auth.currentUser!.id);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile saved')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _registerProperty() async {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const PropertyWizardPage()));
    if (ok == true) {
      widget.onBusinessCreated?.call();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Submitted. An admin will review your property.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Profile', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 4),
        Text(db.auth.currentUser?.email ?? ''),
        const SizedBox(height: 12),
        Card(child: ListTile(leading: const Icon(Icons.stars, color: Color(0xFFD4AF37)), title: Text('$_points loyalty points'), subtitle: const Text('You earn 10 points on every paid booking.'))),
        const SizedBox(height: 12),
        TextField(controller: _name, decoration: const InputDecoration(labelText: 'Full name', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone', hintText: '+91 98765 43210', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _country,
          decoration: const InputDecoration(labelText: 'Country', border: OutlineInputBorder()),
          items: const [
            DropdownMenuItem(value: 'IN', child: Text('India (INR)')),
            DropdownMenuItem(value: 'US', child: Text('America (USD)')),
          ],
          onChanged: (v) => setState(() => _country = v ?? 'IN'),
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving...' : 'Save')),
        const SizedBox(height: 8),
        OutlinedButton.icon(onPressed: _registerProperty, icon: const Icon(Icons.add_business), label: const Text('Register your hotel or restaurant')),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: () => db.auth.signOut(), child: const Text('Sign out')),
      ],
    );
  }
}
