# app/services/tutorial_content.py
#
# チュートリアル講義の固定コンテンツ(言語別)。LLM生成ではなく、あらかじめ
# 用意した文言をそのまま /seed-tutorial エンドポイントがSupabaseへ挿入する。
#
# これは元々 user_interface/lib/l10n/tutorial/tutorial_content_en.dart と
# tutorial_content_ja.dart にあったDart定数を1:1で移植したもの。今後
# コンテンツを直す場合はこのファイルだけを更新すればよい(クライアント側の
# 静的コンテンツは廃止済み)。

TUTORIAL_CONTENT: dict[str, dict] = {
    "en": {
        "course_title": "Guide & Notes",
        "course_summary": (
            "Where the app tour lives, plus a home for one-off recordings that "
            "don't need their own course."
        ),
        "lecture_title": "Welcome to leFture: From Recording to Learning",
        "lecture_summary": (
            "This sample lecture introduces how leFture works and its core "
            "philosophy. Experience how everyday recordings transform into "
            "organized, future-shaping knowledge."
        ),
        "fun_fact": {
            "title": 'The "Memory Bug" Discovered in 1885 🧠',
            "hook": (
                "Without any review, 74% of what you learn vanishes within 24 "
                "hours — this was the shocking discovery made by German "
                'psychologist Hermann Ebbinghaus in 1885 with his "Forgetting '
                'Curve".'
            ),
            "body": (
                "Ebbinghaus rigorously tested how quickly human memory decays by "
                'memorizing over 1,600 nonsense syllables like "WID" and "ZOF".\n\n'
                "People usually assume memory fades gradually over time. In "
                "reality, most of it plummets within the very first 24 hours.\n\n"
                'Yet his most critical discovery was this: applying a single '
                '"active recall test" (forcing the brain to retrieve the memory) '
                "within 24 hours dramatically flattens the curve.\n\n"
                "Rather than passively skimming notes for an hour, swiping "
                "through flashcards for just one minute signals the brain: "
                '"This is crucial information for survival!"\n\n'
                "The real secret to effective learning isn't how long you study, "
                "but how many times you actively retrieve the knowledge."
            ),
            "sources": ["https://en.wikipedia.org/wiki/Forgetting_curve"],
        },
        "announcements": [
            {
                "type": "TODO",
                "title": "Swipe to Complete",
                "description": (
                    "Try swiping this announcement tile to the left to mark it "
                    "as completed!"
                ),
            },
            {
                "type": "TODO",
                "title": "Record Your Next Lecture",
                "description": (
                    "Tap the record button at the bottom of the Home screen to "
                    "start recording your next class!"
                ),
            },
            {
                "type": "HINT",
                "title": "Leave Live Reactions",
                "description": (
                    'Add reactions in the Live tab whenever you feel "Interesting" '
                    'or "Difficult"! You can revisit those moments later from the '
                    "transcript."
                ),
            },
        ],
        "keywords": [
            {"keyword": "leFture", "topic_number": 1},
            {"keyword": "The Magic Pipeline", "topic_number": 1},
            {"keyword": "Review Cards", "topic_number": 2},
            {"keyword": "Deep Notes", "topic_number": 2},
            {"keyword": "Citation Tracking", "topic_number": 2},
            {"keyword": "AHA Moment", "topic_number": 3},
            {"keyword": "Galaxy of Learning", "topic_number": 4},
        ],
        "topics": [
            {
                "topic_index": 1,
                "title": "The Magic Pipeline",
                "summary": (
                    "How simply putting your phone down and recording turns into "
                    "structured review materials, and the story behind leFture."
                ),
                "deep_note_markdown": """## 👋 Welcome to leFture!
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

Nothing taught in university lectures is useless. Most students choose a major aligned with their interests, meaning lecture topics are likely relevant to everyday life or your ambitions. However, professors can't tailor lectures to every single individual. That's why I thought: if AI could generate personalized, fascinating Fun Facts connecting lecture concepts to your unique interests, wouldn't lectures become infinitely more engaging?

## ⚙️ The Solution: A Positive Learning Routine
To solve these challenges, I built an app that uses AI to analyze lecture content, generating easy-to-digest review materials and personalized Fun Facts. Using it is effortless:

- **Before class**: Tap the record button once
- **During class**: Put your phone down and just focus
- **After class**: Upload the audio, that's it

On the bus ride home or relaxing on your couch, you can review in a stress-free environment. I hope this creates a positive routine where you look forward to tomorrow's lectures!""",
                "review_cards": [
                    {
                        "card_type": "hook",
                        "hero_emoji": "❓",
                        "title": "Are you enjoying class?",
                        "content_blocks": [
                            {
                                "type": "quote",
                                "text": (
                                    '"Is this lecture really helping my future...?" '
                                    "Have you ever felt that lingering doubt?"
                                ),
                            },
                            {
                                "type": "paragraph",
                                "text": (
                                    "Lectures often become boring simply because we "
                                    "get left behind and lose track of what's being "
                                    "taught."
                                ),
                            },
                            {
                                "type": "paragraph",
                                "text": (
                                    "leFture exists to erase that doubt. **Just set "
                                    "your phone down and record** — your lecture "
                                    "turns itself into material you actually "
                                    "understand."
                                ),
                            },
                        ],
                    },
                    {
                        "card_type": "core_why",
                        "hero_emoji": "🎙️",
                        "title": "Just hit Record and focus",
                        "content_blocks": [
                            {
                                "type": "paragraph",
                                "text": (
                                    "It's simple: **tap the record button once** "
                                    "before class starts, put your phone down, and "
                                    "focus on the lecture in front of you."
                                ),
                            },
                            {
                                "type": "callout",
                                "alert_type": "info",
                                "text": (
                                    "Upload the audio when class ends! By the time "
                                    "you're on the bus or on your couch, your study "
                                    "materials will be ready."
                                ),
                            },
                            {
                                "type": "paragraph",
                                "text": (
                                    'Behind the scenes, a multi-stage "**Magic '
                                    'Pipeline**" kicks in — transcribing the audio, '
                                    "organizing it by topic, and extracting the key "
                                    "points. You don't have to lift a finger, and "
                                    "that's the whole point."
                                ),
                            },
                        ],
                    },
                    {
                        "card_type": "gotcha",
                        "hero_emoji": "⚡",
                        "title": "10 minutes to structured knowledge",
                        "content_blocks": [
                            {
                                "type": "paragraph",
                                "text": (
                                    "In about 10 minutes, AI analyzes the audio, "
                                    "removes background noise, and automatically "
                                    "generates high-quality review cards and Fun "
                                    "Facts."
                                ),
                            },
                            {
                                "type": "callout",
                                "alert_type": "warning",
                                "text": (
                                    "Processing continues in the background even "
                                    "if you close the app — no need to stare at "
                                    "the screen waiting!"
                                ),
                            },
                            {
                                "type": "paragraph",
                                "text": (
                                    "During those 10 minutes, several AI tasks run "
                                    "one after another — sometimes in parallel: "
                                    "transcription, topic segmentation, "
                                    "summarization, review card generation, and "
                                    "Fun Fact generation. Your review materials "
                                    "will be ready before you even think to check."
                                ),
                            },
                        ],
                    },
                    {
                        "card_type": "next_action",
                        "hero_emoji": "🚀",
                        "title": "Start Your Review Routine",
                        "content_blocks": [
                            {
                                "type": "paragraph",
                                "text": (
                                    "Start a new routine of quick, relaxed reviews "
                                    "with your generated content."
                                ),
                            },
                            {
                                "type": "list",
                                "items": [
                                    "Tap record once before class starts",
                                    "Put your phone down and focus during class",
                                    "Just upload the audio when it's over",
                                ],
                            },
                            {
                                "type": "paragraph",
                                "text": (
                                    "Next, let's explore the two review tools "
                                    "designed for deep understanding: Review Cards "
                                    "and Deep Notes!"
                                ),
                            },
                        ],
                    },
                ],
            },
            {
                "topic_index": 2,
                "title": "Fun & Deep Understanding",
                "summary": (
                    "How to use 15-minute Review Cards for quick summaries and "
                    "Deep Notes for exhaustive context."
                ),
                "deep_note_markdown": """## 💡 Two Ways to Review
Reviewing is one of the most effective ways to retain what you've learned, but getting started is often difficult for several reasons: clean review materials rarely exist (usually just messy board photos or personal notes lacking context), and thorough reviewing takes hours. To turn reviewing into an enjoyable, effortless, and solid learning habit, we created two complementary review methods.

## 🧩 Review Cards
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
Having crystal-clear study materials ready right after class removes the friction of studying. Swipe through Review Cards after class, and dive into Deep Notes when you want to study deeply. You will walk into your next class and upcoming exams with total confidence!""",
                "review_cards": [
                    {
                        "card_type": "hook",
                        "hero_emoji": "💡",
                        "title": "Why is reviewing so hard?",
                        "content_blocks": [
                            {
                                "type": "quote",
                                "text": (
                                    "Messy notes and endless study hours... break "
                                    "through the barrier with two distinct review "
                                    "tools!"
                                ),
                            },
                            {
                                "type": "paragraph",
                                "text": (
                                    'Quick-to-digest "Review Cards" and thorough '
                                    '"Deep Notes" transform reviewing into a '
                                    "sustainable, effortless habit."
                                ),
                            },
                            {
                                "type": "paragraph",
                                "text": (
                                    "Both are generated automatically from the "
                                    "same lecture, so you can **freely switch "
                                    "between them** depending on your mood and how "
                                    "much time you have."
                                ),
                            },
                        ],
                    },
                    {
                        "card_type": "core_why",
                        "hero_emoji": "🧩",
                        "title": "15-Minute Review Cards",
                        "content_blocks": [
                            {
                                "type": "paragraph",
                                "text": (
                                    "Ideal for quick reviews right after class. A "
                                    "4-card sequence per topic breaks down the "
                                    "lecture's hottest concepts."
                                ),
                            },
                            {
                                "type": "callout",
                                "alert_type": "info",
                                "text": (
                                    "Swipe through Hook, Core Why, Gotcha, and Next "
                                    "Action to effortlessly lock in the core "
                                    "takeaways."
                                ),
                            },
                            {
                                "type": "paragraph",
                                "text": (
                                    "Cards aren't just for reading — you can "
                                    "**highlight lines and jot down your own "
                                    "notes** right on them. Underline a sentence "
                                    "that catches your eye, and it'll be right "
                                    "there waiting the next time you review."
                                ),
                            },
                        ],
                    },
                    {
                        "card_type": "gotcha",
                        "hero_emoji": "📖",
                        "title": "Deep Notes & Source Citations",
                        "content_blocks": [
                            {
                                "type": "paragraph",
                                "text": (
                                    'A "Readable Lecture" capturing the full '
                                    "context without dropping critical details "
                                    "like generic summaries do."
                                ),
                            },
                            {
                                "type": "callout",
                                "alert_type": "info",
                                "text": (
                                    'Select any text and tap "Citation" to '
                                    "instantly pinpoint where the professor spoke "
                                    "about it in the transcript!"
                                ),
                            },
                            {
                                "type": "paragraph",
                                "text": (
                                    'If something ever makes you think "wait, did '
                                    'they actually say that?", the **citation '
                                    "feature** jumps you straight to that exact "
                                    "moment in the transcript — so you can trust "
                                    "the AI's summary without blindly relying on "
                                    "it."
                                ),
                            },
                        ],
                    },
                    {
                        "card_type": "next_action",
                        "hero_emoji": "💡",
                        "title": "Discover Your Best Study Style",
                        "content_blocks": [
                            {
                                "type": "paragraph",
                                "text": (
                                    "Use Review Cards for light daily check-ins, "
                                    "and dive into Deep Notes before exams or on "
                                    "weekends."
                                ),
                            },
                            {
                                "type": "list",
                                "items": [
                                    "Daily Review: Swipe through cards in 15 minutes",
                                    "Exam Prep: Read Deep Notes for context & citations",
                                    "Save key sentences with highlights and custom notes",
                                ],
                            },
                            {
                                "type": "paragraph",
                                "text": (
                                    'Next, let\'s explore the "Fun Facts" section '
                                    "that makes learning genuinely exciting!"
                                ),
                            },
                        ],
                    },
                ],
            },
            {
                "topic_index": 3,
                "title": "Connecting Knowledge to Yourself",
                "summary": (
                    "Personalized Fun Facts created from your profile and "
                    "real-time Web Search."
                ),
                "deep_note_markdown": """## 🧠 Study for Your Own Time & Growth
The classes you take today belong to you. Learning should be enjoyable and provide positive value for your future. Even dry concepts might become crucial in your career, and unrelated subjects can enrich your everyday life. If you're going to study anyway, making it fun and meaningful works best!

## 💡 Emotionally Charged Memories & Fun Facts
Remember when you were in school? You might have forgotten formulas or textbook definitions, but still clearly remember a teacher's funny anecdote or historical trivia.

The human brain naturally retains information that triggers emotions or feels personally relevant.

That's why we built the **Fun Facts** section — combining three sources of information:

- **Your Profile**: Your major, hobbies, and career goals
- **Lecture Topics**: Today's core concepts and keywords
- **Real-Time Web Search**: How this theory is applied in current news and industry

When an abstract concept connects with something you love, you get a sudden "AHA!" moment that turns studying into something you look forward to.""",
                "review_cards": [
                    {
                        "card_type": "hook",
                        "hero_emoji": "🧠",
                        "title": "Memories Tied to Emotion Stick",
                        "content_blocks": [
                            {
                                "type": "quote",
                                "text": (
                                    "Forget textbook formulas, but remember a "
                                    "professor's quirky story? Here's why!"
                                ),
                            },
                            {
                                "type": "paragraph",
                                "text": (
                                    "Human memory prioritizes emotional triggers "
                                    "and personal relevance over dry facts."
                                ),
                            },
                            {
                                "type": "paragraph",
                                "text": (
                                    'The Fun Facts section intentionally creates '
                                    'those "AHA!" moments in every single lecture.'
                                ),
                            },
                        ],
                    },
                    {
                        "card_type": "core_why",
                        "hero_emoji": "🔮",
                        "title": "Fun Facts Tailored Just for You",
                        "content_blocks": [
                            {
                                "type": "paragraph",
                                "text": (
                                    "AI connects today's lecture with your "
                                    "background, hobbies, and dreams registered in "
                                    "your profile."
                                ),
                            },
                            {
                                "type": "callout",
                                "alert_type": "info",
                                "text": (
                                    "See how abstract concepts directly relate to "
                                    "your passions and future goals!"
                                ),
                            },
                            {
                                "type": "paragraph",
                                "text": (
                                    "Whether you love cooking or sports, "
                                    "thermodynamics gets explained using analogies "
                                    "from the kitchen or athletic metabolism!"
                                ),
                            },
                        ],
                    },
                    {
                        "card_type": "gotcha",
                        "hero_emoji": "🌐",
                        "title": "Real-Time Web Search & Living Knowledge",
                        "content_blocks": [
                            {
                                "type": "paragraph",
                                "text": (
                                    "Real-time web searches reveal how concepts "
                                    "are being applied in current industry news "
                                    "today."
                                ),
                            },
                            {
                                "type": "callout",
                                "alert_type": "warning",
                                "text": (
                                    "Static textbook theory turns into active, "
                                    "real-world knowledge for your career!"
                                ),
                            },
                            {
                                "type": "paragraph",
                                "text": (
                                    "It doesn't stop at Fun Facts — it goes as far "
                                    "as showing exactly where in today's world "
                                    "that concept shows up, so it sticks with you "
                                    "as **knowledge you'll actually use**, not "
                                    "just something to memorize for a test."
                                ),
                            },
                        ],
                    },
                    {
                        "card_type": "next_action",
                        "hero_emoji": "🎯",
                        "title": "Set Up Your Profile & Enjoy",
                        "content_blocks": [
                            {
                                "type": "paragraph",
                                "text": (
                                    "Keep your profile updated to enjoy "
                                    "personalized Fun Facts generated just for "
                                    "you."
                                ),
                            },
                            {
                                "type": "list",
                                "items": [
                                    "Add your major, hobbies, and dreams in Profile",
                                    "Enjoy unique Fun Facts tailored for every lecture",
                                    "Check out the latest topics surfaced by real-time web search",
                                ],
                            },
                            {
                                "type": "paragraph",
                                "text": (
                                    "Finally, let's look at our helpful companion "
                                    "tools and the exciting future roadmap of "
                                    "leFture!"
                                ),
                            },
                        ],
                    },
                ],
            },
            {
                "topic_index": 4,
                "title": "The Future of leFture",
                "summary": (
                    "Discover companion tools like Announcements and Topic Maps, "
                    'and our vision for the "Galaxy of Learning".'
                ),
                "deep_note_markdown": """## 🛠️ Companion Study Tools
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
While we are currently at the short-term phase, partner AI companions and visual learning galaxies will soon arrive. Thank you for reading, and we are cheering for your bright future!""",
                "review_cards": [
                    {
                        "card_type": "hook",
                        "hero_emoji": "🚀",
                        "title": "More to discover!",
                        "content_blocks": [
                            {
                                "type": "quote",
                                "text": (
                                    "There are still plenty of features waiting "
                                    "for you, plus an exciting future vision for "
                                    "this app!"
                                ),
                            },
                            {
                                "type": "paragraph",
                                "text": (
                                    "Discover companion tools that support your "
                                    "studies and our roadmap to turning learning "
                                    "into entertainment."
                                ),
                            },
                            {
                                "type": "paragraph",
                                "text": (
                                    "Everything we've covered so far — Review "
                                    "Cards, Deep Notes, Fun Facts — is really just "
                                    "**the entry point** into a much bigger vision "
                                    "for this app."
                                ),
                            },
                        ],
                    },
                    {
                        "card_type": "core_why",
                        "hero_emoji": "🛠️",
                        "title": "Comprehensive Study Tools",
                        "content_blocks": [
                            {
                                "type": "paragraph",
                                "text": (
                                    "A full suite of tools to keep your learning "
                                    "organized and frictionless."
                                ),
                            },
                            {
                                "type": "list",
                                "items": [
                                    "📢 Announcements: Track deadlines with swipe-to-complete",
                                    "🏷️ Keywords: Key terminology with custom definitions",
                                    "🗺️ Topic Map: Visual overview of lecture structure",
                                    "✍️ Highlights & Moments: Bookmark timestamps during class",
                                ],
                            },
                            {
                                "type": "paragraph",
                                "text": (
                                    "Every one of these features comes from the "
                                    "same underlying belief: **shave off even one "
                                    "more piece of friction** from reviewing. "
                                    "Small tools add up, making everyday studying "
                                    "just a little bit easier each time."
                                ),
                            },
                        ],
                    },
                    {
                        "card_type": "gotcha",
                        "hero_emoji": "🌌",
                        "title": "Future Vision: Galaxy of Learning",
                        "content_blocks": [
                            {
                                "type": "paragraph",
                                "text": (
                                    "leFture's ultimate goal is to turn all your "
                                    "learning and experiences into entertainment "
                                    "for your future."
                                ),
                            },
                            {
                                "type": "callout",
                                "alert_type": "info",
                                "text": (
                                    "From short-term 15-minute reviews to "
                                    'companion AI and the interactive "Galaxy of '
                                    'Learning" on your home screen!'
                                ),
                            },
                            {
                                "type": "paragraph",
                                "text": (
                                    'Right now, only the "short-term" review '
                                    "session is live — but that's just the first "
                                    "step of a three-stage roadmap. Next comes a "
                                    "companion AI that truly understands you, "
                                    'followed by the "**Galaxy of Learning**," a '
                                    "living visualization of your growth."
                                ),
                            },
                        ],
                    },
                    {
                        "card_type": "next_action",
                        "hero_emoji": "💖",
                        "title": "Tutorial Complete!",
                        "content_blocks": [
                            {
                                "type": "paragraph",
                                "text": (
                                    "You're all set! Thank you so much for "
                                    "exploring this tutorial."
                                ),
                            },
                            {
                                "type": "list",
                                "items": [
                                    "Hit Record in your next class",
                                    "Experience your new 10-minute review routine",
                                    "Explore other features like Announcements and Keywords",
                                ],
                            },
                            {
                                "type": "paragraph",
                                "text": (
                                    "leFture is cheering for you and your future "
                                    "every step of the way!"
                                ),
                            },
                        ],
                    },
                ],
            },
        ],
    },
    "ja": {
        "course_title": "使い方・メモ",
        "course_summary": "leFtureの使い方や、コースを作るまでもない一発ものの録音をまとめておく場所です。",
        "lecture_title": "Welcome to leFture: 録音が「学び」に変わるまで",
        "lecture_summary": (
            "この講義はleFtureの使い方や開発思想を体験するためのチュートリアルです。"
            "ただの録音がどのように整理され、未来の学びへ変わるのかを体感してみましょう。"
        ),
        "fun_fact": {
            "title": "1885年に証明された「記憶のバグ」🧠",
            "hook": (
                "講義で学んだ記憶は何も復習しないと24時間で74%が消え去る——"
                "これがドイツの心理学者ヘルマン・エビングハウスが1885年に発見した"
                "「忘却曲線」の衝撃的なデータです。"
            ),
            "body": (
                "エビングハウスは「WID」や「ZOF」といった1,600個もの無意味な文字列を"
                "自ら暗記し、人間の脳がどれほど早く記憶を失うかを厳密に測定しました。\n\n"
                "普通は「時間が経つほど徐々に忘れる」と思われがちです。しかし実際は、"
                "直後の最初の24時間で一気に大半の記憶が崩壊します。\n\n"
                "ところが彼が見つけた最も重要な発見は、「24時間以内に1度だけ"
                "『問いかけて思い出す（アクティブリコール）』負荷をかけると、"
                "忘却のスピードが直角に鈍化する」という事実でした。\n\n"
                "ノートをぼーっと読み返す1時間よりも、カードをスワイプして"
                "「これなんだっけ？」と脳を刺激するたった1分のほうが、脳は"
                "『これは重要情報だ！』と判断して記憶を固定化します。\n\n"
                "効率的な学びの秘密は、勉強時間の長さではなく「思い出した回数」にあります。"
            ),
            "sources": ["https://en.wikipedia.org/wiki/Forgetting_curve"],
        },
        "announcements": [
            {
                "type": "TODO",
                "title": "スライドして完了にしよう",
                "description": (
                    "このアナウンスメントタイルを左にスライド（スワイプ）して、"
                    "完了状態に切り替えてみよう！"
                ),
            },
            {
                "type": "TODO",
                "title": "次の講義で録音してみよう",
                "description": (
                    "ホーム画面下の録音ボタンを押して、次の実際の授業でさっそく講義を"
                    "録音してみよう！"
                ),
            },
            {
                "type": "HINT",
                "title": "授業中にリアクションを残そう",
                "description": (
                    "授業中に「面白い」「難しい」と感じたらLiveタブからリアクションを"
                    "追加しよう！あとから文字起こし画面でタイムスタンプとして見返せるよ。"
                ),
            },
        ],
        "keywords": [
            {"keyword": "leFture", "topic_number": 1},
            {"keyword": "魔法のパイプライン", "topic_number": 1},
            {"keyword": "復習カード", "topic_number": 2},
            {"keyword": "詳細ノート", "topic_number": 2},
            {"keyword": "文字起こし出典機能", "topic_number": 2},
            {"keyword": "AHA体験", "topic_number": 3},
            {"keyword": "学びの銀河", "topic_number": 4},
        ],
        "topics": [
            {
                "topic_index": 1,
                "title": "魔法のパイプライン",
                "summary": "スマホを置いて録音するだけで、AIが自動で復習教材を生成する仕組みと開発者の想い。",
                "deep_note_markdown": """## 👋 ようこそ、leFtureへ！
ようこそ、leFtureへ！まずはインストールしていただき、そしてこのチュートリアルを開いていただき、本当にありがとうございます。

突然ですがみなさんに質問です。
- 授業や勉強は楽しめていますか？
- 自分の専攻分野は好きですか？
- 今勉強している意味や目標はありますか？

このアプリはこれらの質問に自信をもって「はい」と答えられるようにするために、そのお手伝いをするという目的で開発しています。

このアプリの名前である**leFture**は「**Lectures for the Futures**」を短くしたものです。その名の通り、みなさんが普段受けている授業が、みなさん自身の未来のためになっているという実感を持てるように、そのサポートがしたいなという想いで名付けました。

ちなみに最初このアプリは僕自身が、学校を楽しんでない、もっと有意義な時間にできるはずなのに、というモヤモヤを抱えて作り始めたものでした。本来楽しいはずの授業がなんでこんなにも面倒に感じてしまうのか、どうしたら解決できるのか、と考えた結果、これら二つのことが原因だと気付きました。

## ❓ 1. そもそも授業が難しくてその場でついていけない
内容が理解できているときだけ、その授業が面白いって思うこと、ありませんか？もしくは、最後まで全くわからなかったのに、試験勉強をしてるとだんだんと内容が理解できてきて、少しずつ面白くなっていって、もっと早くから勉強してたらもっと楽しめたかもしれないのに、なんて思うこともあります。僕は授業が面白くなくなる主な原因は、単に理解できていないからなんじゃないかと仮説を立てました。

ある授業で置いてけぼりになってしまうと、その次の授業でも何を言っているのか分からなくなります。特に僕の第一言語は日本語なので、英語の授業は半分くらいしか理解できません。そんな状態で復習もせずに授業を受けていては、どんどん分からないことが増えていって、まったく面白くなくなります。

もちろんすぐに復習をして理解すれば良いのですが、僕は昔から復習が苦手でした。復習には時間がかかるしノートも全然取れてない、教授は毎授業後に復習教材なんて配ってくれません。楽しく、簡単に、でもしっかり内容が理解できる復習方法があれば、難しい授業にもついていけるようになって面白くなるかも、と思いました。

## 💡 2. 自分の興味や目標との繋がりが見出せない
仮に内容がすべて理解できたとしても、自分にとってどうでも良いことは、当たり前ですが学んでも面白くありません。逆にまったく関係ないと思っていた知識が自分の興味のある分野と結びついていると知った時の「**AHA体験**」は、大きな衝撃を生みます。

授業で習う内容の中で、大切じゃないものなんてありません。そしてほとんどの人は自分の興味のある分野を専攻として選んでいると思います。つまりたいていの授業内容は日常生活で大切なものか、もしくは自分の興味につながっている可能性が高いはずです。ただし、学校では一人一人の事情に合わせて面白く授業をすることなんてできません。だからこそ、授業で習わないような面白いファンファクトを自分だけにパーソナライズして生み出せれば、その授業内容がもっと面白くなるんじゃないかと思ったのです。

## ⚙️ 解決のための「ポジティブなルーティーン」
これらを解決するために、AIを使って授業内容を分析し、楽しく簡単にしっかり復習ができる教材と、一人一人に合わせたファンファクトを生成する、そんなアプリを作ろうと思い立ちました。操作はとても簡単です。

- 授業が始まる前に**録音ボタン**を1回押す
- 授業中はスマホを触らず、ただ**授業に集中する**
- 授業が終わったら**音声をアップロードする**だけ

これだけで、10分程度で復習教材とファンファクト、そしてさまざまな学習をしやすくするためのコンテンツが生成されます。帰りのバスでも、家のソファでも、リラックスできる環境でサッと復習ができ、また明日からの授業が楽しみになる、そんなポジティブなルーティーンが生まれることを願っています。""",
                "review_cards": [
                    {
                        "card_type": "hook",
                        "hero_emoji": "❓",
                        "title": "授業は楽しめていますか？",
                        "content_blocks": [
                            {
                                "type": "quote",
                                "text": "「今の授業、自分の未来に役に立っているのかな…？」そんなモヤモヤを感じたことはありませんか？",
                            },
                            {
                                "type": "paragraph",
                                "text": "本来楽しいはずの授業が退屈に変わってしまう原因は、単に『その場で置いていかれて理解できないから』かもしれません。",
                            },
                            {
                                "type": "paragraph",
                                "text": "leFtureはこのモヤモヤを解消するために生まれました。**スマホを置いて録音するだけ**で、あなたの授業が自動で「わかる」教材に変わっていきます。",
                            },
                        ],
                    },
                    {
                        "card_type": "core_why",
                        "hero_emoji": "🎙️",
                        "title": "録音ボタンを押して放っておくだけ",
                        "content_blocks": [
                            {
                                "type": "paragraph",
                                "text": "使い方はとても簡単。授業が始まる前に**録音ボタンを1回押し**、あとはスマホを触らず目の前の講義に集中するだけです。",
                            },
                            {
                                "type": "callout",
                                "alert_type": "info",
                                "text": "授業が終わったら音声をアップロード！帰りのバスや家のソファでアプリを開けば、復習教材が完成しています。",
                            },
                            {
                                "type": "paragraph",
                                "text": "裏側では、AIが音声を文字起こしし、トピックごとに整理し、要点を抽出するという何段階もの「**魔法のパイプライン**」が動いています。あなたは何もしなくていい、それがこのアプリが一番大切にしているポイントです。",
                            },
                        ],
                    },
                    {
                        "card_type": "gotcha",
                        "hero_emoji": "⚡",
                        "title": "10分で「知識」に変わる裏側",
                        "content_blocks": [
                            {
                                "type": "paragraph",
                                "text": "アップロードから約10分。AIが音声を解析し、ノイズを削ぎ落として高品質な復習コンテンツとファンファクトを自動生成します。",
                            },
                            {
                                "type": "callout",
                                "alert_type": "warning",
                                "text": "アプリを閉じて移動していてもバックグラウンドで処理が進むため、画面を見つめて待つ必要はありません！",
                            },
                            {
                                "type": "paragraph",
                                "text": "この10分の裏側では、文字起こし→トピック分割→要約→復習カード生成→ファンファクト生成という複数のAIタスクが、順番に、時には並行して走っています。気づいたときにはもう復習の準備が整っています。",
                            },
                        ],
                    },
                    {
                        "card_type": "next_action",
                        "hero_emoji": "🚀",
                        "title": "さっそく復習を始めよう",
                        "content_blocks": [
                            {
                                "type": "paragraph",
                                "text": "生成されたコンテンツを使って、リラックスした環境でサッと復習する新しいルーティーンが始まります。",
                            },
                            {
                                "type": "list",
                                "items": [
                                    "授業前に録音ボタンを1回押す",
                                    "授業中はスマホを触らず集中する",
                                    "授業後に音声をアップロードするだけ",
                                ],
                            },
                            {
                                "type": "paragraph",
                                "text": "次は、効果的に理解を深める2つの復習ツール「復習カード」と「詳細ノート」を見てみましょう！",
                            },
                        ],
                    },
                ],
            },
            {
                "topic_index": 2,
                "title": "楽しく深い理解へ",
                "summary": "15分で要点を押さえる復習カードと、文脈まで深く網羅する詳細ノートの活用法。",
                "deep_note_markdown": """## 💡 二つの復習方法
授業で習ったことを定着させるのに、復習はとても有効な手段です。でもなかなか手がつけにくいのはいくつかの理由があると思います。まずきれいな復習教材なんてほとんどありません。だいたいは教授の板書や自分のノートです。それらは読みにくく、後からだとコンテキストがわかりにくい場合もあります。それに、しっかりと復習するには時間がかかります。そんな復習を、なんとか楽しく簡単に、そしてしっかりと学べる時間にできないかと考えた結果、このアプリには二つの復習方法を作りました。

## 🧩 復習カード
授業後すぐに15分程度でさっと復習したいとき、このカードをめくっていくだけで授業中の大切なポイントはしっかりとつかむことができます。1トピックにつき、以下の4枚構成になっています。

- **つかみ (Hook)**: まずは直感的にピンとくる例え話で興味を引く
- **重要ポイント (Core Why)**: そのトピックの核心を、簡潔かつ熱量高く解説
- **ひらめき (Gotcha)**: 授業の中でも特に大切な「ここがポイント！」という部分を深掘り
- **次のアクション (Next Action)**: 学んだことのまとめと、次のトピックへの橋渡し

授業の中でもっともホットな部分だけを抽出し、比喩やできるだけ簡単な言葉を用いて噛み砕いてわかりやすく説明してくれます。イラストや絵文字、箇条書きも使用し、短く楽しく読みやすいカードで復習ができます。

## 📖 詳細ノート
まとまった時間があるときや試験前などの集中して深く勉強する時を想定した、詳細なノートです。これを読めば教授が言った内容はほとんど全て網羅することができます。

授業のトランスクリプトをそのまま読むのは時間がかかり非効率的ですが、AIにまとめを作らせると大切な部分が抜け落ちてしまいます。このノートはトランスクリプトをそのまま読みやすいフォーマットに変換したような、いわば「読む授業」です。

さらにはこれらの文章の**出典**も見れるようになっています。文字を選択して「出典」ボタンを押せば、文字起こしのどの部分でそのことを話していたのかが確認できます。

## 🎯 自信を持って次の授業へ
授業後に明確にわかりやすい復習教材が準備されていれば、復習のハードルが一つ減ります。授業終わりには復習カードでさらっと復習し、しっかり勉強したい時に詳細ノートを読み込む、そうすれば次の授業も、そしてテストも、自信を持って受けに行くことができるようになるのではないでしょうか。""",
                "review_cards": [
                    {
                        "card_type": "hook",
                        "hero_emoji": "💡",
                        "title": "なぜ復習は長続きしないのか？",
                        "content_blocks": [
                            {
                                "type": "quote",
                                "text": "「読みにくいノート」「膨大な時間」…復習のハードルを打ち砕く、タイプの異なる2つのツール！",
                            },
                            {
                                "type": "paragraph",
                                "text": "サクッと学べる「復習カード」と、しっかり深く学べる「詳細ノート」が、復習を無理のない習慣に変えます。",
                            },
                            {
                                "type": "paragraph",
                                "text": "どちらも同じ授業から自動生成されるので、その日の気分や使える時間に合わせて**自由に使い分ける**ことができます。",
                            },
                        ],
                    },
                    {
                        "card_type": "core_why",
                        "hero_emoji": "🧩",
                        "title": "15分でサクッと「復習カード」",
                        "content_blocks": [
                            {
                                "type": "paragraph",
                                "text": "授業直後やスキマ時間に最適なフラッシュカード。1トピック4枚構成で、授業の最もホットな部分を噛み砕いて説明します。",
                            },
                            {
                                "type": "callout",
                                "alert_type": "info",
                                "text": "スワイプしていくだけで「つかみ」「重要ポイント」「ひらめき」「次のアクション」が手軽に把握できます。",
                            },
                            {
                                "type": "paragraph",
                                "text": "カードは読み物としてだけでなく、**ハイライトや自分だけのメモ**を書き込める場所でもあります。気になった一文に線を引いておけば、あとで見返すときにすぐ目に留まります。",
                            },
                        ],
                    },
                    {
                        "card_type": "gotcha",
                        "hero_emoji": "📖",
                        "title": "試験前は「詳細ノート」＆出典追跡",
                        "content_blocks": [
                            {
                                "type": "paragraph",
                                "text": "教授の発言や講義の文脈をまるごと網羅した「読む授業」。AI要約で落ちがちな細部までしっかりカバーします。",
                            },
                            {
                                "type": "callout",
                                "alert_type": "info",
                                "text": "気になる文章を選択して「出典」ボタンを押すと、文字起こしのどの部分で話していたか瞬時に確認できます！",
                            },
                            {
                                "type": "paragraph",
                                "text": "「本当にこんなこと言ってたっけ？」と思ったときも、**出典機能**があればすぐに文字起こしの該当箇所に飛んで確認できるので、AIの要約を鵜呑みにせず安心して勉強できます。",
                            },
                        ],
                    },
                    {
                        "card_type": "next_action",
                        "hero_emoji": "💡",
                        "title": "自分に合った学習スタイルを見つけよう",
                        "content_blocks": [
                            {
                                "type": "paragraph",
                                "text": "普段はカードでライトに復習し、テスト前や週末に詳細ノートで深掘りするのがベストな活用法です。",
                            },
                            {
                                "type": "list",
                                "items": [
                                    "普段の復習：カードをスワイプして15分チェック",
                                    "テスト勉強：詳細ノートで文脈と出典を確認",
                                    "気になる一文はハイライトやメモで残しておく",
                                ],
                            },
                            {
                                "type": "paragraph",
                                "text": "次は、勉強を圧倒的に面白くする「ファンファクト」セクションの秘密へ進みましょう！",
                            },
                        ],
                    },
                ],
            },
            {
                "topic_index": 3,
                "title": "自分自身との繋がり",
                "summary": "プロフィール連携とリアルタイムWeb検索が生み出す、あなた専用のパーソナライズファンファクト。",
                "deep_note_markdown": """## 🧠 学ぶなら自分のお金と時間のため
今あなたが受けている授業は、あなたのためのものです。だからこそ、あなたが楽しまないと意味がないですし、その授業はあなたに何かポジティブな影響を与えてくれるポテンシャルを持っているはずです。あなたが全く興味がない概念も、あなたのキャリアのどこかで考えないといけなくなるかもしれません。あなたの目指すキャリアと全く関係のない内容も、日常生活で役に立つかもしれません。どうせ学ばなければいけないなら、自分のためと思って面白く学んだ方が絶対に得ですよね！

## 💡 感情が動いた記憶と「ファンファクト」セクション
昔、学校の授業でこんな経験はありませんでしたか？

> 教科書の太字や公式は全然覚えられなかったのに、先生がふと話した「その科学者の変人エピソード」や「歴史の裏話」だけは今でもハッキリ覚えている。

脳は、単なる記号よりも「感情が動いたファンファクト」や「自分に関係があること」のほうが圧倒的に覚えやすく、そして楽しいと感じやすいのです。

その感覚を毎授業味わいたいと思って作ったのが「**ファンファクト**」セクションです。作り方はシンプルで、以下の3つの情報を組み合わせています。

- **プロフィール**: 最初に登録してくれた専攻・趣味・将来の夢など
- **今日の授業内容**: その日扱われたトピックやキーワード
- **リアルタイムWeb検索**: 「この概念・理論が今まさに社会や最新ニュースでどう使われているか」という最新情報

これらを掛け合わせることで、一見自分とは無関係に見えた知識が、自分の好きな世界と繋がった瞬間、パッと視界が開けるような「**アハ体験**」が生まれるはずです。

次の授業が待ち遠しくなるような、あなたのためだけの楽しい知識をお届けします。""",
                "review_cards": [
                    {
                        "card_type": "hook",
                        "hero_emoji": "🧠",
                        "title": "感情が動いた記憶は忘れない",
                        "content_blocks": [
                            {
                                "type": "quote",
                                "text": "教科書の太字は忘れても、先生が話した「変人エピソード」だけハッキリ覚えている現象、ありませんか？",
                            },
                            {
                                "type": "paragraph",
                                "text": "人間の脳は、無機質な記号よりも「感情が動いたファンファクト」や「自分に関係があること」を圧倒的に覚えやすくできています。",
                            },
                            {
                                "type": "paragraph",
                                "text": "だったら、その「感情が動く瞬間」を毎回の授業で意図的に作ってしまえばいいんじゃないか——それがこの「**ファンファクト**」セクションが生まれたきっかけです。",
                            },
                        ],
                    },
                    {
                        "card_type": "core_why",
                        "hero_emoji": "🔮",
                        "title": "あなた専用に届く「ファンファクト」",
                        "content_blocks": [
                            {
                                "type": "paragraph",
                                "text": "最初に登録したプロフィール（専攻・趣味・将来の夢など）をもとに、授業内容とあなたの興味をAIが自動で繋ぎます。",
                            },
                            {
                                "type": "callout",
                                "alert_type": "info",
                                "text": "一見無関係に見えた知識が自分の好きな世界と結びつく、パッと視界が開けるような「AHA（アハ）体験」が生まれます。",
                            },
                            {
                                "type": "paragraph",
                                "text": "たとえば同じ「熱力学」の授業でも、料理が好きな人にはキッチンの話で、スポーツが好きな人には筋肉の代謝の話で説明してくれます。同じ内容でも、**あなた専用の切り口**が用意されているんです。",
                            },
                        ],
                    },
                    {
                        "card_type": "gotcha",
                        "hero_emoji": "🌐",
                        "title": "リアルタイムWeb検索と「生の知識」",
                        "content_blocks": [
                            {
                                "type": "paragraph",
                                "text": "必要に応じてリアルタイムでWeb検索を行い、「この概念が今まさに社会や最新ニュースでどう使われているか」まで補足してくれます。",
                            },
                            {
                                "type": "callout",
                                "alert_type": "warning",
                                "text": "教科書の古い知識が、あなたのキャリアや日常に繋がる生きた知識へと進化します！",
                            },
                            {
                                "type": "paragraph",
                                "text": "単なる豆知識で終わらせず、「これは今の世界のどこで使われているのか」まで踏み込んで教えてくれるので、テストのためだけじゃない、**一生使える知識**として頭に残りやすくなります。",
                            },
                        ],
                    },
                    {
                        "card_type": "next_action",
                        "hero_emoji": "🎯",
                        "title": "プロフィールを登録して体験しよう",
                        "content_blocks": [
                            {
                                "type": "paragraph",
                                "text": "プロフィールを充実させて、あなたのためだけに生成される楽しい知識を体験してください。",
                            },
                            {
                                "type": "list",
                                "items": [
                                    "プロフィールに専攻や興味・夢を入力",
                                    "毎授業ごとのパーソナライズファンファクトを楽しむ",
                                    "リアルタイムWeb検索でつながる最新トピックもチェック",
                                ],
                            },
                            {
                                "type": "paragraph",
                                "text": "最後は、学習を支える便利機能群とleFtureが目指すワクワクする未来について紹介します！",
                            },
                        ],
                    },
                ],
            },
            {
                "topic_index": 4,
                "title": "leFtureの未来：真の学びと成長の可視化",
                "summary": "アナウンスメントやトピックマップなどの機能と、成長の証「学びの銀河」への展望。",
                "deep_note_markdown": """## 🛠️ 学習に役立つその他の機能
これまで復習とファンファクトの二つの機能について紹介しましたが、leFtureには他にも、学習に役立つ機能があります。

- **📢 アナウンスメント**: 教授が授業中に行った連絡事項や学習のヒントを抜き出します。期限があるものは日付まで記録されます。スワイプで完了・未完了を更新できます。
- **🏷️ キーワード**: 各トピックごとのキーワードを抽出します。自分でその意味や説明を追加できます。
- **🗺️ トピックマップ**: その授業の大きなトピックを把握し、その中にどんな小トピックが含まれているのかを確認できます。トピック同士の繋がりも矢印で表示されます。
- **✍️ ハイライトとメモ**: 復習カードと詳細ノートの文章の中で重要な部分があれば、ハイライトができます。また、自分だけのメモを残しておくこともできます。
- **⏱️ 授業モーメント**: 授業中に「面白い」「難しい」「後で確認したい」と思った時、ワンタップでそのタイムスタンプを記録できます。後から文字起こしページから確認できます。

## 🚀 leFtureが目指す「3つのエンタメ」
しかし、これらはleFtureの最終形態ではありません。このアプリの本来の目的はみなさんが未来にワクワクできるようにサポートすることです。つまり授業はもちろん、クラブ活動やアルバイト、個人プロジェクト、さらには日々考えていることまで含めたすべての学習や経験を、自分の成長のため、目標のため、あるいは楽しみのためだと思えるようになることです。みなさんが今までしんどかったことを、未来のためのエンタメに変えることです。

僕はこのアプリに**3つのエンタメ要素**を盛り込もうと思っています。

### ⚡ 短期のエンタメ：復習セッション
授業直後に「わからない」を解消し、次の授業での迷子をなくす濃い15分間。
授業の録音から「楽しく、簡単に、しっかりと」復習できるコンテンツが生成され、さらにはその授業が自分の興味や目標にどう結びついるのかが示されます。

### 🤝 中期のエンタメ：真の学び場
面白いことを好きなだけ好きなように。理解者と共に創る学びのセッション。
復習コンテンツから浮かんだ小さな疑問や、日々の行動でふと思いついたアイデアなどを、AIと共に深めていきます。テストや成績のためじゃない、面白いから学びたくなる、そんなセッションを作ります。
今までの習ってきた内容、考えてきたこと、性格や価値観などを踏まえ、あなただけの理解者として寄り添いながら学習できます。

### 🌌 長期のエンタメ：学びの銀河
自分の未来につながるすべてが重なり合って形成される自分だけの銀河。
ホーム画面にある巨大な銀河は、今はただの飾りです。でも将来これは、あなたの成長と共に大きく美しく育っていく、「**成長の証**」となります。授業で習ったこと、日常で思いついたアイデア、すべてが小さな星となり、ここに蓄積されていきます。
同時に自分のプロフィールがどんどん更新され、自分の興味や目標がより明確になっていきます。

## 💖 最後に
今は短期のエンタメまでしか実装できていません（そしてこれでもまだ完成ではありません）。これからこのアプリには、あなたを理解してくれるパートナーAIと、成長を象徴する銀河が追加される予定です。楽しみにしていてくださいね。

改めて、このアプリに興味を持ってくださり、そしてここまで読んでくださり、ありがとうございました。今後ともleFtureをよろしくお願いします。

あなたの未来を応援しています。""",
                "review_cards": [
                    {
                        "card_type": "hook",
                        "hero_emoji": "🚀",
                        "title": "これだけじゃない！leFtureの全貌",
                        "content_blocks": [
                            {
                                "type": "quote",
                                "text": "まだまだ紹介しきれていない機能がたくさんあります！そして、このアプリが目指すワクワクする未来についてもお話しします！",
                            },
                            {
                                "type": "paragraph",
                                "text": "日々の学習を網羅するツール群と、勉強を「未来のためのエンタメ」に変える長期的なロードマップをご紹介します。",
                            },
                            {
                                "type": "paragraph",
                                "text": "ここまで紹介してきた復習カード・詳細ノート・ファンファクトは、実はこのアプリが目指す大きな未来の**ほんの入り口**に過ぎません。",
                            },
                        ],
                    },
                    {
                        "card_type": "core_why",
                        "hero_emoji": "🛠️",
                        "title": "学習を完全サポートする機能群",
                        "content_blocks": [
                            {
                                "type": "paragraph",
                                "text": "復習をさらに快適にするための多彩な機能が揃っています。",
                            },
                            {
                                "type": "list",
                                "items": [
                                    "📢 アナウンスメント: 課題期限や連絡事項を自動抽出",
                                    "🏷️ キーワード: トピックごとの重要用語抽出＆意味の追記",
                                    "🗺️ トピックマップ: 講義全体の構造と繋がりの視覚化",
                                    "✍️ ハイライト＆メモ / ⏱️ 授業モーメント: 重要な瞬間のタイムスタンプ保存",
                                ],
                            },
                            {
                                "type": "paragraph",
                                "text": "これらの機能は全て、「**復習のハードルを一つでも減らす**」という同じ想いから生まれています。小さな機能の積み重ねが、毎日の学習を少しずつ楽にしてくれます。",
                            },
                        ],
                    },
                    {
                        "card_type": "gotcha",
                        "hero_emoji": "🌌",
                        "title": "未来のエンタメ「学びの銀河」",
                        "content_blocks": [
                            {
                                "type": "paragraph",
                                "text": "leFtureの最終目標は、みなさんのすべての学習や経験を未来のためのエンタメに変えることです。",
                            },
                            {
                                "type": "callout",
                                "alert_type": "info",
                                "text": "短期（復習）、中期（真の学び場）、長期（ホームの巨大な銀河があなたの成長と共に育つ『学びの銀河』）へと進化していきます！",
                            },
                            {
                                "type": "paragraph",
                                "text": "今はまだ「短期のエンタメ」である復習セッションしか実装されていませんが、これは3段階あるロードマップの最初の1歩にすぎません。これから、あなただけの理解者となるパートナーAIや、成長を目に見える形にする「**学びの銀河**」が少しずつ姿を現していきます。",
                            },
                        ],
                    },
                    {
                        "card_type": "next_action",
                        "hero_emoji": "💖",
                        "title": "チュートリアル完了！",
                        "content_blocks": [
                            {
                                "type": "paragraph",
                                "text": "これでチュートリアルは完了です。ここまで読んでいただき本当にありがとうございました！",
                            },
                            {
                                "type": "list",
                                "items": [
                                    "次の授業でさっそく録音ボタンを押す",
                                    "10分後の新しい復習ルーティーンを体感する",
                                    "アナウンスメントやキーワードなど、他の機能も触ってみる",
                                ],
                            },
                            {
                                "type": "paragraph",
                                "text": "あなたの未来がワクワクするものになるよう、leFtureは全力で応援しています！",
                            },
                        ],
                    },
                ],
            },
        ],
    },
}


def get_tutorial_content(language_code: str) -> dict:
    """言語コードに応じたチュートリアルコンテンツを取得する。
    未対応言語はenへフォールバックする(クライアント側get_tutorial_contentと同じ挙動)。
    """
    return TUTORIAL_CONTENT.get(language_code, TUTORIAL_CONTENT["en"])
