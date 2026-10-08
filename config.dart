import 'package:supabase_flutter/supabase_flutter.dart';

// Public values only. The publishable key is safe in the app; it is limited by Row Level Security.
// Never put the service_role / secret key or any payment secret in this app.
const supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: 'https://fmdokknyscrpeoerupao.supabase.co');
const supabaseKey = String.fromEnvironment('SUPABASE_KEY', defaultValue: 'sb_publishable_39QAt1E5JsZNCo2CdopXjw_UX7rCqqN');

SupabaseClient get db => Supabase.instance.client;

String money(String currency, num value) {
  final symbol = currency == 'USD' ? '\$' : '\u20b9';
  final text = value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(2);
  return '$symbol$text';
}

String statusLabel(String status) => status.replaceAll('_', ' ');
