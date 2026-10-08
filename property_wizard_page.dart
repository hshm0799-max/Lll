import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';

class PropertyWizardPage extends StatefulWidget {
  const PropertyWizardPage({super.key});

  @override
  State<PropertyWizardPage> createState() => _PropertyWizardPageState();
}

class _PropertyWizardPageState extends State<PropertyWizardPage> {
  final _name = TextEditingController();
  final _city = TextEditingController();
  final _address = TextEditingController();
  final _gstin = TextEditingController();
  final _phone = TextEditingController();
  final _maps = TextEditingController();
  String _type = 'hotel';
  String _country = 'IN';
  bool _busy = false;

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty || _city.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add the business name and city')));
      return;
    }
    setState(() => _busy = true);
    try {
      await db.rpc('create_property', params: {
        'p_name': _name.text.trim(),
        'p_type': _type,
        'p_country': _country,
        'p_city': _city.text.trim(),
        'p_address': _address.text.trim(),
        'p_gstin': _gstin.text.trim().isEmpty ? null : _gstin.text.trim(),
        'p_phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        'p_maps': _maps.text.trim().isEmpty ? null : _maps.text.trim(),
      });
      if (mounted) Navigator.of(context).pop(true);
    } on PostgrestException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(TextEditingController c, String label, {String? hint, TextInputType? type}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(controller: c, keyboardType: type, decoration: InputDecoration(labelText: label, hintText: hint, border: const OutlineInputBorder())),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Register your property')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Step 1: basic details. After the admin approves, add rooms, tables and the menu in the Business tab.'),
          const SizedBox(height: 16),
          _field(_name, 'Business name'),
          DropdownButtonFormField<String>(
            value: _type,
            decoration: const InputDecoration(labelText: 'Type', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'hotel', child: Text('Hotel')),
              DropdownMenuItem(value: 'restaurant', child: Text('Restaurant')),
              DropdownMenuItem(value: 'hotel_restaurant', child: Text('Hotel + Restaurant')),
            ],
            onChanged: (v) => setState(() => _type = v ?? 'hotel'),
          ),
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
          const SizedBox(height: 12),
          _field(_city, 'City'),
          _field(_address, 'Address'),
          _field(_gstin, 'GSTIN / tax number (optional)'),
          _field(_phone, 'Contact phone', hint: '+91 98765 43210', type: TextInputType.phone),
          _field(_maps, 'Google Maps link (optional)'),
          FilledButton(onPressed: _busy ? null : _submit, child: Text(_busy ? 'Submitting...' : 'Submit for approval')),
        ],
      ),
    );
  }
}
