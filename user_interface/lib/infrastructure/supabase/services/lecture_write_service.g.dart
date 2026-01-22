// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'lecture_write_service.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(lectureWriteService)
final lectureWriteServiceProvider = LectureWriteServiceProvider._();

final class LectureWriteServiceProvider
    extends
        $FunctionalProvider<
          LectureWriteService,
          LectureWriteService,
          LectureWriteService
        >
    with $Provider<LectureWriteService> {
  LectureWriteServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'lectureWriteServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$lectureWriteServiceHash();

  @$internal
  @override
  $ProviderElement<LectureWriteService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  LectureWriteService create(Ref ref) {
    return lectureWriteService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LectureWriteService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LectureWriteService>(value),
    );
  }
}

String _$lectureWriteServiceHash() =>
    r'8a08202d177b3ae99b8644dd890acaca1d060a7a';
