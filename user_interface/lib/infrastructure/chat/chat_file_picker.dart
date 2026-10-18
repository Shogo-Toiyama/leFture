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

  PickedChatFile _fromXFile(XFile file) => PickedChatFile(
    path: file.path,
    // カメラの写真には拡張子がない名前が付くことがある。種類は中身(mimeType)でも判定する
    name: file.name.isEmpty ? 'photo.jpg' : file.name,
    mimeType: file.mimeType ?? 'image/jpeg',
  );

  @override
  Future<List<PickedChatFile>> takePhoto() async {
    final file = await ImagePicker().pickImage(source: ImageSource.camera);
    return file == null ? const [] : [_fromXFile(file)];
  }

  @override
  Future<List<PickedChatFile>> pickPhotos() async {
    final files = await ImagePicker().pickMultiImage();
    return [for (final f in files) _fromXFile(f)];
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
