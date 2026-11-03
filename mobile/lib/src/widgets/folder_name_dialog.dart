import 'package:flutter/material.dart';

class FolderNameDialog extends StatefulWidget {
  const FolderNameDialog({
    super.key,
    required this.title,
    required this.submitLabel,
    required this.fieldLabel,
    required this.hintText,
    this.initialName = '',
  });

  final String title;
  final String submitLabel;
  final String fieldLabel;
  final String hintText;
  final String initialName;

  @override
  State<FolderNameDialog> createState() => _FolderNameDialogState();
}

class _FolderNameDialogState extends State<FolderNameDialog> {
  late String _name = widget.initialName;

  void _submit() => Navigator.of(context).pop(_name.trim());

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextFormField(
      initialValue: widget.initialName,
      autofocus: true,
      maxLength: 80,
      textCapitalization: TextCapitalization.words,
      decoration: InputDecoration(
        labelText: widget.fieldLabel,
        hintText: widget.hintText,
      ),
      onChanged: (value) => _name = value,
      onFieldSubmitted: (_) => _submit(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: Text(widget.submitLabel)),
    ],
  );
}
