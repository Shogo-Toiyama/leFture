// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'folder_breadcrumb_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(folderBreadcrumb)
final folderBreadcrumbProvider = FolderBreadcrumbFamily._();

final class FolderBreadcrumbProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<FolderCrumb>>,
          List<FolderCrumb>,
          FutureOr<List<FolderCrumb>>
        >
    with
        $FutureModifier<List<FolderCrumb>>,
        $FutureProvider<List<FolderCrumb>> {
  FolderBreadcrumbProvider._({
    required FolderBreadcrumbFamily super.from,
    required String? super.argument,
  }) : super(
         retry: null,
         name: r'folderBreadcrumbProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$folderBreadcrumbHash();

  @override
  String toString() {
    return r'folderBreadcrumbProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<List<FolderCrumb>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<FolderCrumb>> create(Ref ref) {
    final argument = this.argument as String?;
    return folderBreadcrumb(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is FolderBreadcrumbProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$folderBreadcrumbHash() => r'7e70669c0c902121bc83d9963b5563f61d03a959';

final class FolderBreadcrumbFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<List<FolderCrumb>>, String?> {
  FolderBreadcrumbFamily._()
    : super(
        retry: null,
        name: r'folderBreadcrumbProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  FolderBreadcrumbProvider call(String? folderId) =>
      FolderBreadcrumbProvider._(argument: folderId, from: this);

  @override
  String toString() => r'folderBreadcrumbProvider';
}
