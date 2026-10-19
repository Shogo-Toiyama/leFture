// lib/infrastructure/chat/chat_file_picker.dart
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lefture/infrastructure/chat/chat_file_prep.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'chat_file_picker.g.dart';

@Riverpod(keepAlive: true)
ChatFilePicker chatFilePicker(Ref ref) => const DeviceChatFilePicker();

/// 端末で資料を選ぶ(「＋」メニューの カメラ / 写真 / ファイル)。選ばずに閉じたら空のリスト。
/// 許可がなくて開けないときなどは例外を投げる(画面が「設定で許可してください」と案内する)。
abstract class ChatFilePicker {
  Future<List<PickedChatFile>> takePhoto();
  Future<List<PickedChatFile>> pickPhotos();
  Future<List<PickedChatFile>> pickFiles();
}

class DeviceChatFilePicker implements ChatFilePicker {
  const DeviceChatFilePicker();

  /// 写真・カメラの画像。端末が付ける名前(image_picker_UUID.jpg)は「@名前」やチップに出ると読みにくいので、
  /// 撮った/選んだ時刻の名前にする(拡張子はそのまま。種類は中身(mimeType)でも判定する)。
  PickedChatFile _photo(XFile file, int index) {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp =
        '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}${two(now.second)}';
    final dot = file.name.lastIndexOf('.');
    final extension = dot >= 0 && dot < file.name.length - 1
        ? file.name.substring(dot).toLowerCase()
        : '.jpg';
    return PickedChatFile(
      path: file.path,
      name: 'photo_$stamp${index == 0 ? '' : '_$index'}$extension',
      mimeType: file.mimeType ?? 'image/jpeg',
    );
  }

  @override
  Future<List<PickedChatFile>> takePhoto() async {
    final file = await ImagePicker().pickImage(source: ImageSource.camera);
    return file == null ? const [] : [_photo(file, 0)];
  }

  @override
  Future<List<PickedChatFile>> pickPhotos() async {
    final files = await ImagePicker().pickMultiImage();
    return [for (var i = 0; i < files.length; i++) _photo(files[i], i)];
  }

  @override
  Future<List<PickedChatFile>> pickFiles() async {
    final result = await FilePicker.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: chatPickableExtensions,
    );
    if (result == null) return const [];
    return [
      for (final f in result.files)
        if (f.path != null) PickedChatFile(path: f.path!, name: f.name),
    ];
  }
}
