// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat_attachment_files.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 送った資料の元のファイルを開く署名付きURL(画像の見本・PDFの表示・元のファイルを開く)。
///
/// 署名付きURLは10分で切れるので、9分だけ使い回す(webappの useAttachmentImageUrl と同じ)。
/// 同じ資料を同時に頼んでも、問い合わせは1回。失敗は覚えず、次に頼んだときにやり直す。

@ProviderFor(chatAttachmentFileLink)
final chatAttachmentFileLinkProvider = ChatAttachmentFileLinkFamily._();

/// 送った資料の元のファイルを開く署名付きURL(画像の見本・PDFの表示・元のファイルを開く)。
///
/// 署名付きURLは10分で切れるので、9分だけ使い回す(webappの useAttachmentImageUrl と同じ)。
/// 同じ資料を同時に頼んでも、問い合わせは1回。失敗は覚えず、次に頼んだときにやり直す。

final class ChatAttachmentFileLinkProvider
    extends
        $FunctionalProvider<
          AsyncValue<ChatFileLink>,
          ChatFileLink,
          FutureOr<ChatFileLink>
        >
    with $FutureModifier<ChatFileLink>, $FutureProvider<ChatFileLink> {
  /// 送った資料の元のファイルを開く署名付きURL(画像の見本・PDFの表示・元のファイルを開く)。
  ///
  /// 署名付きURLは10分で切れるので、9分だけ使い回す(webappの useAttachmentImageUrl と同じ)。
  /// 同じ資料を同時に頼んでも、問い合わせは1回。失敗は覚えず、次に頼んだときにやり直す。
  ChatAttachmentFileLinkProvider._({
    required ChatAttachmentFileLinkFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'chatAttachmentFileLinkProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$chatAttachmentFileLinkHash();

  @override
  String toString() {
    return r'chatAttachmentFileLinkProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<ChatFileLink> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<ChatFileLink> create(Ref ref) {
    final argument = this.argument as String;
    return chatAttachmentFileLink(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ChatAttachmentFileLinkProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$chatAttachmentFileLinkHash() =>
    r'74236f491682d3ade9a96f2e071a8c03e5b7bac0';

/// 送った資料の元のファイルを開く署名付きURL(画像の見本・PDFの表示・元のファイルを開く)。
///
/// 署名付きURLは10分で切れるので、9分だけ使い回す(webappの useAttachmentImageUrl と同じ)。
/// 同じ資料を同時に頼んでも、問い合わせは1回。失敗は覚えず、次に頼んだときにやり直す。

final class ChatAttachmentFileLinkFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<ChatFileLink>, String> {
  ChatAttachmentFileLinkFamily._()
    : super(
        retry: null,
        name: r'chatAttachmentFileLinkProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// 送った資料の元のファイルを開く署名付きURL(画像の見本・PDFの表示・元のファイルを開く)。
  ///
  /// 署名付きURLは10分で切れるので、9分だけ使い回す(webappの useAttachmentImageUrl と同じ)。
  /// 同じ資料を同時に頼んでも、問い合わせは1回。失敗は覚えず、次に頼んだときにやり直す。

  ChatAttachmentFileLinkProvider call(String attachmentId) =>
      ChatAttachmentFileLinkProvider._(argument: attachmentId, from: this);

  @override
  String toString() => r'chatAttachmentFileLinkProvider';
}
