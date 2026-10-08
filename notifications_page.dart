import 'package:flutter/material.dart';

import '../config.dart';

class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = db.auth.currentUser!.id;
    // Realtime stream: new notifications appear without refreshing.
    final stream = db.from('notifications').stream(primaryKey: ['id']).eq('user_id', uid).order('created_at', ascending: false);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Alerts', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 12),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: stream,
              builder: (context, snap) {
                if (snap.hasError) return const Center(child: Text('Could not load alerts.'));
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final rows = snap.data!;
                if (rows.isEmpty) return const Center(child: Text('No alerts yet.'));
                return ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final n = rows[i];
                    final unread = n['read'] == false;
                    return Card(
                      child: ListTile(
                        leading: Icon(unread ? Icons.notifications_active : Icons.notifications_none),
                        title: Text(n['title'] as String, style: TextStyle(fontWeight: unread ? FontWeight.bold : FontWeight.normal)),
                        subtitle: Text((n['body'] ?? '') as String),
                        onTap: unread ? () => db.from('notifications').update({'read': true}).eq('id', n['id']) : null,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
