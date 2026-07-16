// lib/presentation/widgets/note_sub_toolbar.dart
//
// Floating popover shown when the "Note" button is tapped in
// CardSelectionToolbar: a small draggable card with a text field for
// writing a note attached to the current text selection, plus a save
// button that persists it as a "notes"-type Annotation.

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import 'package:lecture_companion_ui/presentation/widgets/draggable_toolbar_card.dart';

class NoteSubToolbar extends HookWidget {
  const NoteSubToolbar({super.key, this.initialText = '', this.onSave});

  final String initialText;
  final ValueChanged<String>? onSave;

  @override
  Widget build(BuildContext context) {
    final controller = useTextEditingController(text: initialText);

    return DraggableToolbarCard(
      child: SizedBox(
        width: 220,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              minLines: 2,
              maxLines: 5,
              style: const TextStyle(fontSize: 14, color: Colors.black87),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'Add a note...',
                hintStyle: TextStyle(color: Colors.black38),
              ),
            ),
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => onSave?.call(controller.text),
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(Icons.check_circle, size: 22, color: Colors.black54),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
