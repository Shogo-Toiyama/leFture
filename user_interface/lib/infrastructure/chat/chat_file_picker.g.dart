// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat_file_picker.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(chatFilePicker)
final chatFilePickerProvider = ChatFilePickerProvider._();

final class ChatFilePickerProvider
    extends $FunctionalProvider<ChatFilePicker, ChatFilePicker, ChatFilePicker>
    with $Provider<ChatFilePicker> {
  ChatFilePickerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'chatFilePickerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$chatFilePickerHash();

  @$internal
  @override
  $ProviderElement<ChatFilePicker> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ChatFilePicker create(Ref ref) {
    return chatFilePicker(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ChatFilePicker value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ChatFilePicker>(value),
    );
  }
}

String _$chatFilePickerHash() => r'e85e6ee6458498171ef5d345cbd45f10a23d84c5';
