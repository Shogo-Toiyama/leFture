export type Locale = 'ja' | 'en';

export interface LanguageOption {
  code: Locale;
  label: string;
}

export const SUPPORTED_LANGUAGES: LanguageOption[] = [
  { code: 'ja', label: '日本語' },
  { code: 'en', label: 'English' },
];

/** Top page copy. Grounded in the in-app tutorial course "Welcome to leFture". */
export interface HomeTranslations {
  hero: {
    eyebrow: string;
    titleTop: string;
    titleGlow: string;
    subtitle: string;
    primaryCta: string;
    secondaryCta: string;
    scrollHint: string;
  };
  why: {
    eyebrow: string;
    heading: string;
    lead: string;
    problems: { no: string; title: string; body: string }[];
    closing: string;
  };
  how: {
    eyebrow: string;
    heading: string;
    steps: { when: string; title: string; body: string }[];
    pipelineLabel: string;
    pipelineStages: string[];
    pipelineNote: string;
    result: string;
  };
  what: {
    eyebrow: string;
    heading: string;
    lead: string;
    cards: {
      tag: string;
      title: string;
      subtitle: string;
      body: string;
      deckHint: string;
      deck: { kind: string; emoji: string; title: string; body: string }[];
    };
    notes: {
      tag: string;
      title: string;
      subtitle: string;
      body: string;
      citationTitle: string;
      citationBody: string;
      sampleHeading: string;
      sampleLine: string;
      sampleAction: string;
      sampleQuote: string;
      sampleTimestamp: string;
    };
    facts: {
      tag: string;
      title: string;
      subtitle: string;
      body: string;
      ahaLabel: string;
      lecture: string;
      personas: { emoji: string; who: string; angle: string }[];
      ingredients: string[];
    };
  };
  tools: {
    eyebrow: string;
    heading: string;
    lead: string;
    items: { emoji: string; title: string; body: string }[];
  };
  road: {
    eyebrow: string;
    heading: string;
    lead: string;
    stages: {
      emoji: string;
      term: string;
      title: string;
      body: string;
      status: string;
    }[];
  };
  cta: {
    heading: string;
    sub: string;
    button: string;
    secondary: string;
  };
}

export interface FaqItem {
  id: string;
  question: string;
  answer: string;
  action?: {
    label: string;
    url: string;
  };
  note?: string;
}

export interface FaqTranslations {
  title: string;
  subtitle: string;
  badge: string;
  items: FaqItem[];
  stillHaveQuestions: string;
  contactLink: string;
}

export interface DownloadModalTranslations {
  title: string;
  subtitle: string;
  iosTitle: string;
  iosDesc: string;
  iosBadge: string;
  iosButton: string;
  androidTitle: string;
  androidDesc: string;
  androidBadge: string;
  note: string;
}

export interface Translations {
  nav: {
    home: string;
    terms: string;
    privacy: string;
    faq: string;
    contact: string;
    downloadApp: string;
  };
  downloadModal: DownloadModalTranslations;
  home: HomeTranslations;
  terms: {
    title: string;
    subtitle: string;
    loading: string;
    errorTitle: string;
    errorDesc: string;
    retry: string;
    effectiveDate: string;
  };
  privacy: {
    title: string;
    subtitle: string;
    loading: string;
    errorTitle: string;
    errorDesc: string;
    retry: string;
    effectiveDate: string;
  };
  faq: FaqTranslations;
  contact: {
    title: string;
    subtitle: string;
    nameLabel: string;
    namePlaceholder: string;
    emailLabel: string;
    emailPlaceholder: string;
    categoryLabel: string;
    catBug: string;
    catFeedback: string;
    catAccount: string;
    catOther: string;
    messageLabel: string;
    messagePlaceholder: string;
    attachmentLabel: string;
    attachmentHint: string;
    attachmentMax: string;
    removeAttachment: string;
    submitButton: string;
    submitting: string;
    successTitle: string;
    successDesc: string;
    ticketCodeLabel: string;
    sendAnother: string;
    errorRequired: string;
    errorGeneric: string;
  };
  footer: {
    tagline: string;
    rights: string;
    audience: string;
  };
}

