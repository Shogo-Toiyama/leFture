import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';

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
      // 宇宙の背景色
      backgroundColor: AppColors.universe.voidBackground,
      // 枠線をつけて浮き上がらせる
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.universe.glassBorder),
      ),
      title: Text(
        title, 
        style: TextStyle(color: AppColors.universe.textStarlight),
      ),
      content: TextField(
        controller: controller,
        autofocus: true,
        style: TextStyle(color: AppColors.universe.textStarlight),
        cursorColor: AppColors.starGold,
        decoration: InputDecoration(
          labelText: 'Folder name',
          labelStyle: TextStyle(color: AppColors.universe.textComet),
          // 下線だけの色調整
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: AppColors.universe.glassBorder),
          ),
          focusedBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: AppColors.starGold),
          ),
        ),
        // GoRouterのpopを使用
        onSubmitted: (_) => context.pop(controller.text),
      ),
      actions: [
        TextButton(
          onPressed: () => context.pop(null),
          child: Text(
            'Cancel', 
            style: TextStyle(color: AppColors.universe.textComet),
          ),
        ),
        FilledButton(
          onPressed: () => context.pop(controller.text),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.starGold,
            foregroundColor: Colors.white,
          ),
          child: Text(saveLabel),
        ),
      ],
    ),
  );
}