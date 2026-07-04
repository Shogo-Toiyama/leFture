import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
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
    final selectedText = useState<String?>(null);

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
        selectedText: selectedText,
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
          selectedText: selectedText,
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
    required ValueNotifier<String?> selectedText,
  }) {
    final paperTheme = ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.paper.background,
      colorScheme: ColorScheme.light(
        surface: AppColors.paper.surface,
        onSurface: AppColors.paper.textInk,
        onSurfaceVariant: AppColors.paper.textPencil,
        primary: AppColors.deepGold,
      ),
      textTheme: TextTheme(
        bodyLarge: TextStyle(color: AppColors.paper.textInk),
        bodyMedium: TextStyle(color: AppColors.paper.textInk),
        titleLarge: TextStyle(color: AppColors.paper.textInk, fontWeight: FontWeight.bold),
        titleMedium: TextStyle(color: AppColors.paper.textInk, fontWeight: FontWeight.bold),
        labelSmall: TextStyle(color: AppColors.paper.textPencil),
      ),
    );

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

    useEffect(() {
      selectedText.value = null;
      return null;
    }, [currentTab.value, isExpanded.value, selectedNoteIndex.value]);

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
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  color: isExpanded.value
                      ? AppColors.paper.background
                      : AppColors.paper.background.withValues(alpha: 0.5),
                  border: isExpanded.value ? null : Border(top: BorderSide(color: AppColors.universe.glassBorder)),
                  borderRadius: isExpanded.value 
                      ? BorderRadius.zero 
                      : const BorderRadius.vertical(top: Radius.circular(32)),
                ),
                child: Theme(
                  data: paperTheme,
                  child: Stack(
                    children: [
                      Column(
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
                                selectedText: selectedText,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (isExpanded.value && selectedText.value != null && selectedText.value!.isNotEmpty)
                        Positioned(
                          top: MediaQuery.of(context).padding.top + 104.0,
                          left: 16,
                          right: 16,
                          child: Builder(
                            builder: (context) {
                              final isDark = Theme.of(context).brightness == Brightness.dark;
                              return Container(
                                height: 46,
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? AppColors.universe.voidBackground.withValues(alpha: 0.92)
                                      : AppColors.paper.surface.withValues(alpha: 0.95),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isDark
                                        ? AppColors.universe.glassBorder
                                        : Colors.black.withValues(alpha: 0.08),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: isDark
                                          ? Colors.black.withValues(alpha: 0.4)
                                          : Colors.black.withValues(alpha: 0.06),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  physics: const BouncingScrollPhysics(),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.gesture, 
                                          color: isDark 
                                              ? AppColors.universe.textComet 
                                              : AppColors.paper.textPencil, 
                                          size: 16,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'テキストアクション',
                                          style: TextStyle(
                                            color: isDark 
                                                ? Colors.white70 
                                                : AppColors.paper.textPencil,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(width: 24),
                                        _ToolbarButton(
                                          icon: Icons.auto_awesome,
                                          label: 'AIに質問',
                                          color: AppColors.starGold,
                                          onTap: () {
                                            final text = selectedText.value;
                                            if (text != null && text.isNotEmpty) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                  backgroundColor: AppColors.universe.voidBackground,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius: BorderRadius.circular(6),
                                                    side: BorderSide(color: AppColors.universe.glassBorder),
                                                  ),
                                                  behavior: SnackBarBehavior.floating,
                                                  content: Text('AIに質問中: "$text"', style: const TextStyle(color: Colors.white)),
                                                ),
                                              );
                                              selectedText.value = null; // Close menu
                                            }
                                          },
                                        ),
                                        const SizedBox(width: 8),
                                        _ToolbarButton(
                                          icon: Icons.edit,
                                          label: 'マーカー',
                                          color: isDark ? Colors.white : AppColors.paper.textInk,
                                          onTap: () {
                                            final text = selectedText.value;
                                            if (text != null && text.isNotEmpty) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                  backgroundColor: AppColors.universe.voidBackground,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius: BorderRadius.circular(12),
                                                    side: BorderSide(color: AppColors.universe.glassBorder),
                                                  ),
                                                  behavior: SnackBarBehavior.floating,
                                                  content: Text('マーカーを追加: "$text"', style: const TextStyle(color: Colors.white)),
                                                ),
                                              );
                                              selectedText.value = null; // Close menu
                                            }
                                          },
                                        ),
                                        const SizedBox(width: 8),
                                        _ToolbarButton(
                                          icon: Icons.copy,
                                          label: 'コピー',
                                          color: isDark ? Colors.white : AppColors.paper.textInk,
                                          onTap: () {
                                            final text = selectedText.value;
                                            if (text != null && text.isNotEmpty) {
                                              Clipboard.setData(ClipboardData(text: text));
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                  backgroundColor: AppColors.universe.voidBackground,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius: BorderRadius.circular(12),
                                                    side: BorderSide(color: AppColors.universe.glassBorder),
                                                  ),
                                                  behavior: SnackBarBehavior.floating,
                                                  content: const Text('クリップボードにコピーしました', style: TextStyle(color: Colors.white)),
                                                ),
                                              );
                                              selectedText.value = null; // Close menu
                                            }
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
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
      decoration: isExpanded
          ? BoxDecoration(
              color: Color.lerp(AppColors.paper.background, AppColors.paper.textInk, 0.035),
              border: Border(
                bottom: BorderSide(color: Colors.black.withValues(alpha: 0.05)),
              ),
            )
          : null,
      padding: EdgeInsets.only(
        top: isExpanded ? safeTop + 16.0 : 16.0, 
        bottom: isExpanded ? 12.0 : 8.0,
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
                child: Icon(Icons.keyboard_arrow_down, color: AppColors.paper.textPencil, size: 28),
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
    required ValueNotifier<String?> selectedText,
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
        selectedText: selectedText,
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
            border: isActive ? Border(bottom: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2)) : null,
          ),
          child: Text(
            title,
            style: TextStyle(
              color: isActive ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              fontSize: 14,
            ),
          ),
        ),
      );
    } else {
      // Collapsed: Prominent, button-like design (styled for dark/transparent background)
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
    'content': '''Object-Oriented Programming (OOP) is a programming paradigm based on the concept of "objects", which can contain data and code. Data is in the form of fields (often known as attributes or properties), and code is in the form of procedures (often known as methods).

### What is a Class?
A class is a user-defined blueprint or prototype from which objects are created. Classes provide a means of bundling data and functionality together. Creating a new class creates a new type of object, allowing new instances of that type to be made. Each class instance can have attributes attached to it for maintaining its state. Class instances can also have methods (defined by its class) for modifying its state.

### What is an Object?
An object is an instance of a class. When a class is defined, no memory is allocated but when it is instantiated (i.e. an object is created), memory is allocated. Objects have state, behavior, and identity.

### Why OOP?
OOP makes it easier to model real-world concepts in code. It provides structure, reusability, and makes large codebases easier to maintain over time.

- **Modularity:** The source code for a class can be written and maintained independently of the source code for other classes.
- **Information hiding:** By interacting only with an object's methods, the details of its internal implementation remain hidden from the outside world.
- **Code re-use:** If a class already exists, you can use that class's objects in your program.
- **Easy debugging:** If a particular object is causing problems, you can simply remove it and try another.

```python
class Dog:
    # Class Attribute
    species = "Canis familiaris"

    def __init__(self, name, age):
        self.name = name
        self.age = age

    # Instance method
    def description(self):
        return f"{self.name} is {self.age} years old"

    # Another instance method
    def speak(self, sound):
        return f"{self.name} says {sound}"
```

### Let's see it in action:
Here is how you can instantiate the class and use its properties and methods:

```python
buddy = Dog("Buddy", 9)
miles = Dog("Miles", 4)

print(buddy.description())  # Output: Buddy is 9 years old
print(miles.speak("Woof"))  # Output: Miles says Woof
```''',
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
    'content': '''In Python, defining a class is straightforward. We use the `class` keyword followed by the class name. According to PEP 8 standards, class names should use CapWords (PascalCase) convention.

### Defining a Class
Here is how you can define a simple class with class attributes and instance attributes:

```python
class Car:
    # Class attribute (shared by all instances)
    wheels = 4
    
    def __init__(self, model, year, color):
        self.model = model  # Instance attribute
        self.year = year    # Instance attribute
        self.color = color  # Instance attribute
        self.odometer = 0   # Default attribute
```

### Instantiating an Object
To create an instance of a class, call the class name as if it were a function and pass the arguments that `__init__` expects:

```python
my_car = Car("Model 3", 2023, "Red")
print(my_car.model)  # Output: Model 3
print(my_car.wheels) # Output: 4
```

### Modifying Attributes
There are three ways to modify an attribute's value:
1. Modify the value directly through the instance.
2. Set the value through a method.
3. Increment the value through a method.

#### 1. Modifying an Attribute's Value Directly
```python
my_car.odometer = 23
print(my_car.odometer)  # Output: 23
```

#### 2. Modifying an Attribute's Value Through a Method
```python
class Car:
    # ... previous code ...
    def update_odometer(self, mileage):
        if mileage >= self.odometer:
            self.odometer = mileage
        else:
            print("You can't roll back an odometer!")
```''',
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
    'content': '''The `__init__` method is a special method in Python classes. It is run automatically as soon as an object of a class is instantiated. It is often referred to as the constructor, although technically it initializes an already created object.

### Purpose of __init__
It is used to initialize the object's attributes. It acts as the constructor of the class. It allows you to pass arguments when creating a new instance of a class, ensuring every instance starts with the necessary state.

### The `self` Parameter
The `self` parameter is a reference to the current instance of the class and is used to access variables that belong to the class. It does not have to be named `self`, but it is a strong convention in Python. Omitting `self` will result in a NameError or TypeError when trying to access instance variables.

### Multiple Constructors?
Unlike some other languages (like Java or C++), Python does not support multiple `__init__` methods directly (method overloading). If you define multiple `__init__` methods, the last one will overwrite the previous ones. However, you can achieve similar functionality using:
- Default arguments.
- Variable-length arguments (`*args`, `**kwargs`).
- Class methods as alternative constructors.

```python
class User:
    def __init__(self, username, email="default@example.com", role="Student"):
        self.username = username
        self.email = email
        self.role = role

    @classmethod
    def create_admin(cls, username):
        return cls(username, email=f"{username}@admin.com", role="Admin")

# Normal creation
student = User("alice")
# Admin creation using classmethod
admin = User.create_admin("bob")
```''',
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
    'content': '''Methods are functions defined inside the body of a class. They are used to define the behaviors of an object and can perform computations or alter the state of the object.

### Instance Methods
Instance methods are the most common type of method in Python classes. They must take `self` as their first argument. Through the `self` parameter, instance methods can freely access other attributes and other methods on the same object.

```python
class Calculator:
    def __init__(self, value=0):
        self.value = value
        
    def add(self, amount):
        self.value += amount
        return self.value

    def subtract(self, amount):
        self.value -= amount
        return self.value
```

### Why `self` is Required
When you call a method like `obj.method(amount)`, Python automatically translates it into `Class.method(obj, amount)`. The `self` parameter receives the instance object itself.

### Class Methods
Class methods are decorated with `@classmethod`. Instead of `self`, they take `cls` as the first parameter, which points to the class itself rather than an instance. They can modify class state that applies across all instances.

```python
class SchoolMember:
    total_members = 0

    def __init__(self):
        SchoolMember.increment_members()

    @classmethod
    def increment_members(cls):
        cls.total_members += 1
```

### Static Methods
If a method does not access instance or class state, we can use the `@staticmethod` decorator. They behave like plain functions but belong to the class's namespace.

```python
class MathUtils:
    @staticmethod
    def is_even(n):
        return n % 2 == 0
```''',
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
    'content': '''Python OOP supports advanced features such as inheritance, polymorphism, method overriding, and encapsulation.

### Inheritance
Inheritance allows us to define a class that inherits all the methods and properties from another class. The parent class is the class being inherited from, also called the base class. The child class is the class that inherits from another class, also called the derived class.

```python
class Animal:
    def __init__(self, name):
        self.name = name

    def speak(self):
        return "Some sound"
        
class Cat(Animal):
    def speak(self):
        return "Meow"
```

### Method Overriding
In the example above, `Cat` overrides the `speak` method of `Animal`. Method overriding allows a child class to provide a specific implementation of a method that is already provided by one of its superclasses.

### The `super()` Function
`super()` is used to call methods of the parent class. It is particularly useful in `__init__` to ensure the parent class is initialized correctly.

```python
class Dog(Animal):
    def __init__(self, name, breed):
        super().__init__(name)  # Initialize parent attributes
        self.breed = breed

    def speak(self):
        return f"{super().speak()} and Woof!"
```

### Polymorphism
Polymorphism is the ability of different classes to respond to the same method call in their own ways. For example, if you have a list of animals, you can call `.speak()` on all of them without knowing their specific subtype:

```python
animals = [Cat("Whiskers"), Dog("Rex", "German Shepherd")]
for animal in animals:
    print(f"{animal.name}: {animal.speak()}")
```''',
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

      final isDark = Theme.of(context).brightness == Brightness.dark;

      return Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.universe.glassWhiteLow : AppColors.paper.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isDark ? AppColors.universe.glassBorder : Colors.black.withValues(alpha: 0.08),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: isDark ? Colors.black38 : Colors.black.withValues(alpha: 0.05),
              blurRadius: 16,
              offset: const Offset(0, 8),
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
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
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
                color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
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
                style: TextStyle(
                  color: AppColors.paper.textInk,
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
                          color: AppColors.paper.background,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.03),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            card['q']!,
                            style: TextStyle(
                              color: AppColors.paper.textInk,
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

    final topic = dummyTopics[topicIndex];

    return Container(
      color: Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Topic Title above the card
          Text(
            topic['title'] as String,
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),

          // 2. Stories Progress Indicators (Grouped by Topic, 20 bars total)
          Row(
            children: List.generate(dummyTopics.length, (topicIdx) {
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    children: List.generate(4, (cardIdx) {
                      final absIdx = topicIdx * 4 + cardIdx;
                      final isFilled = absIdx <= currentCardIndex.value;
                      final isActive = absIdx == currentCardIndex.value;
                      
                      final isDark = Theme.of(context).brightness == Brightness.dark;
                      final activeColor = Theme.of(context).colorScheme.primary;
                      final filledColor = Theme.of(context).colorScheme.primary.withValues(alpha: 0.6);
                      final unfilledColor = isDark ? Colors.white12 : Colors.black12;

                      return Expanded(
                        child: Container(
                          height: 4,
                          margin: const EdgeInsets.symmetric(horizontal: 1.5),
                          decoration: BoxDecoration(
                            color: isActive 
                                ? activeColor 
                                : isFilled 
                                    ? filledColor 
                                    : unfilledColor,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      );
                    }),
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
                                  child: Transform.scale(
                                    scale: 1.0 - (0.08 * progress),
                                    child: Opacity(
                                      opacity: 1.0 - (0.5 * progress),
                                      child: buildCard(previousCardIndex.value),
                                    ),
                                  ),
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
    required this.selectedText,
  });

  final bool isExpanded;
  final ValueNotifier<int?> selectedNoteIndex;
  final VoidCallback onExpand;
  final ValueNotifier<String?> selectedText;

  @override
  Widget build(BuildContext context) {
    final shouldStartAtBottom = useState(false);
    final noteIndex = selectedNoteIndex.value;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: noteIndex == null
          ? _buildNoteList(context)
          : _NoteDetailView(
              key: ValueKey('note_detail_$noteIndex'),
              noteIndex: noteIndex,
              topic: dummyTopics[noteIndex],
              startAtBottom: shouldStartAtBottom.value,
              selectedText: selectedText,
              onNext: () {
                if (noteIndex < dummyTopics.length - 1) {
                  shouldStartAtBottom.value = false;
                  selectedNoteIndex.value = noteIndex + 1;
                }
              },
              onPrev: () {
                if (noteIndex > 0) {
                  shouldStartAtBottom.value = true;
                  selectedNoteIndex.value = noteIndex - 1;
                }
              },
            ),
    );
  }

  Widget _buildNoteList(BuildContext context) {
    return ListView.separated(
      key: const ValueKey('note_list'),
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
              color: AppColors.paper.background,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        topic['title'] as String,
                        style: TextStyle(
                          color: AppColors.paper.textInk,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        topic['summary'] as String,
                        style: TextStyle(
                          color: AppColors.paper.textPencil,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.primary, size: 24),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _NoteDetailView extends HookWidget {
  const _NoteDetailView({
    super.key,
    required this.noteIndex,
    required this.topic,
    required this.startAtBottom,
    required this.onNext,
    required this.onPrev,
    required this.selectedText,
  });

  final int noteIndex;
  final Map<String, dynamic> topic;
  final bool startAtBottom;
  final VoidCallback onNext;
  final VoidCallback onPrev;
  final ValueNotifier<String?> selectedText;

  @override
  Widget build(BuildContext context) {
    final scrollController = useScrollController();
    final isTransitioning = useState(false);
    
    // Markers to track where scroll gestures start
    final startedAtTop = useState(false);
    final startedAtBottom = useState(false);
    final shouldGoToNext = useState(false);
    final shouldGoToPrev = useState(false);

    // Jump to bottom if startAtBottom is true
    useEffect(() {
      if (startAtBottom) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (scrollController.hasClients) {
            scrollController.jumpTo(scrollController.position.maxScrollExtent);
          }
        });
      }
      return null;
    }, [noteIndex]);

    return Container(
      color: Colors.transparent,
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
                  shouldGoToNext.value = false;
                  shouldGoToPrev.value = false;
                }
                
                // Trigger transitions ONLY when the user releases their finger (dragDetails becomes null)
                if (notification is ScrollEndNotification || 
                    (notification is ScrollUpdateNotification && notification.dragDetails == null)) {
                  if (shouldGoToNext.value) {
                    shouldGoToNext.value = false;
                    shouldGoToPrev.value = false;
                    isTransitioning.value = true;
                    onNext();
                  } else if (shouldGoToPrev.value) {
                    shouldGoToNext.value = false;
                    shouldGoToPrev.value = false;
                    isTransitioning.value = true;
                    onPrev();
                  }
                }
                
                // Detect overscroll boundaries
                if (notification is ScrollUpdateNotification) {
                  final metrics = notification.metrics;
                  final isDragging = notification.dragDetails != null;
                  
                  if (isDragging) {
                    if (startedAtBottom.value && metrics.pixels >= metrics.maxScrollExtent + 50 && noteIndex < dummyTopics.length - 1) {
                      shouldGoToNext.value = true;
                    }
                    if (startedAtTop.value && metrics.pixels <= metrics.minScrollExtent - 50 && noteIndex > 0) {
                      shouldGoToPrev.value = true;
                    }

                    // Reset page turn intent if user scrolls back before releasing
                    if (shouldGoToNext.value && metrics.pixels < metrics.maxScrollExtent + 10) {
                      shouldGoToNext.value = false;
                    }
                    if (shouldGoToPrev.value && metrics.pixels > metrics.minScrollExtent - 10) {
                      shouldGoToPrev.value = false;
                    }
                  }
                }
                
                if (notification is ScrollEndNotification) {
                  startedAtTop.value = false;
                  startedAtBottom.value = false;
                }
                return false;
              },
              child: SelectionArea(
                onSelectionChanged: (content) {
                  selectedText.value = content?.plainText;
                },
                contextMenuBuilder: (context, selectableRegionState) {
                  return const SizedBox.shrink(); // Suppress standard OS selection menu
                },
                child: ListView(
                  controller: scrollController,
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  children: [
                    // Upper Arrow indicator (if previous note exists)
                    if (noteIndex > 0)
                      Center(
                        child: Column(
                          children: [
                            IconButton(
                              icon: Icon(Icons.keyboard_arrow_up, color: Theme.of(context).colorScheme.primary, size: 28),
                              onPressed: onPrev,
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
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      topic['summary'] as String,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 15,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(height: 24),
                    MarkdownBody(
                      data: topic['content'] as String? ?? '',
                      selectable: false,
                      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                        p: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 16,
                          height: 1.6,
                        ),
                        h1: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                        h2: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                        h3: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        listBullet: TextStyle(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? AppColors.starGold
                              : AppColors.deepGold,
                          fontSize: 16,
                        ),
                        code: TextStyle(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.greenAccent
                              : const Color(0xFF0F766E),
                          fontFamily: 'monospace',
                          fontSize: 14,
                          backgroundColor: Colors.transparent,
                        ),
                        codeblockPadding: const EdgeInsets.all(16),
                        codeblockDecoration: BoxDecoration(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.black45
                              : Colors.black.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Theme.of(context).brightness == Brightness.dark
                                ? AppColors.universe.glassBorder
                                : Colors.black.withValues(alpha: 0.1),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Lower Arrow indicator (if next note exists)
                    if (noteIndex < dummyTopics.length - 1)
                      Center(
                        child: Column(
                          children: [
                            const SizedBox(height: 16),
                            IconButton(
                              icon: Icon(Icons.keyboard_arrow_down, color: Theme.of(context).colorScheme.primary, size: 28),
                              onPressed: onNext,
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
      color: Colors.transparent,
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
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14, height: 1.5),
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

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}