import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vector_math/vector_math_64.dart' as v;

part 'galaxy_state_provider.g.dart';

class GalaxyState {
  final v.Quaternion camRot;
  final double zoom;
  final bool autoRotate;

  const GalaxyState({
    required this.camRot,
    required this.zoom,
    required this.autoRotate,
  });
}

@Riverpod(keepAlive: true)
class GalaxyStateNotifier extends _$GalaxyStateNotifier {
  @override
  GalaxyState build() {
    return GalaxyState(
      camRot: v.Quaternion(0.25, 0.0, 0.0, 1.0)..normalize(),
      zoom: 4.0,
      autoRotate: true,
    );
  }

  void updateState({required v.Quaternion camRot, required double zoom}) {
    state = GalaxyState(
      camRot: camRot,
      zoom: zoom,
      autoRotate: state.autoRotate,
    );
  }

  void toggleAutoRotate() {
    state = GalaxyState(
      camRot: state.camRot,
      zoom: state.zoom,
      autoRotate: !state.autoRotate,
    );
  }

  void resetCamera() {
    state = GalaxyState(
      camRot: v.Quaternion(0.25, 0.0, 0.0, 1.0)..normalize(),
      zoom: 4.0,
      autoRotate: state.autoRotate,
    );
  }
}
