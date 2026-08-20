import { Translations } from '../types';

export const en: Translations = {
  nav: {
    home: 'Home',
    terms: 'Terms of Service',
    privacy: 'Privacy Policy',
    contact: 'Contact',
    downloadApp: 'Coming Soon',
  },
  home: {
    hero: {
      eyebrow: 'Lectures for the Futures',
      titleTop: 'Put your phone down.',
      titleGlow: 'Just focus.',
      subtitle:
        'leFture turns lecture recordings into bite-sized review cards, deep notes, and personalized fun facts. Free yourself from the stress of falling behind, and turn every class into an exciting, future-shaping journey.',
      primaryCta: 'Coming Soon on App Store',
      secondaryCta: 'See how it works',
      scrollHint: 'Scroll',
    },
    why: {
      eyebrow: 'Why we built it',
      heading: 'There are two primary reasons lectures get boring.',
      lead: 'This app started from a personal frustration: the feeling that school could be so much more than it was. Why did lectures that should be exciting so often feel like a chore? These two answers are what we kept coming back to.',
      problems: [
        {
          no: '01',
          title: "You can't keep up in real time",
          body: 'Fall behind once, and the next lecture is incomprehensible. My native language is Japanese, so I could only follow about half of an English lecture. You do not understand, so it is not interesting. It is not interesting, so you understand even less. Then it finally clicks during exam prep, and you think: if only I had understood this earlier, I would have loved that class.',
        },
        {
          no: '02',
          title: 'It never connects to what you care about',
          body: "Even if you follow every word, learning something that feels irrelevant to you is unexciting. But when knowledge you assumed was unrelated links straight to something you love, you get a mind-blowing AHA moment. A professor can't tailor a lecture to every single student — but AI can.",
        },
      ],
      closing:
        'So we set out to make reviewing fun, effortless, and solid.',
    },
    how: {
      eyebrow: 'The Magic Pipeline',
      heading: 'There are only three things you do.',
      steps: [
        {
          when: 'Before class',
          title: 'Tap the record button once',
          body: 'That is the whole setup. Leave it on the desk or in your pocket.',
        },
        {
          when: 'During class',
          title: 'Put your phone down and focus',
          body: 'No frantic note-taking. If something sparks your curiosity or feels tricky, just tap once to react. Be fully present for the lecture.',
        },
        {
          when: 'After class',
          title: 'Upload the audio. Done.',
          body: 'From here it is the AI’s job. You just walk out of the room like any other day.',
        },
      ],
      pipelineLabel: 'About 10 minutes, in the background',
      pipelineStages: [
        'Transcription',
        'Noise removal',
        'Topic segmentation',
        'Summarization',
        'Review card generation',
        'Deep note generation',
        'Fun fact generation',
      ],
      pipelineNote:
        'Processing continues even if you close the app. No need to stare at a loading screen.',
      result:
        'On the bus, or on your couch. Before you think to check, high-quality review material is waiting.',
    },
    what: {
      eyebrow: 'What you get',
      heading: 'One lecture. Three ways in.',
      lead: 'Pick whichever fits your mood and the time you have left. All of it is generated from the same lecture, so you can move freely between them.',
      cards: {
        tag: '15 min',
        title: 'Review Cards',
        subtitle: '15 min, right after class',
        body: 'Four cards per topic, always in the same rhythm, breaking down only the best parts of the lecture. Illustrations, emoji, and bite-sized lists make it feel more like glancing than studying. Highlight any line that catches your eye and leave your own note on it.',
        deckHint: 'Tap to flip',
        deck: [
          {
            kind: 'Hook',
            emoji: '❓',
            title: 'Are you enjoying class?',
            body: '"Is this lecture really helping my future?" Ever felt that lingering doubt? An intuitive analogy grabs your attention before anything else.',
          },
          {
            kind: 'Core Why',
            emoji: '🎙️',
            title: 'Just hit record and focus',
            body: 'The heart of the topic, explained concisely and with real enthusiasm. Behind the scenes a multi-stage Magic Pipeline runs — and you lift no finger. That is the whole point.',
          },
          {
            kind: 'Gotcha',
            emoji: '⚡',
            title: '10 minutes to structured knowledge',
            body: 'A deep dive into the single most important "pay attention here" moment. Transcription, segmentation, summarization, and card generation run one after another — sometimes in parallel.',
          },
          {
            kind: 'Next Action',
            emoji: '🧭',
            title: 'Wrap up, then bridge forward',
            body: 'The takeaways, plus a bridge into the next topic. You leave with something concrete to do tomorrow, which is how reviewing turns into a habit.',
          },
        ],
      },
      notes: {
        tag: 'Deep dive',
        title: 'Deep Notes',
        subtitle: 'A readable lecture with source citations',
        body: 'Read this and you cover nearly everything the professor said. Raw transcripts are exhausting, and generic AI summaries drop the technical nuance that mattered. Deep Notes reformat the entire lecture into a structured, genuinely readable guide — built for the night before an exam.',
        citationTitle: 'Source tracking',
        citationBody:
          'If you ever think "wait, did they actually say that?", select the sentence and tap Source. You jump straight to that exact moment in the transcript — so you can trust the AI without taking it on faith.',
        sampleHeading: '⚙️ The Solution: A Positive Learning Routine',
        sampleLine:
          'AI analyzes the lecture audio to generate easy-to-digest review materials and personalized fun facts.',
        sampleAction: 'Source',
        sampleQuote:
          '"…so what matters here is the idea of taking reviewing off your list of chores entirely."',
        sampleTimestamp: 'Transcript 24:18',
      },
      facts: {
        tag: 'Just for you',
        title: 'Fun Facts',
        subtitle: 'Engineered AHA moments',
        body: 'You forget the bold terms in the textbook, but you never forget the strange aside your professor threw in. Human brains hold on to stories that move you and information that is personally relevant. So we make that happen on purpose, every single lecture.',
        ahaLabel: 'AHA Moment',
        lecture: "Today's lecture: Thermodynamics",
        personas: [
          {
            emoji: '🍳',
            who: 'If you love cooking',
            angle: 'Why temperature control governs flavor in sous-vide',
          },
          {
            emoji: '🏃',
            who: 'If you are an athlete',
            angle: 'What escapes as heat when muscle makes energy',
          },
          {
            emoji: '🎧',
            who: 'If you love music',
            angle: 'The "warm sound" of tube amps, and the physics of heat',
          },
        ],
        ingredients: [
          'Your profile — major, hobbies, career dreams',
          "Today's lecture topics and keywords",
          'Live web search for how the theory is used right now',
        ],
      },
    },
    tools: {
      eyebrow: 'Companion tools',
      heading: 'Small tools that shave off one more piece of friction.',
      lead: 'A whole suite sits around Review Cards and Deep Notes. Every one of them comes from the same belief: remove one more excuse not to review.',
      items: [
        {
          emoji: '📢',
          title: 'Announcements',
          body: 'Pulls action items and deadlines out of the lecture. Swipe to mark them done.',
        },
        {
          emoji: '🏷️',
          title: 'Keywords',
          body: 'Essential vocabulary per topic, extracted automatically. Add your own definitions.',
        },
        {
          emoji: '🗺️',
          title: 'Topic Map',
          body: 'A visual overview of the lecture structure and how the topics relate.',
        },
        {
          emoji: '✍️',
          title: 'Highlights & Notes',
          body: 'Underline anything in cards or notes, and write down what you noticed.',
        },
        {
          emoji: '⏱️',
          title: 'Lecture Reactions',
          body: 'One tap while recording. "This is interesting" becomes a bookmark you can return to.',
        },
      ],
    },
    road: {
      eyebrow: 'The road ahead',
      heading: 'Turning learning into entertainment.',
      lead: 'The ultimate mission of leFture is to take learning — previously stressful — and turn it into something you genuinely enjoy. We get there in three stages.',
      stages: [
        {
          emoji: '⚡',
          term: 'Short-term',
          title: 'The 15-minute review session',
          body: 'Clear up confusion right after class so you never feel lost in the next lecture. This is where we start.',
          status: 'Live now',
        },
        {
          emoji: '🤝',
          term: 'Medium-term',
          title: 'A true learning space',
          body: 'Follow your spontaneous curiosity alongside a companion AI that understands your values, history, and personality.',
          status: 'In progress',
        },
        {
          emoji: '🌌',
          term: 'Long-term',
          title: 'The Galaxy of Learning',
          body: 'The galaxy on your home screen becomes a living record of your growth. Every lecture and every idea becomes a glowing star.',
          status: 'The dream',
        },
      ],
    },
    cta: {
      heading: 'Here is to looking forward to tomorrow’s lecture.',
      sub: 'leFture stands for "Lectures for the Futures." We hope the classes you attend every day start to feel like they are genuinely shaping your own future. We are cheering for you.',
      button: 'Coming Soon on App Store',
      secondary: 'Contact us',
    },
  },
  terms: {
    title: 'Terms of Service',
    subtitle: 'Terms & Conditions',
    loading: 'Loading Terms of Service...',
    errorTitle: 'Failed to load document',
    errorDesc: 'Please check your connection and try again.',
    retry: 'Retry',
    effectiveDate: 'Last Updated',
  },
  privacy: {
    title: 'Privacy Policy',
    subtitle: 'Data & Privacy Protection',
    loading: 'Loading Privacy Policy...',
    errorTitle: 'Failed to load document',
    errorDesc: 'Please check your connection and try again.',
    retry: 'Retry',
    effectiveDate: 'Last Updated',
  },
  contact: {
    title: 'Contact Support',
    subtitle: 'Inquiries & Feedback',
    nameLabel: 'Your Name (Optional)',
    namePlaceholder: 'John Doe',
    emailLabel: 'Email Address',
    emailPlaceholder: 'you@example.com',
    categoryLabel: 'Category',
    catBug: 'Bug Report',
    catFeedback: 'Request / Feedback',
    catAccount: 'Account / Login',
    catOther: 'Other',
    messageLabel: 'Message',
    messagePlaceholder: 'Please describe your inquiry or feedback in detail.',
    attachmentLabel: 'Attach Screenshot (Optional)',
    attachmentHint: 'Drag and drop an image, or click to browse',
    attachmentMax: 'PNG, JPG, WEBP (Max 5MB)',
    removeAttachment: 'Remove image',
    submitButton: 'Send Inquiry',
    submitting: 'Sending...',
    successTitle: 'Inquiry Sent Successfully',
    successDesc: 'Your message has been received. Our team will review and respond via email.',
    ticketCodeLabel: 'Ticket Code',
    sendAnother: 'Send another message',
    errorRequired: 'Please enter your email address and message.',
    errorGeneric: 'Failed to send inquiry. Please try again later.',
  },
  footer: {
    tagline: 'Tap record once, then put your phone down and focus. The AI study companion that connects your lectures to your future.',
    rights: 'All rights reserved.',
    audience: 'leFture — Lectures for the Futures',
  },
};
