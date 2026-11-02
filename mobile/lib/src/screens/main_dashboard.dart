import 'package:flutter/material.dart';

import '../data/local_vault.dart';
import 'vault_screen.dart';
import 'gallery_screen.dart';
import 'notes_screen.dart';
import 'passwords_screen.dart';
import 'more_screen.dart';
import 'settings_screen.dart';

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
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

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
      ),
      SettingsScreen(vault: widget.vault, onLockNow: widget.onLock),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(
              _hiddenMode ? Icons.shield_moon : Icons.shield_rounded,
              color: _hiddenMode ? Colors.amber : colorScheme.primary,
              size: 24,
            ),
            const SizedBox(width: 8),
            Text(
              _hiddenMode ? 'Hidden Safe' : 'Keepsake',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                letterSpacing: -0.3,
                color: _hiddenMode ? Colors.amber : null,
              ),
            ),
            if (_hiddenMode) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.amber.withValues(alpha: 0.4),
                  ),
                ),
                child: const Text(
                  'DECOY',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.amber,
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (_hiddenMode)
            TextButton.icon(
              icon: const Icon(Icons.swap_horiz, size: 18),
              label: const Text('Normal'),
              onPressed: () => setState(() => _hiddenMode = false),
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
