import 'package:flutter/material.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({
    super.key,
    required this.onNotes,
    required this.onPasswords,
  });

  final VoidCallback onNotes;
  final VoidCallback onPasswords;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Tools', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text(
          'Private notes and saved sign-in details stay in your encrypted vault.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 18),
        Card(
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: const CircleAvatar(child: Icon(Icons.note_alt_outlined)),
            title: const Text('Private notes'),
            subtitle: const Text('Write and organize notes in your vault'),
            trailing: const Icon(Icons.chevron_right),
            onTap: onNotes,
          ),
        ),
        Card(
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: const CircleAvatar(child: Icon(Icons.password_outlined)),
            title: const Text('Saved passwords'),
            subtitle: const Text('Keep account details in your vault'),
            trailing: const Icon(Icons.chevron_right),
            onTap: onPasswords,
          ),
        ),
      ],
    );
  }
}
