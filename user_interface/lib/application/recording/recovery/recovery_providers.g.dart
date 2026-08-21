// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'recovery_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(recordingRecoveryService)
final recordingRecoveryServiceProvider = RecordingRecoveryServiceProvider._();

final class RecordingRecoveryServiceProvider
    extends
        $FunctionalProvider<
          RecordingRecoveryService,
          RecordingRecoveryService,
          RecordingRecoveryService
        >
    with $Provider<RecordingRecoveryService> {
  RecordingRecoveryServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'recordingRecoveryServiceProvider',
        isAutoDispose: false,
        dependencies: <ProviderOrFamily>[audioRecorderServiceProvider],
        $allTransitiveDependencies: <ProviderOrFamily>[
          RecordingRecoveryServiceProvider.$allTransitiveDependencies0,
        ],
      );

  static final $allTransitiveDependencies0 = audioRecorderServiceProvider;

  @override
  String debugGetCreateSourceHash() => _$recordingRecoveryServiceHash();

  @$internal
  @override
  $ProviderElement<RecordingRecoveryService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  RecordingRecoveryService create(Ref ref) {
    return recordingRecoveryService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RecordingRecoveryService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RecordingRecoveryService>(value),
    );
  }
}

String _$recordingRecoveryServiceHash() =>
    r'90b52977516fa68ca2b3b0f004bd0972f698baac';

/// 起動時に一度検出し、見つかった孤児のエンコードをバックグラウンドで
/// 自動的に開始する(カードを開くのを待たない — ユーザーが「壊れているのでは」
/// と不安になる時間を最小化するため)。
///
/// app.dartがtutorialLectureSeedProvider/uploadManagerProviderと同じ形で
/// ref.watchしてアプリ起動と同時に必ず生成させる想定。
///
/// recordingRecoveryServiceProviderがdependenciesを宣言した(スコープ可能な
/// audioRecorderServiceProviderに依存するため)ことで、それをwatchする
/// このプロバイダも連鎖的にdependenciesの明示が必要になる。

@ProviderFor(OrphanRecordings)
final orphanRecordingsProvider = OrphanRecordingsProvider._();

/// 起動時に一度検出し、見つかった孤児のエンコードをバックグラウンドで
/// 自動的に開始する(カードを開くのを待たない — ユーザーが「壊れているのでは」
/// と不安になる時間を最小化するため)。
///
/// app.dartがtutorialLectureSeedProvider/uploadManagerProviderと同じ形で
/// ref.watchしてアプリ起動と同時に必ず生成させる想定。
///
/// recordingRecoveryServiceProviderがdependenciesを宣言した(スコープ可能な
/// audioRecorderServiceProviderに依存するため)ことで、それをwatchする
/// このプロバイダも連鎖的にdependenciesの明示が必要になる。
final class OrphanRecordingsProvider
    extends $AsyncNotifierProvider<OrphanRecordings, List<OrphanRecording>> {
  /// 起動時に一度検出し、見つかった孤児のエンコードをバックグラウンドで
  /// 自動的に開始する(カードを開くのを待たない — ユーザーが「壊れているのでは」
  /// と不安になる時間を最小化するため)。
  ///
  /// app.dartがtutorialLectureSeedProvider/uploadManagerProviderと同じ形で
  /// ref.watchしてアプリ起動と同時に必ず生成させる想定。
  ///
  /// recordingRecoveryServiceProviderがdependenciesを宣言した(スコープ可能な
  /// audioRecorderServiceProviderに依存するため)ことで、それをwatchする
  /// このプロバイダも連鎖的にdependenciesの明示が必要になる。
  OrphanRecordingsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'orphanRecordingsProvider',
        isAutoDispose: false,
        dependencies: <ProviderOrFamily>[recordingRecoveryServiceProvider],
        $allTransitiveDependencies: <ProviderOrFamily>[
          OrphanRecordingsProvider.$allTransitiveDependencies0,
          OrphanRecordingsProvider.$allTransitiveDependencies1,
        ],
      );

  static final $allTransitiveDependencies0 = recordingRecoveryServiceProvider;
  static final $allTransitiveDependencies1 =
      RecordingRecoveryServiceProvider.$allTransitiveDependencies0;

  @override
  String debugGetCreateSourceHash() => _$orphanRecordingsHash();

  @$internal
  @override
  OrphanRecordings create() => OrphanRecordings();
}

String _$orphanRecordingsHash() => r'cacc0695ac3eeba5b9a620807444644d1cd47526';

/// 起動時に一度検出し、見つかった孤児のエンコードをバックグラウンドで
/// 自動的に開始する(カードを開くのを待たない — ユーザーが「壊れているのでは」
/// と不安になる時間を最小化するため)。
///
/// app.dartがtutorialLectureSeedProvider/uploadManagerProviderと同じ形で
/// ref.watchしてアプリ起動と同時に必ず生成させる想定。
///
/// recordingRecoveryServiceProviderがdependenciesを宣言した(スコープ可能な
/// audioRecorderServiceProviderに依存するため)ことで、それをwatchする
/// このプロバイダも連鎖的にdependenciesの明示が必要になる。

abstract class _$OrphanRecordings
    extends $AsyncNotifier<List<OrphanRecording>> {
  FutureOr<List<OrphanRecording>> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref =
        this.ref
            as $Ref<AsyncValue<List<OrphanRecording>>, List<OrphanRecording>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<List<OrphanRecording>>,
                List<OrphanRecording>
              >,
              AsyncValue<List<OrphanRecording>>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

/// [lectureId]のエンコード進捗を購読する。
/// recordingRecoveryServiceProviderのdependencies宣言を連鎖的に受け継ぐ
/// 必要がある理由はOrphanRecordingsのコメントを参照。

@ProviderFor(recoveryEncodeState)
final recoveryEncodeStateProvider = RecoveryEncodeStateFamily._();

/// [lectureId]のエンコード進捗を購読する。
/// recordingRecoveryServiceProviderのdependencies宣言を連鎖的に受け継ぐ
/// 必要がある理由はOrphanRecordingsのコメントを参照。

final class RecoveryEncodeStateProvider
    extends
        $FunctionalProvider<
          AsyncValue<RecoveryEncodeState>,
          RecoveryEncodeState,
          Stream<RecoveryEncodeState>
        >
    with
        $FutureModifier<RecoveryEncodeState>,
        $StreamProvider<RecoveryEncodeState> {
  /// [lectureId]のエンコード進捗を購読する。
  /// recordingRecoveryServiceProviderのdependencies宣言を連鎖的に受け継ぐ
  /// 必要がある理由はOrphanRecordingsのコメントを参照。
  RecoveryEncodeStateProvider._({
    required RecoveryEncodeStateFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'recoveryEncodeStateProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  static final $allTransitiveDependencies0 = recordingRecoveryServiceProvider;
  static final $allTransitiveDependencies1 =
      RecordingRecoveryServiceProvider.$allTransitiveDependencies0;

  @override
  String debugGetCreateSourceHash() => _$recoveryEncodeStateHash();

  @override
  String toString() {
    return r'recoveryEncodeStateProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<RecoveryEncodeState> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<RecoveryEncodeState> create(Ref ref) {
    final argument = this.argument as String;
    return recoveryEncodeState(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is RecoveryEncodeStateProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$recoveryEncodeStateHash() =>
    r'53fc988b523e9054fbe99af6feb921dc51828edc';

/// [lectureId]のエンコード進捗を購読する。
/// recordingRecoveryServiceProviderのdependencies宣言を連鎖的に受け継ぐ
/// 必要がある理由はOrphanRecordingsのコメントを参照。

final class RecoveryEncodeStateFamily extends $Family
    with $FunctionalFamilyOverride<Stream<RecoveryEncodeState>, String> {
  RecoveryEncodeStateFamily._()
    : super(
        retry: null,
        name: r'recoveryEncodeStateProvider',
        dependencies: <ProviderOrFamily>[recordingRecoveryServiceProvider],
        $allTransitiveDependencies: <ProviderOrFamily>[
          RecoveryEncodeStateProvider.$allTransitiveDependencies0,
          RecoveryEncodeStateProvider.$allTransitiveDependencies1,
        ],
        isAutoDispose: true,
      );

  /// [lectureId]のエンコード進捗を購読する。
  /// recordingRecoveryServiceProviderのdependencies宣言を連鎖的に受け継ぐ
  /// 必要がある理由はOrphanRecordingsのコメントを参照。

  RecoveryEncodeStateProvider call(String lectureId) =>
      RecoveryEncodeStateProvider._(argument: lectureId, from: this);

  @override
  String toString() => r'recoveryEncodeStateProvider';
}
