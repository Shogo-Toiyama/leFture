// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'folder_list_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(folderListStream)
final folderListStreamProvider = FolderListStreamFamily._();

final class FolderListStreamProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<LectureFolder>>,
          List<LectureFolder>,
          Stream<List<LectureFolder>>
        >
    with
        $FutureModifier<List<LectureFolder>>,
        $StreamProvider<List<LectureFolder>> {
  FolderListStreamProvider._({
    required FolderListStreamFamily super.from,
    required String? super.argument,
  }) : super(
         retry: null,
         name: r'folderListStreamProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$folderListStreamHash();

  @override
  String toString() {
    return r'folderListStreamProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<List<LectureFolder>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<LectureFolder>> create(Ref ref) {
    final argument = this.argument as String?;
    return folderListStream(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is FolderListStreamProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$folderListStreamHash() => r'0d2744b208f7a87d7a272e01cd23a72b6942c415';

final class FolderListStreamFamily extends $Family
    with $FunctionalFamilyOverride<Stream<List<LectureFolder>>, String?> {
  FolderListStreamFamily._()
    : super(
        retry: null,
        name: r'folderListStreamProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  FolderListStreamProvider call(String? parentId) =>
      FolderListStreamProvider._(argument: parentId, from: this);

  @override
  String toString() => r'folderListStreamProvider';
}
