import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lefture/application/lecture/lecture_providers.dart';
import 'package:lefture/core/utils/topic_image_paths.dart';

/// Watches one lecture's images in display priority order. Limit new requests
/// per screen and let the visible route advance the queue.
Map<String, AsyncValue<File>> watchTopicImages(
  WidgetRef ref,
  Iterable<String> imagePaths, {
  required bool startRequests,
  bool prioritizeFirst = false,
}) {
  final originals = imagePaths
      .where((path) => path.trim().isNotEmpty && !path.startsWith('assets/'))
      .toSet();
  final images = <String, AsyncValue<File>>{};
  const maxPending = 3;

  void watchExisting(String path) {
    final provider = artifactFileProvider(path);
    if (ref.watch(provider.exists)) {
      images[path] = ref.watch(provider);
    }
  }

  originals.forEach(watchExisting);
  final thumbnails = originals.map(thumbnailPathFor).nonNulls.toSet();
  thumbnails.forEach(watchExisting);
  if (!startRequests) return images;

  final neededThumbnails = {
    for (final path in originals)
      if (images[path]?.hasValue != true) ?thumbnailPathFor(path),
  };
  // A missing thumbnail must still let the original phase start. Riverpod
  // can retry failures in the background without holding up the queue.
  bool awaitingFirstResult(AsyncValue<File>? image) =>
      image == null || (!image.hasValue && !image.hasError);

  final loadingThumbnails = neededThumbnails.any(
    (path) => awaitingFirstResult(images[path]),
  );
  final phase = loadingThumbnails ? neededThumbnails : originals;
  var pending = phase
      .where(
        (path) => images.containsKey(path) && awaitingFirstResult(images[path]),
      )
      .length;
  final firstOriginal = originals.firstOrNull;
  final priorityPath = !loadingThumbnails || firstOriginal == null
      ? firstOriginal
      : thumbnailPathFor(firstOriginal);
  for (final path in phase) {
    if (images.containsKey(path)) continue;
    final limit = prioritizeFirst && path == priorityPath
        ? maxPending + 1
        : maxPending;
    if (pending >= limit) break;
    final image = ref.watch(artifactFileProvider(path));
    images[path] = image;
    if (awaitingFirstResult(image)) pending++;
  }
  return images;
}

/// Keeps the thumbnail visible until the original has decoded a frame.
class TopicImage extends StatelessWidget {
  const TopicImage({
    super.key,
    required this.path,
    required this.images,
    this.placeholder = const SizedBox.shrink(),
  });

  final String path;
  final Map<String, AsyncValue<File>> images;
  final Widget placeholder;

  static bool hasFile(String? path, Map<String, AsyncValue<File>> images) {
    if (path == null) return false;
    final thumbnail = thumbnailPathFor(path);
    return path.startsWith('assets/') ||
        images[path]?.hasValue == true ||
        images[thumbnail]?.hasValue == true;
  }

  @override
  Widget build(BuildContext context) {
    if (path.startsWith('assets/')) {
      return Image.asset(
        path,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => placeholder,
      );
    }

    final original = images[path]?.value;
    final thumbnail = images[thumbnailPathFor(path)]?.value;
    Widget preview = placeholder;
    if (thumbnail != null) {
      preview = Image.file(
        thumbnail,
        key: const ValueKey('thumb'),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => placeholder,
      );
    }
    if (original == null) return preview;

    return Image.file(
      original,
      key: const ValueKey('full'),
      fit: BoxFit.cover,
      frameBuilder: (_, child, frame, _) => frame == null ? preview : child,
      errorBuilder: (_, _, _) => preview,
    );
  }
}
