import 'package:go_router/go_router.dart';
import 'package:lefture/application/errors/client_diagnostics.dart';

void Function() observeDiagnosticRoutes(
  GoRouter router,
  ClientDiagnostics diagnostics,
) {
  void recordRoute() => diagnostics.recordRoute(_visibleRouteTemplate(router));

  router.routerDelegate.addListener(recordRoute);
  recordRoute();
  return () => router.routerDelegate.removeListener(recordRoute);
}

String? _visibleRouteTemplate(GoRouter router) {
  final configuration = router.routerDelegate.currentConfiguration;
  final top = configuration.lastOrNull;
  final visible = top is ImperativeRouteMatch ? top.matches : configuration;
  if (visible.isError) return 'routing_error';
  return visible.isEmpty ? null : visible.fullPath;
}
