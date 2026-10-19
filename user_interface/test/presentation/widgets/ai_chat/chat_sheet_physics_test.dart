import 'package:flutter_test/flutter_test.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_sheet_physics.dart';

void main() {
  group('つまみのタップ', () {
    test('50%以下なら80%に開く', () {
      expect(ChatSheetPhysics.afterTap(.3), .8);
      expect(ChatSheetPhysics.afterTap(.5), .8);
      expect(ChatSheetPhysics.afterTap(.15), .8);
    });

    test('50%より高ければ30%に下げる', () {
      expect(ChatSheetPhysics.afterTap(.51), .3);
      expect(ChatSheetPhysics.afterTap(.8), .3);
      expect(ChatSheetPhysics.afterTap(1.0), .3);
    });
  });

  group('指を離したとき', () {
    test('ゆっくり離したら、その位置で止まる(どの高さでも)', () {
      for (final f in [.2, .3, .47, .8, .93]) {
        expect(releaseChatSheet(f, 0), isA<ChatSheetStay>());
        expect(releaseChatSheet(f, 400), isA<ChatSheetStay>());
        expect(releaseChatSheet(f, -400), isA<ChatSheetStay>());
      }
    });

    test('素早く上へ → 100%', () {
      final r = releaseChatSheet(.4, -1500) as ChatSheetMoveTo;
      expect(r.fraction, 1.0);
    });

    test('素早く下へ → 閉じる。100%からでも閉じる', () {
      expect(releaseChatSheet(.5, 1500), isA<ChatSheetClose>());
      expect(releaseChatSheet(1.0, 1500), isA<ChatSheetClose>());
    });

    test('15%より下で離したら閉じる。15%以上なら止まる', () {
      expect(releaseChatSheet(.14, 0), isA<ChatSheetClose>());
      expect(releaseChatSheet(.15, 0), isA<ChatSheetStay>());
    });

    test('低い位置から素早く上なら、閉じずに100%へ', () {
      expect(releaseChatSheet(.1, -2000), isA<ChatSheetMoveTo>());
    });
  });

  test('指で動かしている間は0〜100%に収める', () {
    expect(ChatSheetPhysics.clampWhileDragging(-.2), 0);
    expect(ChatSheetPhysics.clampWhileDragging(1.4), 1);
    expect(ChatSheetPhysics.clampWhileDragging(.42), .42);
  });
}
