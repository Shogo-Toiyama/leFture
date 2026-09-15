import 'package:flutter_test/flutter_test.dart';
import 'package:lefture/core/utils/text_preview.dart';

void main() {
  group('plainTextPreview web citations', () {
    test('removes double bracket web citations', () {
      final input = 'Did you know meat stalls at 160°F⟦1⟧ due to cooling⟦1, 2⟧?';
      final result = plainTextPreview(input);
      expect(result, 'Did you know meat stalls at 160°F due to cooling?');
    });

    test('removes bracket variations', () {
      final input = 'Point A〚2〛 and Point B[[3]] done.';
      final result = plainTextPreview(input);
      expect(result, 'Point A and Point B done.');
    });

    test('retains regular text without citations', () {
      final input = 'Regular sentence without any bracket.';
      final result = plainTextPreview(input);
      expect(result, 'Regular sentence without any bracket.');
    });
  });
}
