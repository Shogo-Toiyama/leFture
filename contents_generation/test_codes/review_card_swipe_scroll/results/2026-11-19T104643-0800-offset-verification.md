# Review Cards vertical offset during navigation

The verification ran the production viewer and the installed Flutter 3.50.0
dependencies from an isolated copy. The two content cards were synthetic
fixtures delivered through Riverpod provider overrides. A newly opened card
starts at zero. Revisiting a card in the same viewer restores its last offset.

| Variant | Before drag → first drag frame → after cancel | Progress bar tapped during vertical fling (Android / iOS) | Regression tests |
| --- | --- | --- | --- |
| Original | 200 → 0 → 0 px | 116.82 → 0 px / 114.36 → 0 px | 0/4 passed |
| Card-specific `PageStorageKey` | 200 → 200 → 200 px | 116.82 → 0 px / 114.36 → 0 px | 2/4 passed |
| Card-specific offsets recorded as the scroll moves | 200 → 200 → 200 px | 116.82 → 116.82 px / 114.36 → 114.36 px | 4/4 passed |

The swipe test also releases a short drag, commits a forward and a backward
swipe, checks a new card starts at zero, and confirms that two previously
visited cards retain their independent 200 px and 100 px offsets. The fling
test confirms that vertical movement is still active before tapping the
progress bar.

Flutter's default PageStorage writes an offset when scrolling ends. The
proposed patch stores offsets in viewer memory keyed by card ID as they change
and supplies the last value to each remounted card's `ScrollController`.
Offsets are clamped to the scroll extent when saved. Reference:
[Flutter ScrollController.keepScrollOffset](https://api.flutter.dev/flutter/widgets/ScrollController/keepScrollOffset.html).

The proposed patch and the existing navigation/image suite passed together
(8/8 tests; the Flutter test runner reached completion at 00:03). The
targeted analyzer reported the existing Material import deprecation as an
info and reported no errors or warnings. No external API calls, LLM tokens,
or API charges were incurred. The Android and iOS variants ran in the Flutter
widget test engine. Physical-device behavior was not measured.

The production source stayed untouched. The tested change is in
`../review_card_scroll_offset.patch`, which passes `git apply --check` from
the repository root. With the patch applied in an isolated copy, run from
its Flutter project root:

```sh
flutter test --no-pub --reporter expanded \
  ../contents_generation/test_codes/review_card_swipe_scroll/review_card_swipe_scroll_test.dart \
  ../contents_generation/test_codes/review_card_navigation_images/review_card_navigation_images_test.dart
```
