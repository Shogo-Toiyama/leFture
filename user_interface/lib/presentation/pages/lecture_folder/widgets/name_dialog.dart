// lib/presentation/pages/lecture_folder/widgets/name_dialog.dart
import 'package:flutter/material.dart';

Future<String?> showFolderNameDialog({
  required BuildContext context,
  required String title,
  required String initialValue,
  required String saveLabel,
}) async {
  final controller = TextEditingController(text: initialValue);

  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Folder name'),
        onSubmitted: (_) => Navigator.of(context).pop(controller.text),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text),
          child: Text(saveLabel),
        ),
      ],
    ),
  );
}
