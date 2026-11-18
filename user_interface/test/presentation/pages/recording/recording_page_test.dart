// 録音ページ(RecordingPage)の回帰テスト。
// - 開いただけで、Flutterのdebugチェック「ListTile background color or ink splashes
//   may be invisible」が出ないこと。背景色付きのContainerの直下にListTileを置くと
//   FlutterErrorが報告され、main.dartのFlutterError.onErrorでUNCAUGHT ERRORとして
//   記録・送信されていた。
// - 録音中に状態が更新されても、端を越えて引っ張った位置(iOSの跳ね返り)が引き戻されないこと。
//   SingleChildScrollViewはレイアウトのたびに端を越えた位置を範囲内へ戻すため、録音中の
//   更新(音量・経過時間)のたびに0へ戻り、端でガタついていた。
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lefture/application/asr/asr_model_manager.dart';
import 'package:lefture/application/asr/live_asr_controller.dart';
import 'package:lefture/application/course/course_list_provider.dart';
import 'package:lefture/application/credit/credit_providers.dart';
import 'package:lefture/application/recording/recording_controller.dart';
import 'package:lefture/application/recording/recording_state.dart';
import 'package:lefture/core/services/asr_engine/asr_live_segment.dart';
import 'package:lefture/core/services/recording_preferences.dart';
import 'package:lefture/domain/entities/course.dart';
import 'package:lefture/domain/entities/credit_summary.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/pages/recording/recording_page.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

late _FakeRecordingController _recording;

class _FakeRecordingController extends RecordingController {
  @override
  RecordingState build() {
    _recording = this;
    return RecordingState.idle();
  }

  void emit(RecordingState next) => state = next;

  @override
  Future<PermissionStatus> requestMicPermissionEarly() async =>
      PermissionStatus.granted;
}

class _FakeAsrModelManager extends AsrModelManager {
  @override
  Map<String, AsrLanguageModelState> build() => {};
}

class _FakeLiveAsrController extends LiveAsrController {
  @override
  List<AsrLiveSegment> build() => [];

  @override
  void setLiveTabFocused(bool focused) {}
}

void main() {
  setUpAll(() async {
    // 初回の録音のお知らせダイアログを出さない(ページの上に重なるため)
    SharedPreferences.setMockInitialValues({
      'has_seen_recording_consent_notice': true,
    });
    await RecordingPreferences().init();
  });

  Future<void> pumpRecordingPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          recordingControllerProvider.overrideWith(_FakeRecordingController.new),
          asrModelManagerProvider.overrideWith(_FakeAsrModelManager.new),
          liveAsrControllerProvider.overrideWith(_FakeLiveAsrController.new),
          courseListProvider.overrideWith((ref) => Stream.value(<Course>[])),
          // 読み込み中のままにする(サーバーへは行かない)
          creditSummaryProvider.overrideWith(
            (ref) => Completer<CreditSummary>().future,
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: RecordingPage(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('録音ページを開いてもListTileのdebugチェックに引っかからない', (tester) async {
    await pumpRecordingPage(tester);

    // 背景色付きのContainerの直下にあったタイル(設定・コース・録音言語)が実際に描かれていること
    expect(find.byType(ListTile), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('録音中に状態が更新されても、端を越えて引っ張った位置が引き戻されない', (tester) async {
    // 跳ね返り(BouncingScrollPhysics)はiOSの既定
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await pumpRecordingPage(tester);

    final recording = RecordingState.idle().copyWith(
      phase: RecordingPhase.recording,
      elapsedSeconds: 5,
      audioLevel: 0.2,
    );
    _recording.emit(recording);
    await tester.pump(const Duration(milliseconds: 16));

    final mainList = find.byType(ListView).first;
    final position = tester
        .state<ScrollableState>(
          find.descendant(of: mainList, matching: find.byType(Scrollable)).first,
        )
        .position;
    expect(position.pixels, 0);

    // 上端を越えて下へ引っ張る。1フレームごとに音量を更新する(録音中と同じ)。
    final gesture = await tester.startGesture(tester.getCenter(mainList));
    final pulled = <double>[];
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(0, 30));
      _recording.emit(recording.copyWith(audioLevel: (i % 7) / 7));
      await tester.pump(const Duration(milliseconds: 16));
      pulled.add(position.pixels);
    }
    // 引っ張るほど端を越えていく(更新のたびに0へ戻されない)
    for (var i = 1; i < pulled.length; i++) {
      expect(pulled[i], lessThan(pulled[i - 1]), reason: 'pulled=$pulled');
    }

    // 離すと、更新が続いていても0へなめらかに戻る(途中で向きが変わったり飛んだりしない)
    await gesture.up();
    final released = <double>[pulled.last];
    for (var i = 0; i < 40; i++) {
      _recording.emit(recording.copyWith(audioLevel: (i % 7) / 7));
      await tester.pump(const Duration(milliseconds: 16));
      released.add(position.pixels);
    }
    for (var i = 1; i < released.length; i++) {
      expect(released[i], greaterThanOrEqualTo(released[i - 1]), reason: 'released=$released');
      expect(released[i] - released[i - 1], lessThan(40), reason: 'released=$released');
    }
    expect(released.last, closeTo(0, 2));
  });
}
