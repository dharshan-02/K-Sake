import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../data/local_vault.dart';
import '../data/firebase_sync_service.dart';
import '../models/vault_note.dart';

class NotesScreen extends StatefulWidget {
  const NotesScreen({
    super.key,
    required this.vault,
    this.isHiddenVault = false,
  });

  final LocalVault vault;
  final bool isHiddenVault;

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  List<VaultNote> _notes = [];
  bool _loading = true;
  String _query = '';

  static const List<Color> _noteColors = [
    Color(0xFF1E293B), // Slate default
    Color(0xFF064E3B), // Emerald
    Color(0xFF701A75), // Fuchsia / Purple
    Color(0xFF78350F), // Amber
    Color(0xFF1E3A8A), // Deep Blue
    Color(0xFF881337), // Crimson
  ];

  @override
  void initState() {
    super.initState();
    _loadNotes();
  }

  Future<void> _loadNotes() async {
    setState(() => _loading = true);
    final notes = await widget.vault.listNotes(isHidden: widget.isHiddenVault);
    if (mounted) {
      setState(() {
        _notes = notes;
        _loading = false;
      });
    }
  }

  Future<void> _openNoteEditor([VaultNote? existingNote]) async {
    final titleController = TextEditingController(
      text: existingNote?.title ?? '',
    );
    final contentController = TextEditingController(
      text: existingNote?.content ?? '',
    );
    var selectedColor =
        existingNote?.colorValue ?? _noteColors.first.toARGB32();
    var isPinned = existingNote?.isPinned ?? false;
    var isHidden = existingNote?.isHidden ?? widget.isHiddenVault;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final theme = Theme.of(context);
          return Container(
            height: MediaQuery.of(context).size.height * 0.85,
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text(
                      existingNote == null ? 'New Encrypted Note' : 'Edit Note',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: Icon(
                        isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                      ),
                      color: isPinned ? Colors.amber : null,
                      tooltip: 'Pin Note',
                      onPressed: () =>
                          setModalState(() => isPinned = !isPinned),
                    ),
                    if (existingNote != null)
                      IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.redAccent,
                        ),
                        onPressed: () async {
                          Navigator.pop(ctx);
                          await widget.vault.deleteNote(existingNote.id);
                          FirebaseSyncService(widget.vault).deleteCloudNote(existingNote.id);
                          _loadNotes();
                        },
                      ),
                    FilledButton(
                      onPressed: () async {
                        final title = titleController.text.trim();
                        final content = contentController.text.trim();
                        if (title.isEmpty && content.isEmpty) {
                          Navigator.pop(ctx);
                          return;
                        }
                        final now = DateTime.now().toUtc();
                        final note = VaultNote(
                          id: existingNote?.id ?? const Uuid().v4(),
                          title: title.isEmpty ? 'Untitled Note' : title,
                          content: content,
                          colorValue: selectedColor,
                          isPinned: isPinned,
                          isHidden: isHidden,
                          createdAt: existingNote?.createdAt ?? now,
                          updatedAt: now,
                        );
                        await widget.vault.saveNote(note);
                        FirebaseSyncService(widget.vault).uploadNote(note);
                        if (ctx.mounted) Navigator.pop(ctx);
                        _loadNotes();
                      },
                      child: const Text('Save'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Color picker strip
                Row(
                  children: [
                    const Text('Tag Color: ', style: TextStyle(fontSize: 12)),
                    const SizedBox(width: 8),
                    for (final c in _noteColors)
                      GestureDetector(
                        onTap: () =>
                            setModalState(() => selectedColor = c.toARGB32()),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: selectedColor == c.toARGB32()
                                  ? Colors.white
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    const Spacer(),
                    if (!widget.isHiddenVault)
                      FilterChip(
                        selected: isHidden,
                        label: const Text(
                          'Hidden Safe',
                          style: TextStyle(fontSize: 11),
                        ),
                        avatar: const Icon(Icons.shield_outlined, size: 14),
                        onSelected: (val) =>
                            setModalState(() => isHidden = val),
                      ),
                  ],
                ),
                const Divider(height: 20),

                TextField(
                  controller: titleController,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Note Title…',
                    border: InputBorder.none,
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: TextField(
                    controller: contentController,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    decoration: const InputDecoration(
                      hintText: 'Type your secure memo, private thoughts, or keys here…',
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _notes.where((n) {
      final q = _query.toLowerCase();
      return n.title.toLowerCase().contains(q) ||
          n.content.toLowerCase().contains(q);
    }).toList();

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: SearchBar(
              hintText: 'Search encrypted notes…',
              leading: const Icon(Icons.search, size: 20),
              elevation: const WidgetStatePropertyAll(0),
              backgroundColor: WidgetStatePropertyAll(
                Theme.of(context).cardTheme.color?.withValues(alpha: 0.8),
              ),
              onChanged: (val) => setState(() => _query = val),
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
                          Icons.note_alt_outlined,
                          size: 60,
                          color: Theme.of(context).hintColor,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _query.isEmpty ? 'No notes yet' : 'No matching notes',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Write private thoughts and confidential memos.',
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadNotes,
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                      itemCount: filtered.length,
                      itemBuilder: (context, i) {
                        final note = filtered[i];
                        return _buildNoteCard(note);
                      },
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openNoteEditor(),
        icon: const Icon(Icons.add),
        label: const Text('New Note'),
      ),
    );
  }

  Widget _buildNoteCard(VaultNote note) {
    final cardColor = Color(note.colorValue);

    return Card(
      color: cardColor,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: note.isPinned
              ? Colors.amber.withValues(alpha: 0.5)
              : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openNoteEditor(note),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      note.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  if (note.isPinned)
                    const Icon(Icons.push_pin, size: 16, color: Colors.amber),
                  if (note.isHidden) ...[
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.shield_outlined,
                      size: 16,
                      color: Colors.tealAccent,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Text(
                note.content,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${note.updatedAt.day}/${note.updatedAt.month}/${note.updatedAt.year}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 11,
                    ),
                  ),
                  Text(
                    '${note.content.length} chars',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
