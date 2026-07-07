import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'debug_providers.g.dart';

@riverpod
class DebugForceEmptyHome extends _$DebugForceEmptyHome {
  @override
  bool build() {
    return false;
  }

  void toggle(bool val) {
    state = val;
  }
}
