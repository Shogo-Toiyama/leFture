// PROTOTYPE: this page's normal "AI Chat" content is temporarily replaced by
// a Topic Map Cluster View prototype, loading the dummy fixture at
// test_topic_map.json. Restore the original AiChatPage body once the
// prototype has been validated and moved to its own route.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:lefture/presentation/widgets/topic_map/cluster_view/cluster_map_view.dart';
import 'package:lefture/presentation/widgets/topic_map/topic_map_models.dart';

class AiChatPage extends StatefulWidget {
  const AiChatPage({super.key});

  @override
  State<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends State<AiChatPage> {
  late final Future<TopicMapData> _dataFuture;

  @override
  void initState() {
    super.initState();
    _dataFuture = _loadDummyTopicMap();
  }

  Future<TopicMapData> _loadDummyTopicMap() async {
    final raw = await rootBundle.loadString(
      'lib/presentation/pages/ai_chat/test_topic_map.json',
    );
    return TopicMapData.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Topic Map – Cluster View (Prototype)'),
      ),
      body: FutureBuilder<TopicMapData>(
        future: _dataFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('読み込みに失敗しました: ${snapshot.error}'));
          }
          final data = snapshot.data;
          if (data == null) {
            return const Center(child: CircularProgressIndicator());
          }
          // Dummy fixture, no real course behind it -- the detail sheet's
          // lecture lookup will just no-op (empty lecture list) if tapped.
          return ClusterMapView(data: data, courseId: 'dummy_course');
        },
      ),
    );
  }
}
