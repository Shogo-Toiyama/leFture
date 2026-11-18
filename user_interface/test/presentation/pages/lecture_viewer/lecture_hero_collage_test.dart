// 講義ページのヘッダー(斜めに区切った画像のコラージュ)で、画像が枠いっぱいに
// 広がること(BoxFit.cover)。縮小版→元の画像のAnimatedSwitcherを既定のlayoutBuilder
// のまま使うと、子への制約がゆるみ、画像が元の比率の大きさで中央に置かれて空白ができた。
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lefture/application/lecture/lecture_providers.dart';
import 'package:lefture/application/lecture_viewer/lecture_viewer_data_provider.dart';
import 'package:lefture/core/utils/topic_image_paths.dart';
import 'package:lefture/domain/entities/lecture_topic.dart';
import 'package:lefture/presentation/pages/lecture_viewer/widgets/lecture_hero_collage.dart';

const _lectureId = 'lecture-1';
const _paths = ['u/lecture-1/images/topic_1.jpg', 'u/lecture-1/images/topic_2.jpg'];

LectureTopic _topic(int i, String path) => LectureTopic(
      id: 'topic-$i',
      lectureId: _lectureId,
      index: i,
      imagePath: path,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

void main() {
  // artifactFileProviderが返すファイル。このテスト環境ではデコードが完了しない
  // (下のpumpCollageの注を参照)ので、中身はリポジトリにあるPNGで足りる。
  final full = File('assets/icon.png');
  final thumb = File('assets/icon_foreground.png');

  Future<void> pumpCollage(
    WidgetTester tester, {
    required Future<File> Function() fullFile,
    required Future<File> Function() thumbFile,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          lectureTopicsProvider(_lectureId).overrideWith(
            (ref) => Stream.value([
              for (var i = 0; i < _paths.length; i++) _topic(i + 1, _paths[i]),
            ]),
          ),
          for (final p in _paths) ...[
            artifactFileProvider(p).overrideWith((ref) => fullFile()),
            artifactFileProvider(thumbnailPathFor(p)!)
                .overrideWith((ref) => thumbFile()),
          ],
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 360, child: LectureHeroCollage(lectureId: _lectureId)),
          ),
        ),
      ),
    );
    // Streamとファイルのproviderを流し、縮小版→元の画像の切り替えを終わらせる。
    // 注: このテスト環境ではImage.fileのデコードが完了しない(precacheImageは返らず、
    // 実時間で待ってもRawImage.imageはnullのまま)。そのため画像の中身ではなく、
    // 画像を描くRenderImageの大きさが枠と同じかを確かめる。修正前(制約がゆるい)は、
    // 画像が無ければ0x0、あれば元の比率の大きさになり、どちらでも枠より小さくなる。
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();
  }

  void expectImagesFillTheirSlots(WidgetTester tester) {
    final images = find.byType(RawImage);
    expect(images, findsNWidgets(_paths.length));
    for (final e in images.evaluate()) {
      final imageSize = (e.renderObject! as RenderBox).size;
      final slot = find.ancestor(of: find.byWidget(e.widget), matching: find.byType(ClipPath)).first;
      expect(imageSize, tester.getSize(slot), reason: '画像が枠いっぱいに広がっていない');
    }
  }

  testWidgets('元の画像が枠いっぱいに広がる', (tester) async {
    await pumpCollage(
      tester,
      fullFile: () async => full,
      thumbFile: () async => thumb,
    );
    expectImagesFillTheirSlots(tester);
  });

  testWidgets('元の画像が届く前の縮小版も枠いっぱいに広がる', (tester) async {
    await pumpCollage(
      tester,
      // 元の画像はまだ届かない
      fullFile: () => Completer<File>().future,
      thumbFile: () async => thumb,
    );
    expect(find.byKey(const ValueKey('thumb')), findsNWidgets(_paths.length));
    expectImagesFillTheirSlots(tester);
  });
}
