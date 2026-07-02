import 'package:flutter/material.dart';

import 'package:wheelathlete/theme/app_dimens.dart';

/// Shows a dialog for editing the tags on a session.
///
/// Displays the [initialTags] as deletable chips, with a text field + "Add"
/// button to append a new tag. Tags are free-form strings: whitespace is
/// trimmed, empty strings and duplicates are ignored. Returns the updated
/// tag list when the user taps "Save", or `null` if they cancel.
Future<List<String>?> showTagEditorDialog(
  BuildContext context, {
  required List<String> initialTags,
}) {
  return showDialog<List<String>?>(
    context: context,
    builder: (ctx) => _TagEditorDialog(initialTags: initialTags),
  );
}

class _TagEditorDialog extends StatefulWidget {
  const _TagEditorDialog({required this.initialTags});
  final List<String> initialTags;

  @override
  State<_TagEditorDialog> createState() => _TagEditorDialogState();
}

class _TagEditorDialogState extends State<_TagEditorDialog> {
  late final List<String> _tags;
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tags = List<String>.from(widget.initialTags);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _addTag() {
    final value = _controller.text.trim();
    if (value.isEmpty || _tags.contains(value)) {
      _controller.clear();
      return;
    }
    setState(() {
      _tags.add(value);
    });
    _controller.clear();
  }

  void _removeTag(String tag) {
    setState(() {
      _tags.remove(tag);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Edit tags'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_tags.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Text(
                  'No tags yet. Add one below.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    for (final tag in _tags)
                      Chip(
                        label: Text(tag),
                        onDeleted: () => _removeTag(tag),
                        deleteIcon: const Icon(Icons.cancel),
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        backgroundColor: scheme.secondaryContainer,
                      ),
                  ],
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      labelText: 'New tag',
                      hintText: 'e.g. good, athlete-A',
                      isDense: true,
                    ),
                    onSubmitted: (_) => _addTag(),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                TextButton(
                  onPressed: _addTag,
                  child: const Text('Add'),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _tags),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
