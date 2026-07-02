import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:lecture_companion_ui/application/lecture/lecture_providers.dart';
import 'package:lecture_companion_ui/domain/entities/lecture.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';
import 'package:lecture_companion_ui/presentation/widgets/recording_timer_chip.dart';
import 'package:lecture_companion_ui/app/routes.dart';

class LectureViewerPage extends HookConsumerWidget {
  const LectureViewerPage({
    super.key,
    required this.lectureId,
  });

  final String lectureId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDummy = lectureId.startsWith('dummy_');
    
    // Panel States
    final isExpanded = useState(false);
    final currentTab = useState(0); // 0: Cards, 1: Notes, 2: Transcript
    final currentCardIndex = useState<int>(0);
    final selectedNoteIndex = useState<int?>(null);

    if (isDummy) {
      final dummyLecture = Lecture(
        id: lectureId,
        userId: 'dummy_user',
        courseId: 'dummy_course',
        title: 'Introduction to OOP & Classes',
        isDeleted: false,
        sortOrder: 0,
        lectureDatetime: DateTime.now().subtract(const Duration(days: 2)),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      return _buildViewerBody(
        context: context,
        lecture: dummyLecture,
        isExpanded: isExpanded,
        currentTab: currentTab,
        currentCardIndex: currentCardIndex,
        selectedNoteIndex: selectedNoteIndex,
      );
    }

    final lectureAsync = ref.watch(lectureProvider(lectureId));

    return lectureAsync.when(
      loading: () => Scaffold(backgroundColor: AppColors.universe.voidBackground, body: const Center(child: CircularProgressIndicator(color: AppColors.starGold))),
      error: (err, stack) => Scaffold(backgroundColor: AppColors.universe.voidBackground, body: Center(child: Text('Error: $err', style: const TextStyle(color: AppColors.correctionRed)))),
      data: (lecture) {
        if (lecture == null) {
          return Scaffold(backgroundColor: AppColors.universe.voidBackground, body: const Center(child: Text('Lecture not found', style: TextStyle(color: Colors.white))));
        }

        return _buildViewerBody(
          context: context,
          lecture: lecture,
          isExpanded: isExpanded,
          currentTab: currentTab,
          currentCardIndex: currentCardIndex,
          selectedNoteIndex: selectedNoteIndex,
        );
      },
    );
  }

  Widget _buildViewerBody({
    required BuildContext context,
    required Lecture lecture,
    required ValueNotifier<bool> isExpanded,
    required ValueNotifier<int> currentTab,
    required ValueNotifier<int> currentCardIndex,
    required ValueNotifier<int?> selectedNoteIndex,
  }) {
    useEffect(() {
      if (isExpanded.value) {
        if (currentTab.value == 1 && selectedNoteIndex.value == null) {
          selectedNoteIndex.value = 0;
        }
      } else {
        selectedNoteIndex.value = null;
      }
      return null;
    }, [isExpanded.value, currentTab.value]);

    final headerHeight = useState<double>(280.0);
    final screenHeight = MediaQuery.of(context).size.height;
    
    final collapsedTopOffset = headerHeight.value+20;
    final topOffset = isExpanded.value ? 0.0 : collapsedTopOffset;
    final panelHeight = isExpanded.value ? screenHeight : screenHeight - collapsedTopOffset;

    final dateStr = DateFormat.yMMMd().format(lecture.lectureDatetime);
    final timeStr = DateFormat.Hm().format(lecture.lectureDatetime);

    return Scaffold(
      backgroundColor: AppColors.universe.voidBackground,
      body: Stack(
        children: [
          // 1. Background Content (Header)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _MeasureSize(
              onChange: (size) {
                if (headerHeight.value != size.height) {
                  headerHeight.value = size.height;
                }
              },
              child: _buildBackgroundContent(context, lecture, dateStr, timeStr),
            ),
          ),

          // 2. Slidable Foreground Panel
          AnimatedPositioned(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutCubic,
            top: topOffset,
            left: 0,
            right: 0,
            height: panelHeight,
            child: GestureDetector(
              onVerticalDragUpdate: (details) {
                if (details.delta.dy < -5 && !isExpanded.value) {
                  isExpanded.value = true;
                } else if (details.delta.dy > 5 && isExpanded.value) {
                  isExpanded.value = false;
                }
              },
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.universe.glassWhiteLow,
                  border: isExpanded.value ? null : Border(top: BorderSide(color: AppColors.universe.glassBorder)),
                  borderRadius: isExpanded.value 
                      ? BorderRadius.zero 
                      : const BorderRadius.vertical(top: Radius.circular(32)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Tab Header Area
                    _buildPanelHeader(
                      context: context,
                      isExpanded: isExpanded.value, 
                      currentTab: currentTab,
                      onToggleExpand: () {
                        isExpanded.value = !isExpanded.value;
                      },
                    ),
                    // Panel Content Area
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: _buildPanelContent(
                          currentTab: currentTab.value,
                          isExpanded: isExpanded.value,
                          currentCardIndex: currentCardIndex,
                          selectedNoteIndex: selectedNoteIndex,
                          onExpand: () => isExpanded.value = true,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackgroundContent(BuildContext context, Lecture lecture, String dateStr, String timeStr) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Custom Home-style AppBar with Back button
        const _LectureAppBar(),
        
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Date & Time
              Text(
                '$dateStr • $timeStr',
                style: TextStyle(
                  color: AppColors.universe.textComet,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 4),

              // Title
              Text(
                lecture.title?.isNotEmpty == true ? lecture.title! : 'Untitled Lecture',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  height: 1.2,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),

              // Summary Section (directly written)
              Text(
                'This lecture covers the fundamental concepts of Object-Oriented Programming, specifically focusing on classes and their instantiation into objects.',
                style: TextStyle(
                  color: AppColors.universe.textStarlight,
                  fontSize: 13,
                  height: 1.4,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPanelHeader({
    required BuildContext context,
    required bool isExpanded, 
    required ValueNotifier<int> currentTab,
    required VoidCallback onToggleExpand,
  }) {
    final safeTop = MediaQuery.of(context).padding.top;
    return Container(
      color: isExpanded ? AppColors.universe.voidBackground : Colors.transparent,
      padding: EdgeInsets.only(
        top: isExpanded ? safeTop + 16.0 : 16.0, 
        bottom: 8.0,
      ),
      child: Column(
        children: [
          // Up indicator (only when collapsed)
          if (!isExpanded)
            GestureDetector(
              onTap: onToggleExpand,
              child: Icon(Icons.keyboard_arrow_up, color: AppColors.universe.textComet, size: 28),
            ),
          
          if (!isExpanded) const SizedBox(height: 8),

          // Tabs
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _TabItem(title: 'Review Cards', index: 0, currentTab: currentTab, isExpanded: isExpanded),
              const SizedBox(width: 8),
              _TabItem(title: 'Deep Notes', index: 1, currentTab: currentTab, isExpanded: isExpanded),
              const SizedBox(width: 8),
              _TabItem(title: 'Transcript', index: 2, currentTab: currentTab, isExpanded: isExpanded),
            ],
          ),

          // Down indicator (only when expanded)
          if (isExpanded)
            GestureDetector(
              onTap: onToggleExpand,
              child: Padding(
                padding: const EdgeInsets.only(top: 16.0),
                child: Icon(Icons.keyboard_arrow_down, color: AppColors.universe.textComet, size: 28),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPanelContent({
    required int currentTab,
    required bool isExpanded,
    required ValueNotifier<int> currentCardIndex,
    required ValueNotifier<int?> selectedNoteIndex,
    required VoidCallback onExpand,
  }) {
    if (currentTab == 0) {
      return _ReviewCardsView(
        key: const ValueKey('tab_0'),
        isExpanded: isExpanded,
        currentCardIndex: currentCardIndex,
        onExpand: onExpand,
      );
    } else if (currentTab == 1) {
      return _DeepNotesView(
        key: const ValueKey('tab_1'),
        isExpanded: isExpanded,
        selectedNoteIndex: selectedNoteIndex,
        onExpand: onExpand,
      );
    } else {
      return const _TranscriptView(
        key: ValueKey('tab_2'),
      );
    }
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.title,
    required this.index,
    required this.currentTab,
    required this.isExpanded,
  });

  final String title;
  final int index;
  final ValueNotifier<int> currentTab;
  final bool isExpanded;

  @override
  Widget build(BuildContext context) {
    final isActive = currentTab.value == index;
    
    if (isExpanded) {
      // Expanded: Subtle, flat design
      return GestureDetector(
        onTap: () => currentTab.value = index,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            border: isActive ? const Border(bottom: BorderSide(color: AppColors.starGold, width: 2)) : null,
          ),
          child: Text(
            title,
            style: TextStyle(
              color: isActive ? AppColors.starGold : AppColors.universe.textComet,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              fontSize: 14,
            ),
          ),
        ),
      );
    } else {
      // Collapsed: Prominent, button-like design
      return GestureDetector(
        onTap: () => currentTab.value = index,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: isActive ? AppColors.starGold.withValues(alpha: 0.15) : AppColors.universe.glassWhiteLow,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isActive ? AppColors.starGold : AppColors.universe.glassBorder,
            ),
          ),
          child: Text(
            title,
            style: TextStyle(
              color: isActive ? AppColors.starGold : AppColors.universe.textStarlight,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
      );
    }
  }
}

// Global Dummy Data matching 5 Topics, with summaries and 4 cards each.
final dummyTopics = [
  {
    'title': '1. OOP Basics',
    'summary': 'Introduces classes, objects, and the core differences between structured and object-oriented programming.',
    'cards': [
      {'q': 'What is a Class?', 'a': 'A blueprint for creating objects, defining their properties and behaviors.'},
      {'q': 'What is an Object?', 'a': 'An instance of a class containing actual values.'},
      {'q': 'State vs Behavior?', 'a': 'State represents the data (fields) of an object; behavior represents actions (methods) it can perform.'},
      {'q': 'Instantiation?', 'a': 'The process of creating an instance (object) of a class.'},
    ]
  },
  {
    'title': '2. Class Syntax in Python',
    'summary': 'Covers how to define a class, add attributes, and instantiate them in Python.',
    'cards': [
      {'q': 'class keyword?', 'a': 'Used to define a new user-defined class.'},
      {'q': 'Instance attribute?', 'a': 'Variables that belong to a specific object, defined typically in __init__.'},
      {'q': 'How to instantiate?', 'a': 'Call the class name as if it were a function: my_obj = MyClass().'},
      {'q': 'Class attributes?', 'a': 'Variables shared by all instances of a class.'},
    ]
  },
  {
    'title': '3. Constructors & __init__',
    'summary': 'Deep dive into the initialization method of Python classes, default values, and setup.',
    'cards': [
      {'q': 'What is __init__?', 'a': 'A special method (constructor) called automatically when a class instance is created.'},
      {'q': 'Purpose of self?', 'a': 'Represents the specific instance of the class being created or modified.'},
      {'q': 'Can __init__ return values?', 'a': 'No, it always implicitly returns None.'},
      {'q': 'Default arguments?', 'a': 'Can define parameters in __init__ with default values for flexible instantiation.'},
    ]
  },
  {
    'title': '4. Methods & self',
    'summary': 'Explains instance methods, why self is required as the first argument, and method calls.',
    'cards': [
      {'q': 'Instance method?', 'a': 'A function defined inside a class that takes self as its first parameter.'},
      {'q': 'Why is self needed?', 'a': 'To access other attributes or methods on the same object.'},
      {'q': 'Calling methods?', 'a': 'Use dot notation on the object: object.method().'},
      {'q': 'Static methods?', 'a': 'Methods that don\'t access instance or class state, decorated with @staticmethod.'},
    ]
  },
  {
    'title': '5. Advanced OOP Features',
    'summary': 'A glance at inheritance, method overriding, and polymorphism in Python.',
    'cards': [
      {'q': 'Inheritance syntax?', 'a': 'class ChildClass(ParentClass):'},
      {'q': 'Method Overriding?', 'a': 'Defining a method in the child class with the same name as one in the parent class.'},
      {'q': 'super() function?', 'a': 'Used to delegate method calls to a parent class.'},
      {'q': 'Polymorphism?', 'a': 'The ability of different classes to respond to the same method call in their own ways.'},
    ]
  }
];

// ---------------------------------------------------------------------------
// 1. Review Cards View
// ---------------------------------------------------------------------------
class _ReviewCardsView extends HookWidget {
  const _ReviewCardsView({
    super.key,
    required this.isExpanded,
    required this.currentCardIndex,
    required this.onExpand,
  });

  final bool isExpanded;
  final ValueNotifier<int> currentCardIndex;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    final animationController = useAnimationController(
      duration: const Duration(milliseconds: 350),
    );
    useAnimation(animationController);

    final previousCardIndex = useState<int>(currentCardIndex.value);
    final isAnimating = useState<bool>(false);
    final isGoingForward = useState<bool>(true);

    const totalCards = 20;
    final screenWidth = MediaQuery.of(context).size.width;

    final navigateTo = useCallback((int newIndex, {bool immediate = false}) {
      if (isAnimating.value || newIndex == currentCardIndex.value) return;
      if (immediate) {
        currentCardIndex.value = newIndex;
        previousCardIndex.value = newIndex;
        return;
      }
      previousCardIndex.value = currentCardIndex.value;
      isGoingForward.value = newIndex > currentCardIndex.value;
      currentCardIndex.value = newIndex;
      isAnimating.value = true;
      animationController.forward(from: 0.0).then((_) {
        isAnimating.value = false;
        previousCardIndex.value = newIndex;
      });
    }, [currentCardIndex.value, isAnimating.value]);

    Widget buildCard(int cardIdx) {
      final tIdx = cardIdx ~/ 4;
      final cIdxInTopic = cardIdx % 4;
      final cTopic = dummyTopics[tIdx];
      final cList = cTopic['cards'] as List<Map<String, String>>;
      final cardData = cList[cIdxInTopic];

      return Container(
        decoration: BoxDecoration(
          color: AppColors.universe.glassWhiteLow,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.universe.glassBorder, width: 1.5),
          boxShadow: const [
            BoxShadow(
              color: Colors.black38,
              blurRadius: 16,
              offset: Offset(0, 8),
            ),
          ],
        ),
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.lightbulb_outline,
              color: AppColors.starGold,
              size: 56,
            ),
            const SizedBox(height: 32),
            Text(
              cardData['q']!,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Text(
              cardData['a']!,
              style: TextStyle(
                color: AppColors.universe.textStarlight.withValues(alpha: 0.8),
                fontSize: 15,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    if (!isExpanded) {
      // Collapsed State: Card Dashboard (Start button + Horizontal Scroll Rows)
      return ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: dummyTopics.length + 1,
        separatorBuilder: (_, __) => const SizedBox(height: 24),
        itemBuilder: (context, topicIdx) {
          if (topicIdx == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: GestureDetector(
                onTap: () {
                  navigateTo(0, immediate: true);
                  onExpand();
                },
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.starGold, Color(0xFFFFD700)],
                    ),
                    borderRadius: BorderRadius.circular(26),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.starGold.withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.play_circle_fill, color: AppColors.universe.voidBackground, size: 24),
                      const SizedBox(width: 8),
                      Text(
                        'Start Review Session!',
                        style: TextStyle(
                          color: AppColors.universe.voidBackground,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          final topic = dummyTopics[topicIdx - 1];
          final cards = topic['cards'] as List<Map<String, String>>;
          
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Topic Header
              Text(
                topic['title'] as String,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 10),
              
              // Horizontally scrollable vertical-oriented cards
              SizedBox(
                height: 150,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: cards.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, cardIdx) {
                    final card = cards[cardIdx];
                    return GestureDetector(
                      onTap: () {
                        navigateTo((topicIdx - 1) * 4 + cardIdx, immediate: true);
                        onExpand();
                      },
                      child: Container(
                        width: 110,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.universe.voidBackground.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.universe.glassBorder),
                        ),
                        child: Center(
                          child: Text(
                            card['q']!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 5,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      );
    }

    // Expanded State: Immersive Instagram Stories-style Card Viewer
    final index = currentCardIndex.value.clamp(0, totalCards - 1);
    final topicIndex = index ~/ 4;
    final cardIndexInTopic = index % 4;

    final topic = dummyTopics[topicIndex];

    return Container(
      color: AppColors.universe.voidBackground,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Topic Title above the card
          Text(
            topic['title'] as String,
            style: const TextStyle(
              color: AppColors.starGold,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),

          // 2. Stories Progress Indicators (4 bars)
          Row(
            children: List.generate(4, (i) {
              final isFilled = i <= cardIndexInTopic;
              return Expanded(
                child: Container(
                  height: 4,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: isFilled ? AppColors.starGold : Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 20),

          // 3. Card & Tap Detection Stack
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragEnd: (details) {
                if (details.primaryVelocity == null) return;
                // Swipe Left (velocity < -300) -> Next Topic
                if (details.primaryVelocity! < -300) {
                  final currentTopicIndex = currentCardIndex.value ~/ 4;
                  if (currentTopicIndex < 4) {
                    navigateTo((currentTopicIndex + 1) * 4);
                  }
                }
                // Swipe Right (velocity > 300) -> Previous Topic
                else if (details.primaryVelocity! > 300) {
                  final currentTopicIndex = currentCardIndex.value ~/ 4;
                  if (currentTopicIndex > 0) {
                    navigateTo((currentTopicIndex - 1) * 4);
                  }
                }
              },
              child: Stack(
                children: [
                  // Animated Card Stack
                  Positioned.fill(
                    child: Builder(
                      builder: (context) {
                        if (isAnimating.value) {
                          final progress = animationController.value;
                          if (isGoingForward.value) {
                            return Stack(
                              children: [
                                Positioned.fill(
                                  child: Transform.scale(
                                    scale: 0.92 + (0.08 * progress),
                                    child: Opacity(
                                      opacity: 0.5 + (0.5 * progress),
                                      child: buildCard(currentCardIndex.value),
                                    ),
                                  ),
                                ),
                                Positioned.fill(
                                  child: Transform.translate(
                                    offset: Offset(-progress * screenWidth, 0),
                                    child: Transform.rotate(
                                      angle: -progress * 0.2,
                                      alignment: Alignment.bottomCenter,
                                      child: buildCard(previousCardIndex.value),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          } else {
                            return Stack(
                              children: [
                                Positioned.fill(
                                  child: buildCard(previousCardIndex.value),
                                ),
                                Positioned.fill(
                                  child: Transform.translate(
                                    offset: Offset(-(1.0 - progress) * screenWidth, 0),
                                    child: Transform.rotate(
                                      angle: -(1.0 - progress) * 0.2,
                                      alignment: Alignment.bottomCenter,
                                      child: buildCard(currentCardIndex.value),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }
                        } else {
                          return buildCard(currentCardIndex.value);
                        }
                      },
                    ),
                  ),

                  // Left Tap detector (30% width)
                  Positioned(
                    top: 0,
                    bottom: 0,
                    left: 0,
                    width: (screenWidth - 32) * 0.3,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        if (currentCardIndex.value > 0) {
                          navigateTo(currentCardIndex.value - 1);
                        }
                      },
                    ),
                  ),

                  // Right Tap detector (70% width)
                  Positioned(
                    top: 0,
                    bottom: 0,
                    right: 0,
                    width: (screenWidth - 32) * 0.7,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        if (currentCardIndex.value < totalCards - 1) {
                          navigateTo(currentCardIndex.value + 1);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 2. Deep Notes View
// ---------------------------------------------------------------------------
class _DeepNotesView extends HookWidget {
  const _DeepNotesView({
    super.key,
    required this.isExpanded,
    required this.selectedNoteIndex,
    required this.onExpand,
  });

  final bool isExpanded;
  final ValueNotifier<int?> selectedNoteIndex;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    if (selectedNoteIndex.value == null) {
      // List of note tiles with full summary
      return ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: dummyTopics.length,
        separatorBuilder: (_, __) => const SizedBox(height: 16),
        itemBuilder: (context, index) {
          final topic = dummyTopics[index];
          return GestureDetector(
            onTap: () {
              selectedNoteIndex.value = index;
              onExpand();
            },
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.universe.voidBackground.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.universe.glassBorder),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          topic['title'] as String,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          topic['summary'] as String,
                          style: TextStyle(
                            color: AppColors.universe.textStarlight.withValues(alpha: 0.8),
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Icon(Icons.chevron_right, color: AppColors.starGold, size: 24),
                ],
              ),
            ),
          );
        },
      );
    }

    // Expanded Markdown Detail View with scroll transition arrows (restricted to edge starts)
    final scrollController = useScrollController();
    final isTransitioning = useState(false);
    
    // Markers to track where scroll gestures start
    final startedAtTop = useState(false);
    final startedAtBottom = useState(false);
    
    final topic = dummyTopics[selectedNoteIndex.value!];

    void nextNote() {
      if (isTransitioning.value) return;
      if (selectedNoteIndex.value! < dummyTopics.length - 1) {
        isTransitioning.value = true;
        selectedNoteIndex.value = selectedNoteIndex.value! + 1;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (scrollController.hasClients) {
            scrollController.jumpTo(0.0);
          }
          isTransitioning.value = false;
        });
      }
    }

    void prevNote() {
      if (isTransitioning.value) return;
      if (selectedNoteIndex.value! > 0) {
        isTransitioning.value = true;
        selectedNoteIndex.value = selectedNoteIndex.value! - 1;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (scrollController.hasClients) {
            scrollController.jumpTo(0.0);
          }
          isTransitioning.value = false;
        });
      }
    }

    return Container(
      color: AppColors.universe.voidBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (isTransitioning.value) return false;
                
                // Track where scroll starts
                if (notification is ScrollStartNotification) {
                  final metrics = notification.metrics;
                  startedAtTop.value = metrics.pixels <= 0.0;
                  startedAtBottom.value = metrics.pixels >= metrics.maxScrollExtent;
                }
                
                // Reset on scroll end
                if (notification is ScrollEndNotification) {
                  startedAtTop.value = false;
                  startedAtBottom.value = false;
                }
                
                // Trigger transitions on overscroll ONLY if scroll started at the boundary
                if (notification is ScrollUpdateNotification) {
                  final metrics = notification.metrics;
                  if (startedAtBottom.value && metrics.pixels >= metrics.maxScrollExtent + 50 && selectedNoteIndex.value! < dummyTopics.length - 1) {
                    nextNote();
                  }
                  if (startedAtTop.value && metrics.pixels <= metrics.minScrollExtent - 50 && selectedNoteIndex.value! > 0) {
                    prevNote();
                  }
                }
                return false;
              },
              child: ListView(
                controller: scrollController,
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                children: [
                  // Upper Arrow indicator (if previous note exists)
                  if (selectedNoteIndex.value! > 0)
                    Center(
                      child: Column(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.keyboard_arrow_up, color: AppColors.starGold, size: 28),
                            onPressed: prevNote,
                          ),
                          const Text(
                            'Pull or tap to previous note',
                            style: TextStyle(color: Colors.white30, fontSize: 11),
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),

                  Text(
                    topic['title'] as String,
                    style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    topic['summary'] as String,
                    style: TextStyle(color: AppColors.universe.textComet, fontSize: 15, fontStyle: FontStyle.italic),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'A class is a user-defined blueprint or prototype from which objects are created. Classes provide a means of bundling data and functionality together.\n\nCreating a new class creates a new type of object, allowing new instances of that type to be made. Each class instance can have attributes attached to it for maintaining its state. Class instances can also have methods (defined by its class) for modifying its state.',
                    style: TextStyle(color: AppColors.universe.textStarlight, fontSize: 16, height: 1.6),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.universe.glassBorder),
                    ),
                    child: const Text(
                      'class Dog:\n    def __init__(self, name):\n        self.name = name\n\n    def bark(self):\n        print(f"{self.name} says woof!")',
                      style: TextStyle(color: Colors.greenAccent, fontFamily: 'monospace', fontSize: 14, height: 1.5),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Lower Arrow indicator (if next note exists)
                  if (selectedNoteIndex.value! < dummyTopics.length - 1)
                    Center(
                      child: Column(
                        children: [
                          const SizedBox(height: 16),
                          IconButton(
                            icon: const Icon(Icons.keyboard_arrow_down, color: AppColors.starGold, size: 28),
                            onPressed: nextNote,
                          ),
                          const Text(
                            'Pull or tap to next note',
                            style: TextStyle(color: Colors.white30, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 3. Transcript View
// ---------------------------------------------------------------------------
class _TranscriptView extends StatelessWidget {
  const _TranscriptView({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.universe.voidBackground,
      child: ListView.separated(
        padding: const EdgeInsets.all(24),
        itemCount: 10,
        separatorBuilder: (_, __) => const SizedBox(height: 24),
        itemBuilder: (context, index) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '10:04',
                style: TextStyle(color: AppColors.starGold, fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  'This is a generated transcript snippet for the lecture. At this point, the professor is explaining the core concepts in detail. Pay attention to the syntax used here.',
                  style: TextStyle(color: AppColors.universe.textStarlight, fontSize: 14, height: 1.5),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LectureAppBar extends StatelessWidget {
  const _LectureAppBar();

  @override
  Widget build(BuildContext context) {
    final safeTop = MediaQuery.of(context).padding.top;
    return Padding(
      padding: EdgeInsets.only(top: safeTop, left: 16, right: 16, bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => context.pop(),
              ),
              const SizedBox(width: 8),
              const RecordingTimerChip(),
            ],
          ),
          GestureDetector(
            onTap: () => context.push(AppRoutes.profile),
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(
                    value: 0.7,
                    strokeWidth: 3,
                    backgroundColor: AppColors.universe.glassWhiteLow,
                    valueColor: const AlwaysStoppedAnimation<Color>(AppColors.starGold),
                  ),
                ),
                Container(
                  width: 28,
                  height: 28,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                  ),
                  child: const Icon(Icons.person, color: Colors.grey, size: 20),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}

class _MeasureSize extends StatefulWidget {
  final Widget child;
  final OnWidgetSizeChange onChange;

  const _MeasureSize({
    required this.onChange,
    required this.child,
  });

  @override
  _MeasureSizeState createState() => _MeasureSizeState();
}

typedef OnWidgetSizeChange = void Function(Size size);

class _MeasureSizeState extends State<_MeasureSize> {
  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final box = context.findRenderObject() as RenderBox?;
        if (box != null && box.hasSize) {
          widget.onChange(box.size);
        }
      }
    });
    return widget.child;
  }
}