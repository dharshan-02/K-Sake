import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../data/local_vault.dart';
import '../models/vault_credential.dart';

class PasswordsScreen extends StatefulWidget {
  const PasswordsScreen({
    super.key,
    required this.vault,
    this.isHiddenVault = false,
  });

  final LocalVault vault;
  final bool isHiddenVault;

  @override
  State<PasswordsScreen> createState() => _PasswordsScreenState();
}

class _PasswordsScreenState extends State<PasswordsScreen> {
  List<VaultCredential> _credentials = [];
  bool _loading = true;
  String _query = '';
  String _selectedCategory = 'All';

  static const List<String> _categories = [
    'All',
    'Login',
    'Card',
    'API Key',
    'Recovery',
  ];

  @override
  void initState() {
    super.initState();
    _loadCredentials();
  }

  Future<void> _loadCredentials() async {
    setState(() => _loading = true);
    final list = await widget.vault.listCredentials(
      isHidden: widget.isHiddenVault,
    );
    if (mounted) {
      setState(() {
        _credentials = list;
        _loading = false;
      });
    }
  }

  String _generatePassword({
    int length = 16,
    bool uppercase = true,
    bool lowercase = true,
    bool numbers = true,
    bool symbols = true,
  }) {
    const upper = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    const lower = 'abcdefghijklmnopqrstuvwxyz';
    const digits = '0123456789';
    const syms = '!@#\$%^&*()-_=+[]{}|;:,.<>?';

    var pool = '';
    if (uppercase) pool += upper;
    if (lowercase) pool += lower;
    if (numbers) pool += digits;
    if (symbols) pool += syms;
    if (pool.isEmpty) pool = lower + digits;

    final rand = Random.secure();
    return List.generate(length, (_) => pool[rand.nextInt(pool.length)]).join();
  }

  Future<void> _openCredentialEditor([VaultCredential? existing]) async {
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final userCtrl = TextEditingController(text: existing?.username ?? '');
    final passCtrl = TextEditingController(text: existing?.password ?? '');
    final urlCtrl = TextEditingController(text: existing?.url ?? '');
    final notesCtrl = TextEditingController(text: existing?.notes ?? '');
    var category = existing?.category ?? 'Login';
    var isHidden = existing?.isHidden ?? widget.isHiddenVault;
    var obscurePass = true;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final theme = Theme.of(context);
          return Container(
            height: MediaQuery.of(context).size.height * 0.88,
            decoration: BoxDecoration(
              color: theme.scaffoldBackgroundColor,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            padding: EdgeInsets.only(
              top: 16,
              left: 20,
              right: 20,
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text(
                        existing == null
                            ? 'Add Secure Credential'
                            : 'Edit Credential',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      if (existing != null)
                        IconButton(
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.redAccent,
                          ),
                          onPressed: () async {
                            Navigator.pop(ctx);
                            await widget.vault.deleteCredential(existing.id);
                            _loadCredentials();
                          },
                        ),
                      FilledButton(
                        onPressed: () async {
                          final title = titleCtrl.text.trim();
                          final user = userCtrl.text.trim();
                          final pass = passCtrl.text;
                          if (title.isEmpty || pass.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Title and password are required.',
                                ),
                              ),
                            );
                            return;
                          }
                          final now = DateTime.now().toUtc();
                          final cred = VaultCredential(
                            id: existing?.id ?? const Uuid().v4(),
                            title: title,
                            username: user,
                            password: pass,
                            url: urlCtrl.text.trim().isEmpty
                                ? null
                                : urlCtrl.text.trim(),
                            notes: notesCtrl.text.trim().isEmpty
                                ? null
                                : notesCtrl.text.trim(),
                            category: category,
                            isHidden: isHidden,
                            createdAt: existing?.createdAt ?? now,
                            updatedAt: now,
                          );
                          await widget.vault.saveCredential(cred);
                          if (ctx.mounted) Navigator.pop(ctx);
                          _loadCredentials();
                        },
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Category Selector
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _categories.where((c) => c != 'All').map((c) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(c),
                            selected: category == c,
                            onSelected: (val) =>
                                setModalState(() => category = c),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 16),

                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(
                      labelText:
                          'Account / Service (e.g. Google, Bank, GitHub)',
                      prefixIcon: Icon(Icons.badge_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: userCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Username or Email',
                      prefixIcon: Icon(Icons.person_outline),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passCtrl,
                    obscureText: obscurePass,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.key_outlined),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.auto_awesome),
                            tooltip: 'Generate Strong Password',
                            onPressed: () {
                              final gen = _generatePassword();
                              passCtrl.text = gen;
                              setModalState(() => obscurePass = false);
                            },
                          ),
                          IconButton(
                            icon: Icon(
                              obscurePass
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                            onPressed: () =>
                                setModalState(() => obscurePass = !obscurePass),
                          ),
                        ],
                      ),
                      border: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: urlCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Website URL (Optional)',
                      prefixIcon: Icon(Icons.link_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Notes / Security Questions / PIN',
                      prefixIcon: Icon(Icons.note_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (!widget.isHiddenVault)
                    SwitchListTile(
                      title: const Text(
                        'Store in Hidden Safe',
                        style: TextStyle(fontSize: 14),
                      ),
                      subtitle: const Text(
                        'Only listed inside the Hidden Safe area',
                        style: TextStyle(fontSize: 12),
                      ),
                      value: isHidden,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (val) => setModalState(() => isHidden = val),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _credentials.where((c) {
      final matchesCat =
          _selectedCategory == 'All' || c.category == _selectedCategory;
      final q = _query.toLowerCase();
      final matchesQ =
          c.title.toLowerCase().contains(q) ||
          c.username.toLowerCase().contains(q) ||
          (c.url?.toLowerCase().contains(q) ?? false);
      return matchesCat && matchesQ;
    }).toList();

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SearchBar(
              hintText: 'Search logins & passwords…',
              leading: const Icon(Icons.search, size: 20),
              elevation: const WidgetStatePropertyAll(0),
              backgroundColor: WidgetStatePropertyAll(
                Theme.of(context).cardTheme.color?.withValues(alpha: 0.8),
              ),
              onChanged: (val) => setState(() => _query = val),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: _categories.map((c) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(c, style: const TextStyle(fontSize: 12)),
                    selected: _selectedCategory == c,
                    onSelected: (val) => setState(() => _selectedCategory = c),
                  ),
                );
              }).toList(),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.password_rounded,
                          size: 60,
                          color: Theme.of(context).hintColor,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _query.isEmpty
                              ? 'No credentials stored'
                              : 'No matching logins',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Save accounts, banking logins, and recovery keys.',
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadCredentials,
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                      itemCount: filtered.length,
                      itemBuilder: (context, i) {
                        final cred = filtered[i];
                        return _buildCredCard(cred);
                      },
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openCredentialEditor(),
        icon: const Icon(Icons.add),
        label: const Text('Add Login'),
      ),
    );
  }

  Widget _buildCredCard(VaultCredential cred) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: theme.colorScheme.primary.withValues(
                    alpha: 0.15,
                  ),
                  child: Icon(
                    cred.category == 'Card'
                        ? Icons.credit_card
                        : cred.category == 'API Key'
                        ? Icons.code
                        : Icons.lock_outline,
                    color: theme.colorScheme.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              cred.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          if (cred.isHidden) ...[
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.shield_outlined,
                              size: 15,
                              color: Colors.tealAccent,
                            ),
                          ],
                        ],
                      ),
                      if (cred.username.isNotEmpty)
                        Text(
                          cred.username,
                          style: TextStyle(
                            color: theme.hintColor,
                            fontSize: 13,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  onPressed: () => _openCredentialEditor(cred),
                ),
              ],
            ),
            const Divider(height: 18),
            Row(
              children: [
                Text(
                  '••••••••••••',
                  style: TextStyle(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    letterSpacing: 2,
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
                IconButton.filledTonal(
                  iconSize: 18,
                  icon: const Icon(Icons.copy),
                  tooltip: 'Copy Password',
                  onPressed: () => _copyToClipboard(cred.password, 'Password'),
                ),
                const SizedBox(width: 8),
                if (cred.username.isNotEmpty)
                  IconButton.filledTonal(
                    iconSize: 18,
                    icon: const Icon(Icons.person),
                    tooltip: 'Copy Username',
                    onPressed: () =>
                        _copyToClipboard(cred.username, 'Username'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
