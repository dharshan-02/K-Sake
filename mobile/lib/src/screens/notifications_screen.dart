import 'package:flutter/material.dart';

import '../data/local_vault.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({
    super.key,
    required this.vault,
    this.isHiddenVault = false,
  });
  final LocalVault vault;
  final bool isHiddenVault;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map<String, Object?>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    widget.vault.unreadNotificationCount.addListener(_onUnreadChanged);
    widget.vault.notificationRevision.addListener(_onActivityChanged);
    _load();
  }

  @override
  void dispose() {
    widget.vault.unreadNotificationCount.removeListener(_onUnreadChanged);
    widget.vault.notificationRevision.removeListener(_onActivityChanged);
    super.dispose();
  }

  void _onUnreadChanged() => _load();
  void _onActivityChanged() => _load();

  Future<void> _load() async {
    final items = await widget.vault.listNotifications(
      isHidden: widget.isHiddenVault,
    );
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<void> _markAllRead() async {
    await widget.vault.markAllNotificationsRead(isHidden: widget.isHiddenVault);
    await _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Activity'),
      actions: [
        if (_items.any((item) => (item['is_read'] as int? ?? 0) == 0))
          TextButton(
            onPressed: _markAllRead,
            child: const Text('Mark all read'),
          ),
      ],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _items.isEmpty
        ? const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.notifications_none_outlined, size: 48),
                  SizedBox(height: 12),
                  Text('You’re all caught up.'),
                ],
              ),
            ),
          )
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final item = _items[index];
                final unread = (item['is_read'] as int? ?? 0) == 0;
                final timestamp = DateTime.tryParse(
                  item['created_at'] as String? ?? '',
                )?.toLocal();
                final icon = switch (item['type']) {
                  'upload' => Icons.cloud_done_outlined,
                  'download' => Icons.download_done_outlined,
                  'error' => Icons.warning_amber_outlined,
                  'trash' => Icons.delete_outline,
                  _ => Icons.notifications_none_outlined,
                };
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(child: Icon(icon)),
                    title: Text(
                      item['title'] as String,
                      style: TextStyle(
                        fontWeight: unread
                            ? FontWeight.w700
                            : FontWeight.normal,
                      ),
                    ),
                    subtitle: Text(
                      '${item['message'] as String}\n${timestamp == null ? '' : timestamp.toString().substring(0, 16)}',
                    ),
                    isThreeLine: true,
                    trailing: unread
                        ? Icon(
                            Icons.circle,
                            size: 10,
                            color: Theme.of(context).colorScheme.primary,
                          )
                        : null,
                    onTap: unread
                        ? () async {
                            await widget.vault.markNotificationRead(
                              item['id'] as String,
                              isHidden: widget.isHiddenVault,
                            );
                            await _load();
                          }
                        : null,
                  ),
                );
              },
            ),
          ),
  );
}
