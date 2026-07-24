// lib/presentation/widgets/note_sub_toolbar.dart
//
// Floating popover shown when the "Note" button is tapped in
// CardSelectionToolbar: a small draggable card with a text field for
// writing a note attached to the current text selection, plus a save
// button that persists it as a "notes"-type Annotation.
// Expanded to support Read-Only (viewing) mode and Edit/Delete states.

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import 'package:lecture_companion_ui/l10n/generated/app_localizations.dart';
import 'package:lecture_companion_ui/presentation/widgets/draggable_toolbar_card.dart';

class NoteSubToolbar extends HookWidget {
  const NoteSubToolbar({
    super.key,
    this.initialText = '',
    this.onSave,
    this.onDelete,
    this.isEditing = true,
    this.onEditModeToggle,
  });

  final String initialText;
  final ValueChanged<String>? onSave;
  final VoidCallback? onDelete;
  final bool isEditing;
  final VoidCallback? onEditModeToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = useTextEditingController(text: initialText);

    // If the initialText changes (e.g. from state change), update the controller text
    useEffect(() {
      controller.text = initialText;
      return null;
    }, [initialText]);

    return DraggableToolbarCard(
      child: SizedBox(
        width: 220,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            TextField(
              controller: controller,
              autofocus: isEditing,
              readOnly: !isEditing,
              minLines: 2,
              maxLines: 5,
              style: const TextStyle(fontSize: 14, color: Colors.black87),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: isEditing ? l10n.noteToolbarHintText : '',
                hintStyle: const TextStyle(color: Colors.black38),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!isEditing) ...[
                  // Delete Button
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: onDelete,
                      child: const Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(Icons.delete_outline_rounded, size: 20, color: Colors.redAccent),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Edit Button
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: onEditModeToggle,
                      child: const Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(Icons.edit_note_rounded, size: 22, color: Colors.black54),
                      ),
                    ),
                  ),
                ] else ...[
                  // Save Button
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => onSave?.call(controller.text),
                      child: const Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(Icons.check_circle_outline_rounded, size: 22, color: Colors.black54),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
