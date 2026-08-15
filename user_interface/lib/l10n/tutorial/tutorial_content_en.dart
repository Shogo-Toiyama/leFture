// lib/l10n/tutorial/tutorial_content_en.dart
import 'package:lefture/l10n/tutorial/tutorial_content_model.dart';

const kTutorialContentEn = TutorialContent(
  courseTitle: 'Guide & Notes',
  courseSummary:
      'Where the app tour lives, plus a home for one-off recordings that don\'t need their own course.',
  lectureTitle: 'Welcome to leFture: From Recording to Learning',
  lectureSummary:
      'This sample lecture introduces how leFture works and its core philosophy. Experience how everyday recordings transform into organized, future-shaping knowledge.',
  funFact: TutorialFunFact(
    title: 'The "Memory Bug" Discovered in 1885 🧠',
    hook:
        'Without any review, 74% of what you learn vanishes within 24 hours — this was the shocking discovery made by German psychologist Hermann Ebbinghaus in 1885 with his "Forgetting Curve".',
    body:
        'Ebbinghaus rigorously tested how quickly human memory decays by memorizing over 1,600 nonsense syllables like "WID" and "ZOF".\n\nPeople usually assume memory fades gradually over time. In reality, most of it plummets within the very first 24 hours.\n\nYet his most critical discovery was this: applying a single "active recall test" (forcing the brain to retrieve the memory) within 24 hours dramatically flattens the curve.\n\nRather than passively skimming notes for an hour, swiping through flashcards for just one minute signals the brain: "This is crucial information for survival!"\n\nThe real secret to effective learning isn\'t how long you study, but how many times you actively retrieve the knowledge.',
    sources: ['https://en.wikipedia.org/wiki/Forgetting_curve'],
  ),
  announcements: [
    TutorialAnnouncement(
      id: 'ann_1',
      type: 'TODO',
      content:
          'Fill in your profile (major, interests, future goals) to experience personalized trivia tailored just for you!',
    ),
    TutorialAnnouncement(
      id: 'ann_2',
      type: 'TODO',
      content:
          'Create a new course and try hitting the record button in your next actual lecture!',
    ),
    TutorialAnnouncement(
      id: 'ann_3',
      type: 'INFO',
      content:
          'Exciting upcoming features like a companion partner AI and your growing "Galaxy of Learning" are on the way! Stay tuned!',
    ),
  ],
  keywords: [
    TutorialKeyword(keyword: 'leFture', topicNumber: 1),
    TutorialKeyword(keyword: 'The Magic Pipeline', topicNumber: 1),
    TutorialKeyword(keyword: 'Review Cards', topicNumber: 2),
    TutorialKeyword(keyword: 'Deep Notes', topicNumber: 2),
    TutorialKeyword(keyword: 'Citation Tracking', topicNumber: 2),
    TutorialKeyword(keyword: 'AHA Moment', topicNumber: 3),
    TutorialKeyword(keyword: 'Galaxy of Learning', topicNumber: 4),
  ],
  topics: [
    TutorialTopic(
      topicIndex: 1,
      title: 'The Magic Pipeline',
      summary:
          'How simply putting your phone down and recording turns into structured review materials, and the story behind leFture.',
      deepNoteMarkdown: '''## 👋 Welcome to leFture!
Welcome to leFture! Thank you so much for installing the app and opening this tutorial.

Let me start by asking you a few questions:
- **Are you enjoying your classes and studies?**
- **Do you love your major?**
- **Do you have a clear purpose or goal for what you're currently learning?**

This app was built to help you answer a confident **"Yes!"** to all of those questions.

The name **leFture** stands for **"Lectures for the Futures"**. True to its name, it was created with the wish to help you feel that the classes you attend every day are genuinely shaping your own future.

Originally, this project started from my own frustration: feeling that I wasn't making the most of school and that it could be so much more meaningful. Wondering why lectures that should be exciting often felt like a chore, I realized there were **two primary causes**:

## ❓ 1. Lectures are difficult and hard to follow in real-time
Haven't you had moments where a lecture only felt interesting when you actually understood what was going on? Or times when you had no idea what was happening during class, but while studying for exams, things gradually clicked and you thought, "If only I understood this earlier, I would have enjoyed the class so much more"? I hypothesized that the main reason classes become boring is simply that we fail to understand them in the moment.

Once you get left behind in a class, the next lecture becomes completely incomprehensible. Especially since my native language is Japanese, I could only understand about half of an English lecture. Taking classes in that state without reviewing makes you feel increasingly lost, and it ceases to be fun altogether.

Naturally, reviewing right away would solve this, but I've always struggled with traditional reviewing. It takes too much time, notes are never complete, and professors rarely hand out post-lecture study guides. I thought: if there were an enjoyable, effortless, yet solid way to review, following difficult lectures might become manageable and even fun.

## 💡 2. Failing to see the connection to your own interests and goals
Even if you understand everything, learning something that feels irrelevant to you is naturally unexciting. Conversely, discovering that seemingly unrelated knowledge connects directly to your own passions creates a mind-blowing **"AHA Moment"**.

Nothing taught in university lectures is useless. Most students choose a major aligned with their interests, meaning lecture topics are likely relevant to everyday life or your ambitions. However, professors can't tailor lectures to every single individual. That’s why I thought: if AI could generate personalized, fascinating trivia connecting lecture concepts to your unique interests, wouldn't lectures become infinitely more engaging?

## ⚙️ The Solution: A Positive Learning Routine
To solve these challenges, I built an app that uses AI to analyze lecture content, generating easy-to-digest review materials and personalized trivia. Using it is effortless:

- **Before class**: Tap the record button once
- **During class**: Put your phone down and just focus
- **After class**: Upload the audio, that's it

On the bus ride home or relaxing on your couch, you can review in a stress-free environment. I hope this creates a positive routine where you look forward to tomorrow's lectures!''',
      reviewCards: [
        TutorialReviewCard(
          cardType: 'hook',
          heroEmoji: '❓',
          title: 'Are you enjoying class?',
          contentBlocks: [
            {
              'type': 'quote',
              'text':
                  '"Is this lecture really helping my future...?" Have you ever felt that lingering doubt?',
            },
            {
              'type': 'paragraph',
              'text':
                  'Lectures often become boring simply because we get left behind and lose track of what\'s being taught.',
            },
            {
              'type': 'paragraph',
              'text':
                  'leFture exists to erase that doubt. **Just set your phone down and record** — your lecture turns itself into material you actually understand.',
            },
          ],
        ),
        TutorialReviewCard(
          cardType: 'core_why',
          heroEmoji: '🎙️',
          title: 'Just hit Record and focus',
          contentBlocks: [
            {
              'type': 'paragraph',
              'text':
                  'It\'s simple: **tap the record button once** before class starts, put your phone down, and focus on the lecture in front of you.',
            },
            {
              'type': 'callout',
              'alert_type': 'info',
              'text':
                  'Upload the audio when class ends! By the time you\'re on the bus or on your couch, your study materials will be ready.',
            },
            {
              'type': 'paragraph',
              'text':
                  'Behind the scenes, a multi-stage "**Magic Pipeline**" kicks in — transcribing the audio, organizing it by topic, and extracting the key points. You don\'t have to lift a finger, and that\'s the whole point.',
            },
          ],
        ),
        TutorialReviewCard(
          cardType: 'gotcha',
          heroEmoji: '⚡',
          title: '10 minutes to structured knowledge',
          contentBlocks: [
            {
              'type': 'paragraph',
              'text':
                  'In about 10 minutes, AI analyzes the audio, removes background noise, and automatically generates high-quality review cards and trivia.',
            },
            {
              'type': 'callout',
              'alert_type': 'warning',
              'text':
                  'Processing continues in the background even if you close the app — no need to stare at the screen waiting!',
            },
            {
              'type': 'paragraph',
              'text':
                  'During those 10 minutes, several AI tasks run one after another — sometimes in parallel: transcription, topic segmentation, summarization, review card generation, and trivia generation. Your review materials will be ready before you even think to check.',
            },
          ],
        ),
        TutorialReviewCard(
          cardType: 'next_action',
          heroEmoji: '🧭',
          title: 'Next Steps',
          contentBlocks: [
            {
              'type': 'paragraph',
              'text':
                  'Start a new routine of quick, relaxed reviews with your generated content.',
            },
            {
              'type': 'list',
              'items': [
                'Tap record once before class starts',
                'Put your phone down and focus during class',
                'Just upload the audio when it\'s over',
              ],
            },
            {
              'type': 'paragraph',
              'text':
                  'Next, let\'s explore the two review tools designed for deep understanding: Review Cards and Deep Notes!',
            },
          ],
        ),
      ],
    ),
    TutorialTopic(
      topicIndex: 2,
      title: 'Fun & Deep Understanding',
      summary:
          'How to use 15-minute Review Cards for quick summaries and Deep Notes for exhaustive context.',
      deepNoteMarkdown: '''## 💡 Two Ways to Review
Reviewing is one of the most effective ways to retain what you've learned, but getting started is often difficult for several reasons: clean review materials rarely exist (usually just messy board photos or personal notes lacking context), and thorough reviewing takes hours. To turn reviewing into an enjoyable, effortless, and solid learning habit, we created two complementary review methods.

## 🎴 Review Cards
When you want to quickly recap key lecture points in about 15 minutes right after class, simply swipe through these flashcards. Each topic follows a 4-card structure:

- **Hook**: An intuitive analogy to grab your attention right away
- **Core Why**: The heart of the topic, explained concisely and enthusiastically
- **Gotcha**: A deep dive into the single most important "pay attention here" moment
- **Next Action**: A wrap-up, plus a bridge into the next topic

By extracting only the most critical parts of the lecture and breaking them down with clear analogies and plain language, these cards make reviewing quick and visually engaging through illustrations, emojis, and bite-sized lists.

## 📖 Deep Notes
Designed for when you have dedicated study time or need to prepare thoroughly for exams. Reading this note covers nearly everything the professor said.

Reading raw transcripts is time-consuming and inefficient, but generic AI summaries often drop vital technical nuances. Deep Notes act as a "Readable Lecture" — formatting the entire transcript into a structured, highly readable guide.

Furthermore, you can inspect the **source citations** of any text. Simply select a sentence and tap "Citation" to instantly see exactly where in the transcript that point was spoken.

## 🎯 Approach Exams with Confidence
Having crystal-clear study materials ready right after class removes the friction of studying. Swipe through Review Cards after class, and dive into Deep Notes when you want to study deeply. You will walk into your next class and upcoming exams with total confidence!''',
      reviewCards: [
        TutorialReviewCard(
          cardType: 'hook',
          heroEmoji: '💡',
          title: 'Why is reviewing so hard?',
          contentBlocks: [
            {
              'type': 'quote',
              'text':
                  'Messy notes and endless study hours... break through the barrier with two distinct review tools!',
            },
            {
              'type': 'paragraph',
              'text':
                  'Quick-to-digest "Review Cards" and thorough "Deep Notes" transform reviewing into a sustainable, effortless habit.',
            },
            {
              'type': 'paragraph',
              'text':
                  'Both are generated automatically from the same lecture, so you can **freely switch between them** depending on your mood and how much time you have.',
            },
          ],
        ),
        TutorialReviewCard(
          cardType: 'core_why',
          heroEmoji: '🎴',
          title: '15-Minute Review Cards',
          contentBlocks: [
            {
              'type': 'paragraph',
              'text':
                  'Ideal for quick reviews right after class. A 4-card sequence per topic breaks down the lecture\'s hottest concepts.',
            },
            {
              'type': 'callout',
              'alert_type': 'info',
              'text':
                  'Swipe through Hook, Core Why, Gotcha, and Next Action to effortlessly lock in the core takeaways.',
            },
            {
              'type': 'paragraph',
              'text':
                  'Cards aren\'t just for reading — you can **highlight lines and jot down your own notes** right on them. Underline a sentence that catches your eye, and it\'ll be right there waiting the next time you review.',
            },
          ],
        ),
        TutorialReviewCard(
          cardType: 'gotcha',
          heroEmoji: '📖',
          title: 'Deep Notes & Source Citations',
          contentBlocks: [
            {
              'type': 'paragraph',
              'text':
                  'A "Readable Lecture" capturing the full context without dropping critical details like generic summaries do.',
            },
            {
              'type': 'callout',
              'alert_type': 'info',
              'text':
                  'Select any text and tap "Citation" to instantly pinpoint where the professor spoke about it in the transcript!',
            },
            {
              'type': 'paragraph',
              'text':
                  'If something ever makes you think "wait, did they actually say that?", the **citation feature** jumps you straight to that exact moment in the transcript — so you can trust the AI\'s summary without blindly relying on it.',
            },
          ],
        ),
        TutorialReviewCard(
          cardType: 'next_action',
          heroEmoji: '🧭',
          title: 'Smart Habits & Next Steps',
          contentBlocks: [
            {
              'type': 'paragraph',
              'text':
                  'Use cards for quick daily recaps, and dive into Deep Notes on weekends or before exams.',
            },
            {
              'type': 'list',
              'items': [
                'Daily routine: Swipe through cards for 15 minutes',
                'Exam prep: Explore Deep Notes and citations',
                'Anything that catches your eye: highlight it or leave a note',
              ],
            },
            {
              'type': 'paragraph',
              'text':
                  'Next up: discover the secret behind our personalized "Fun Fact" trivia section!',
            },
          ],
        ),
      ],
    ),
    TutorialTopic(
      topicIndex: 3,
      title: 'Connecting to Yourself',
      summary:
          'How profile personalization and real-time web search generate unique "AHA Moments".',
      deepNoteMarkdown: '''## 🧠 Learning for Your Own Future
The lectures you attend are for your own future. If you are investing your time, learning with genuine interest is infinitely more rewarding! Concepts that seem irrelevant today might become critical in your career or practical in daily life.

Have you ever experienced this in school?
> **You completely forgot textbook formulas, but vividly remember the bizarre quirk or historical anecdote the teacher briefly shared.**

The human brain remembers emotionally engaging stories and personally relevant information far better than dry, abstract symbols.

## 💡 The Fun Fact Section & AHA Moments
We built the "**Fun Fact**" section to bring that engaging feeling to every single lecture, by combining three ingredients:

- **Your profile**: The major, hobbies, and career ambitions you registered
- **Today's lecture**: The specific topics and keywords covered
- **Real-time web search**: Live data showing how the theory is actively used in modern industries and breaking news

When a seemingly dry concept suddenly connects to something you love, you experience an illuminating **"AHA Moment"**. We deliver personalized trivia that makes you genuinely look forward to your next class!''',
      reviewCards: [
        TutorialReviewCard(
          cardType: 'hook',
          heroEmoji: '🧠',
          title: 'Emotional stories stick',
          contentBlocks: [
            {
              'type': 'quote',
              'text':
                  'You might forget bold textbook terms, but you never forget the quirky anecdote your professor told!',
            },
            {
              'type': 'paragraph',
              'text':
                  'Our brains are wired to retain stories that spark emotion and feel personally relevant far more easily.',
            },
            {
              'type': 'paragraph',
              'text':
                  'So why not deliberately create that spark in every single lecture? That\'s exactly the idea behind the "**Fun Fact**" section.',
            },
          ],
        ),
        TutorialReviewCard(
          cardType: 'core_why',
          heroEmoji: '🔮',
          title: 'Personalized Fun Facts',
          contentBlocks: [
            {
              'type': 'paragraph',
              'text':
                  'Based on your registered profile (major, hobbies, career dreams), AI connects lecture topics to your personal passions.',
            },
            {
              'type': 'callout',
              'alert_type': 'info',
              'text':
                  'Experience sudden "AHA Moments" as seemingly unrelated academic concepts link directly to what you love.',
            },
            {
              'type': 'paragraph',
              'text':
                  'Take a thermodynamics lecture, for example: someone who loves cooking might get a kitchen-science angle, while an athlete gets an explanation through muscle metabolism. Same lecture, but **the entry point is written just for you**.',
            },
          ],
        ),
        TutorialReviewCard(
          cardType: 'gotcha',
          heroEmoji: '🌐',
          title: 'Live Web Search & Real-World Use',
          contentBlocks: [
            {
              'type': 'paragraph',
              'text':
                  'AI searches the web in real-time to explain how theoretical concepts are actively applied in modern society and latest news.',
            },
            {
              'type': 'callout',
              'alert_type': 'warning',
              'text':
                  'Dry academic concepts transform into living, practical knowledge for your future!',
            },
            {
              'type': 'paragraph',
              'text':
                  'It doesn\'t stop at trivia — it goes as far as showing exactly where in today\'s world that concept shows up, so it sticks with you as **knowledge you\'ll actually use**, not just something to memorize for a test.',
            },
          ],
        ),
        TutorialReviewCard(
          cardType: 'next_action',
          heroEmoji: '🧭',
          title: 'Next Steps',
          contentBlocks: [
            {
              'type': 'paragraph',
              'text':
                  'Keep your profile updated to enjoy personalized trivia generated just for you.',
            },
            {
              'type': 'list',
              'items': [
                'Add your major, hobbies, and dreams in Profile',
                'Enjoy unique trivia tailored for every lecture',
                'Check out the latest topics surfaced by real-time web search',
              ],
            },
            {
              'type': 'paragraph',
              'text':
                  'Finally, let\'s look at our helpful companion tools and the exciting future roadmap of leFture!',
            },
          ],
        ),
      ],
    ),
    TutorialTopic(
      topicIndex: 4,
      title: 'The Future of leFture',
      summary:
          'Discover companion tools like Announcements and Topic Maps, and our vision for the "Galaxy of Learning".',
      deepNoteMarkdown: '''## 🛠️ Companion Study Tools
Beyond Review Cards and Deep Notes, leFture provides a rich suite of learning tools:

- **📢 Announcements**: Extracts action items and deadlines from class. Swipe to mark them completed.
- **🏷️ Keywords**: Automatically pulls essential vocabulary per topic, allowing you to add personal definitions.
- **🗺️ Topic Map**: Visualizes the high-level lecture structure and relationships between topics.
- **✍️ Highlights & Notes**: Highlight key sentences in Review Cards or Deep Notes, and jot down personal notes.
- **⏱️ Lecture Moments**: Tap once during recording to bookmark timestamps for exciting or tricky moments.

## 🚀 The Three Levels of Entertainment
The ultimate mission of leFture is to help you feel excited about your future by transforming previously stressful learning into **genuine entertainment**.

### ⚡ Short-Term: The 15-Minute Review Session
Clear up confusion immediately after class so you never feel lost in the next lecture.

### 🤝 Medium-Term: A True Learning Space
Deepen your spontaneous ideas and curiosities alongside a companion AI that understands your values, learning history, and personality.

### 🌌 Long-Term: The Galaxy of Learning
The massive galaxy on your home screen will evolve as a **visual testament to your personal growth**. Every lecture and idea becomes a glowing star in your personal universe.

## 💖 Thank You
While we are currently at the short-term phase, partner AI companions and visual learning galaxies will soon arrive. Thank you for reading, and we are cheering for your bright future!''',
      reviewCards: [
        TutorialReviewCard(
          cardType: 'hook',
          heroEmoji: '🚀',
          title: 'More to discover!',
          contentBlocks: [
            {
              'type': 'quote',
              'text':
                  'There are still plenty of features waiting for you, plus an exciting future vision for this app!',
            },
            {
              'type': 'paragraph',
              'text':
                  'Discover companion tools that support your studies and our roadmap to turning learning into entertainment.',
            },
            {
              'type': 'paragraph',
              'text':
                  'Everything we\'ve covered so far — Review Cards, Deep Notes, Fun Facts — is really just **the entry point** into a much bigger vision for this app.',
            },
          ],
        ),
        TutorialReviewCard(
          cardType: 'core_why',
          heroEmoji: '🛠️',
          title: 'Comprehensive Study Tools',
          contentBlocks: [
            {
              'type': 'paragraph',
              'text':
                  'A full suite of tools to keep your learning organized and frictionless.',
            },
            {
              'type': 'list',
              'items': [
                '📢 Announcements: Track deadlines with swipe-to-complete',
                '🏷️ Keywords: Key terminology with custom definitions',
                '🗺️ Topic Map: Visual overview of lecture structure',
                '✍️ Highlights & Moments: Bookmark timestamps during class',
              ],
            },
            {
              'type': 'paragraph',
              'text':
                  'Every one of these features comes from the same underlying belief: **shave off even one more piece of friction** from reviewing. Small tools add up, making everyday studying just a little bit easier each time.',
            },
          ],
        ),
        TutorialReviewCard(
          cardType: 'gotcha',
          heroEmoji: '🌌',
          title: 'Future Vision: Galaxy of Learning',
          contentBlocks: [
            {
              'type': 'paragraph',
              'text':
                  'leFture\'s ultimate goal is to turn all your learning and experiences into entertainment for your future.',
            },
            {
              'type': 'callout',
              'alert_type': 'info',
              'text':
                  'From short-term 15-minute reviews to companion AI and the interactive "Galaxy of Learning" on your home screen!',
            },
            {
              'type': 'paragraph',
              'text':
                  'Right now, only the "short-term" review session is live — but that\'s just the first step of a three-stage roadmap. Next comes a companion AI that truly understands you, followed by the "**Galaxy of Learning**," a living visualization of your growth.',
            },
          ],
        ),
        TutorialReviewCard(
          cardType: 'next_action',
          heroEmoji: '💖',
          title: 'Tutorial Complete!',
          contentBlocks: [
            {
              'type': 'paragraph',
              'text':
                  'You\'re all set! Thank you so much for exploring this tutorial.',
            },
            {
              'type': 'list',
              'items': [
                'Hit Record in your next class',
                'Experience your new 10-minute review routine',
                'Explore other features like Announcements and Keywords',
              ],
            },
            {
              'type': 'paragraph',
              'text':
                  'leFture is cheering for you and your future every step of the way!',
            },
          ],
        ),
      ],
    ),
  ],
);
