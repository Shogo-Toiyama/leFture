// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat_file_pipeline.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(chatFilePipeline)
final chatFilePipelineProvider = ChatFilePipelineProvider._();

final class ChatFilePipelineProvider
    extends
        $FunctionalProvider<
          ChatFilePipeline,
          ChatFilePipeline,
          ChatFilePipeline
        >
    with $Provider<ChatFilePipeline> {
  ChatFilePipelineProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'chatFilePipelineProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$chatFilePipelineHash();

  @$internal
  @override
  $ProviderElement<ChatFilePipeline> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ChatFilePipeline create(Ref ref) {
    return chatFilePipeline(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ChatFilePipeline value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ChatFilePipeline>(value),
    );
  }
}

String _$chatFilePipelineHash() => r'aea6134b421a79817f2c8fb9170d11dce3b953b8';
