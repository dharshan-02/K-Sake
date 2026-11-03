import 'package:flutter/material.dart';

import '../data/local_vault.dart';
import '../data/firebase_sync_service.dart';
import 'vault_screen.dart';
import 'gallery_screen.dart';
import 'notes_screen.dart';
import 'passwords_screen.dart';
import 'more_screen.dart';
import 'settings_screen.dart';
import 'notifications_screen.dart';
import 'recycle_bin_screen.dart';
import '../widgets/keepsake_logo.dart';

class MainDashboard extends StatefulWidget {
  const MainDashboard({
    super.key,
    required this.vault,
    required this.isHiddenVault,
    required this.onLock,
  });

  final LocalVault vault;
  final bool isHiddenVault;
  final VoidCallback onLock;

  @override
  State<MainDashboard> createState() => _MainDashboardState();
}

class _MainDashboardState extends State<MainDashboard> {
  int _currentIndex = 0;
  late bool _hiddenMode;

  @override
  void initState() {
    super.initState();
    _hiddenMode = widget.isHiddenVault;
    widget.vault.refreshUnreadNotificationCount(isHidden: widget.isHiddenVault);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      VaultScreen(vault: widget.vault, isHiddenVault: _hiddenMode),
      GalleryScreen(vault: widget.vault, isHiddenVault: _hiddenMode),
      MoreScreen(
        onNotes: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                NotesScreen(vault: widget.vault, isHiddenVault: _hiddenMode),
          ),
        ),
        onPasswords: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => PasswordsScreen(
              vault: widget.vault,
              isHiddenVault: _hiddenMode,
            ),
          ),
        ),
        onRecycleBin: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => RecycleBinScreen(
              vault: widget.vault,
              isHiddenVault: _hiddenMode,
            ),
          ),
        ),
      ),
      SettingsScreen(
        vault: widget.vault,
        onLockNow: widget.onLock,
        isHiddenVault: _hiddenMode,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            if (!_hiddenMode) const KeepsakeLogo(size: 32),
            if (_hiddenMode) ...[
              const Icon(Icons.shield_moon, color: Colors.amber, size: 24),
              const SizedBox(width: 8),
            ],
            Text(
              _hiddenMode ? 'Hidden Safe' : 'Keepsake',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                letterSpacing: -0.3,
                color: _hiddenMode ? Colors.amber : null,
              ),
            ),
          ],
        ),
        actions: [
          if (!_hiddenMode)
            IconButton(
              icon: const Icon(Icons.sync_rounded),
              tooltip: 'Sync Vault',
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Syncing encrypted vault...'),
                    duration: Duration(seconds: 1),
                  ),
                );
                try {
                  final summary = await FirebaseSyncService(widget.vault)
                      .syncAll(downloadMissing: true);
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        summary.uploaded == 0 && summary.downloaded == 0
                            ? 'Vault is up to date (${summary.totalCloud} cloud files).'
                            : 'Synced: ${summary.uploaded} uploaded, ${summary.downloaded} downloaded.',
                      ),
                    ),
                  );
                } catch (_) {
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Cloud sync check completed. Encrypted files are safe.',
                      ),
                    ),
                  );
                }
              },
            ),
          ValueListenableBuilder<int>(
            valueListenable: widget.vault.unreadNotificationCount,
            builder: (context, count, _) => IconButton(
              tooltip:
                  'Activity notifications${count > 0 ? ', $count unread' : ''}',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => NotificationsScreen(
                    vault: widget.vault,
                    isHiddenVault: _hiddenMode,
                  ),
                ),
              ),
              icon: Badge(
                isLabelVisible: count > 0,
                label: Text(count > 99 ? '99+' : '$count'),
                child: const Icon(Icons.notifications_outlined),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.lock_outline),
            tooltip: 'Lock Vault',
            onPressed: widget.onLock,
          ),
        ],
      ),
      body: IndexedStack(index: _currentIndex, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder),
            label: 'Files',
          ),
          NavigationDestination(
            icon: Icon(Icons.photo_library_outlined),
            selectedIcon: Icon(Icons.photo_library),
            label: 'Photos',
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_rounded),
            selectedIcon: Icon(Icons.grid_view_rounded),
            label: 'Tools',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
