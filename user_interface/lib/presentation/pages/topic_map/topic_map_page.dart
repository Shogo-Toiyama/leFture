import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lefture/application/topic_map/topic_map_provider.dart';
import 'package:lefture/presentation/themes/app_colors.dart';
import 'package:lefture/presentation/widgets/topic_map/cluster_view/cluster_map_view.dart';

/// Topic Map for a single course, fetched from the `topic_maps` table (the
/// `map` jsonb column produced by the topic-mapping pipeline -- see
/// TopicMapData.fromJson).
class TopicMapPage extends ConsumerWidget {
  const TopicMapPage({super.key, required this.courseId});

  final String courseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final topicMapAsync = ref.watch(topicMapForCourseProvider(courseId));

    return Scaffold(
      backgroundColor: AppColors.universe.voidBackground,
      body: topicMapAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.starGold),
        ),
        error: (error, _) => Center(
          child: Text(
            'Error: $error',
            style: const TextStyle(color: AppColors.correctionRed),
          ),
        ),
        data: (data) {
          if (data == null) {
            return Center(
              child: Text(
                'Topic map is still being generated…',
                style: TextStyle(color: AppColors.universe.textComet),
              ),
            );
          }
          return ClusterMapView(data: data, courseId: courseId);
        },
      ),
    );
  }
}
