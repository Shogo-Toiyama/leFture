-- Brings the already-created `legal_documents` table under migration
-- control (it previously existed only as a manual change in the project),
-- and seeds it with the version_02 legal document content (English).
--
-- Schema: one row per (slug, locale). Readers fall back to locale='en'
-- when a translation doesn't exist yet for the user's display language.

create or replace function public.set_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

create table if not exists public.legal_documents (
  slug text not null,
  locale text not null default 'en'::text,
  version integer not null default 1,
  title text not null,
  content_markdown text not null,
  effective_date date not null,
  updated_at timestamp with time zone not null default now(),
  constraint legal_documents_pkey primary key (slug, locale)
);

drop trigger if exists trg_set_updated_at on public.legal_documents;
create trigger trg_set_updated_at
  before update on public.legal_documents
  for each row
  execute function public.set_updated_at();

insert into public.legal_documents (slug, locale, version, title, content_markdown, effective_date)
values
(
  'privacy_policy',
  'en',
  2,
  'Privacy Policy for leFture',
  $md$# Privacy Policy for leFture

## 1. Introduction
Welcome to leFture ("we," "our," or "us"), operated by Shogo Toiyama. This Privacy Policy explains how we collect, use, disclose, and safeguard your information when you use our mobile application (the "App").

By accessing or using leFture, you agree to the collection and use of information in accordance with this Privacy Policy. If you do not agree with the terms of this Privacy Policy, please do not use the App.

## 2. Information We Collect
We collect information that you directly provide to us, as well as information collected automatically when you use the App.

**2.1 Information You Provide to Us**
* **Account Information:** Your email address and username. You may sign in using Apple Sign-In or Google Sign-In (if you use Apple Sign-In with the "Hide My Email" option, we only receive the anonymized email address Apple issues).
* **Profile Information:** Information you choose to provide about your interests, future goals, and preferences.
* **Academic & Course Data:** Details regarding your courses, such as school name, course codes, course titles, and professor names.
* **User Content:** Audio recordings of lectures you capture using the App, as well as the study notes, text, and memos you create.

**2.2 Information We Collect Automatically**
* **Device Information:** We may collect specific device information (such as device model, OS version, app version, and locale) strictly when you contact us for customer support, in order to identify and resolve bugs quickly.
* **Log & Usage Data:** For security, authentication, and infrastructure reliability, our systems and infrastructure providers may automatically log your IP address when you interact with the App.

## 3. How We Use Your Information
We use the collected information for the following purposes:
* **Core Functionality:** To process and analyze your lecture audio recordings and generate interactive study notes and related learning content.
* **Personalization:** To tailor the generated content and future features (such as AI chatbots) to your specific profile, interests, and course details.
* **App Improvement & Support:** To troubleshoot bugs, provide customer support, and maintain the overall stability of the App.

## 4. How We Share Your Information
We do not sell your personal information. We only share your data under the following circumstances:

**4.1 Infrastructure & Service Providers**
We utilize trusted third-party service providers (such as Google Cloud, Cloudflare, Supabase, and Resend) to host our database, handle authentication, store files, route emails, and maintain backend operations. These providers process your data strictly to facilitate our services.

**4.2 AI Service Providers**
To transcribe audio, generate intelligent study notes, and enrich content with supplementary information, we securely transmit audio and text data to third-party artificial intelligence and data providers, including Google AI Studio, TogetherAI, Modal, and **Cloudflare Workers AI** (used to transcribe lecture audio and to generate topic images). We also use **Tavily**, a web search API, to retrieve supplementary information (such as source material for "fun facts") based on queries derived from your lecture content.

**Important:** We ensure through our provider agreements that your audio recordings, personal data, and generated notes are strictly processed for your immediate use. **Your data is NEVER used by these third parties to train or retrain their AI models.**

**4.3 Legal Requirements**
We may disclose your information if required to do so by law or in response to valid requests by public authorities (e.g., a court or a government agency).

**4.4 International Data Transfers**
Our service providers may store and process your information in countries other than your own, including the United States, where data protection laws may differ from those in your jurisdiction. Where required by applicable law, we rely on appropriate safeguards (such as our providers' standard contractual clauses or equivalent mechanisms) to protect your information when it is transferred internationally.

## 5. Data Retention and Deletion
We retain your personal information and user content for as long as your account is active or as needed to provide you with our services.

* **Account Deletion:** You can delete your account and associated data at any time using the account deletion feature provided within the App.
* **Immediate & Permanent Deletion:** When you request account deletion, your account, personal data, lecture audio recordings, generated notes, and associated files are immediately and irrevocably deleted (hard deleted) from our primary databases and storage systems. Once confirmed, this action cannot be undone and your data cannot be recovered. (Note: Customer support ticket histories and related support attachments may be retained separately for customer service, security, and compliance purposes.)
* **Individual Content Deletion:** Deleting an individual lecture or course moves it to a trash state for a limited grace period before it is permanently purged, allowing you to recover it if deleted by mistake. This is distinct from account deletion, which is immediate and permanent.
* **Debug Data:** Intermediate processing data and logs used strictly for debugging purposes are retained only temporarily and are automatically deleted once they are no longer needed for system improvements.

## 6. Data Security
We implement commercially reasonable technical and organizational measures to protect your personal information against accidental or unlawful destruction, loss, alteration, and unauthorized disclosure or access. However, please be aware that no method of transmission over the internet or method of electronic storage is 100% secure, and we cannot guarantee the absolute security of your data.

## 7. Your Privacy Rights
Depending on your location, you may have certain rights regarding your personal information, which may include the right to access, correct, update, delete, or receive a copy of your personal data, and, where applicable under laws such as the GDPR or the CCPA/CPRA, the right to restrict or object to certain processing and the right to lodge a complaint with your local data protection authority. You can manage your information directly within the App's settings or by contacting us using the information provided below. We will not discriminate against you for exercising your privacy rights.

## 8. Children's Privacy
Our App is not intended for use by children under the age of 13. We do not knowingly collect or solicit personal information from anyone under the age of 13. If you are under 13, please do not use the App or send any information about yourself to us. If we learn that we have collected personal information from a child under 13 without verification of parental consent, we will delete that information as quickly as possible.

## 9. Changes to This Privacy Policy
We may update this Privacy Policy from time to time to reflect changes in our practices or for other operational, legal, or regulatory reasons. If we make material changes, we will notify you by updating the "Effective Date" at the top of this Privacy Policy and, if applicable, providing a notice within the App. Your continued use of the App after the changes take effect constitutes your acceptance of the revised policy.

## 10. Contact Us
If you have any questions, concerns, or requests regarding this Privacy Policy or how we handle your data, please contact us at:

**Email:** lefture.app@gmail.com
$md$,
  '2026-07-31'
),
(
  'terms_of_service',
  'en',
  2,
  'Terms of Service for leFture',
  $md$# Terms of Service for leFture

## 1. Acceptance of Terms
These Terms of Service ("Terms") govern your access to and use of the leFture mobile application (the "App"), provided by Shogo Toiyama ("we," "us," or "our"). By downloading, accessing, or using the App, you agree to be bound by these Terms. If you do not agree to these Terms, you may not use the App.

## 2. Description of Service and Usage Limits
leFture provides an AI-powered platform designed to transcribe educational lectures and generate interactive study notes.
* **Free Access and AI Credits:** The App is currently provided free of charge. However, due to the computational costs associated with artificial intelligence processing, your use of AI-driven features is subject to strict usage limits (e.g., a fixed allocation of processing credits per month).
* **Modification of Service:** At this current phase, additional credits cannot be purchased. We reserve the right to modify these limits, adjust the credit allocation, or introduce paid features in the future at our sole discretion.

## 3. Recording Consent and Legal Compliance
This is a critical requirement for using leFture. By using the App to record any audio, you expressly acknowledge and agree to the following:
* **Obligation to Obtain Consent:** Laws regarding audio recording vary significantly by jurisdiction. In many regions (including California), the law requires the consent of all parties involved in a recording. You are solely and exclusively responsible for obtaining explicit, legally valid consent from professors, instructors, students, and any other individuals before recording them.
* **Copyright and Institutional Policies:** Educational lectures may be protected by copyright owned by the instructor or the institution. You agree to use the recordings and generated notes strictly for your personal, non-commercial educational purposes. You assume full liability for any violation of institutional policies or copyright laws. We strictly disclaim any liability arising from your failure to obtain necessary permissions.

## 4. AI Accuracy and Educational Disclaimer
* **No Guarantee of Accuracy:** leFture utilizes third-party artificial intelligence models to transcribe audio and summarize content. AI technologies are experimental and subject to errors, omissions, or "hallucinations." We do not warrant or guarantee the accuracy, completeness, or reliability of any generated study notes or content.
* **User Responsibility:** The App is a supplemental study tool, not a replacement for attending classes or studying original materials. You are solely responsible for verifying the facts and accuracy of the generated notes before relying on them for exams or assignments.
* **Academic Integrity:** You agree to use the App in full compliance with your educational institution's academic integrity guidelines and honor codes.

## 5. User Accounts
To use certain features of the App, you must register for an account.
* **Age Requirement:** You must be at least 13 years old to use the App.
* **Account Security:** You are responsible for safeguarding your account credentials (such as your login information via third-party providers) and for all activities that occur under your account. You agree to notify us immediately of any unauthorized access to or use of your account.

## 6. Prohibited Conduct
You agree not to use the App for any unlawful purpose or in any way that interrupts, damages, or impairs the service. Specifically, you agree not to:
* Attempt to bypass, manipulate, or exploit the AI credit limits or access the App through unauthorized means.
* Reverse engineer, decompile, or disassemble any part of the App.
* Upload or transmit any viruses, malware, or destructive code.
* Use the App in a way that infringes upon the intellectual property rights, privacy rights, or other legal rights of any third party.
* Engage in any behavior that constitutes harassment, bullying, or hate speech within any future sharing or community features of the App.

## 7. Intellectual Property Rights
* **Our Property:** The App, including its original code, design, layout, algorithms, and branding (collectively, the "Service Content"), is the exclusive property of Shogo Toiyama and is protected by copyright, trademark, and other intellectual property laws.
* **Your Content:** You retain full ownership rights to the audio recordings and the specific notes you generate ("User Content"). By uploading your content, you grant us a temporary, non-exclusive license to process, store, and transmit your User Content solely for the purpose of operating the App and providing you with the requested AI generation services.

## 8. Indemnification
You agree to indemnify, defend, and hold harmless Shogo Toiyama and leFture from and against any claims, liabilities, damages, losses, and expenses (including reasonable legal fees) arising out of or in any way connected with: (i) your recording of any individual without obtaining legally valid consent; (ii) your violation of any institutional policy, academic integrity rule, or copyright law in connection with your use of the App; (iii) your violation of these Terms; or (iv) your violation of any rights of a third party.

## 9. Termination
We may terminate or suspend your account and bar access to the App immediately, without prior notice or liability, under our sole discretion, for any reason whatsoever and without limitation, including but not limited to a breach of these Terms. Upon termination, your right to use the App will cease immediately, and your data may be subject to deletion in accordance with our Privacy Policy.

## 10. Disclaimer of Warranties
THE APP IS PROVIDED ON AN "AS IS" AND "AS AVAILABLE" BASIS. WE MAKE NO REPRESENTATIONS OR WARRANTIES OF ANY KIND, EXPRESS OR IMPLIED, REGARDING THE OPERATION OF THE APP OR THE INFORMATION, CONTENT, OR MATERIALS INCLUDED IN THE APP. TO THE FULL EXTENT PERMISSIBLE BY APPLICABLE LAW, WE DISCLAIM ALL WARRANTIES, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. WE DO NOT WARRANT THAT THE APP WILL BE UNINTERRUPTED, ERROR-FREE, OR COMPLETELY SECURE FROM DATA LOSS.

## 11. Limitation of Liability
TO THE MAXIMUM EXTENT PERMITTED BY APPLICABLE LAW, IN NO EVENT SHALL SHOGO TOIYAMA BE LIABLE FOR ANY INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, OR PUNITIVE DAMAGES, INCLUDING WITHOUT LIMITATION, LOSS OF PROFITS, DATA, USE, GOODWILL, OR OTHER INTANGIBLE LOSSES, RESULTING FROM (I) YOUR ACCESS TO OR USE OF OR INABILITY TO ACCESS OR USE THE APP; (II) ANY CONDUCT OR CONTENT OF ANY THIRD PARTY ON THE APP; (III) ANY CONTENT OBTAINED FROM THE APP; AND (IV) UNAUTHORIZED ACCESS, USE OR ALTERATION OF YOUR TRANSMISSIONS OR CONTENT, WHETHER BASED ON WARRANTY, CONTRACT, TORT (INCLUDING NEGLIGENCE) OR ANY OTHER LEGAL THEORY.

## 12. Governing Law and Dispute Resolution
These Terms shall be governed and construed in accordance with the laws of the State of California, United States, without regard to its conflict of law provisions. Any legal action or proceeding related to the App shall be brought exclusively in a state or federal court located in California, and you hereby consent to the personal jurisdiction and venue therein.

## 13. Changes to Terms
We reserve the right, at our sole discretion, to modify or replace these Terms at any time. If a revision is material, we will try to provide at least 30 days' notice prior to any new terms taking effect. By continuing to access or use our App after those revisions become effective, you agree to be bound by the revised terms.

## 14. General Provisions
* **Severability:** If any provision of these Terms is found to be unenforceable, the remaining provisions will remain in full force and effect.
* **Entire Agreement:** These Terms, together with the Privacy Policy, constitute the entire agreement between you and us regarding the App and supersede any prior agreements.
* **Assignment:** You may not assign or transfer these Terms without our prior written consent. We may assign these Terms without restriction.
* **No Waiver:** Our failure to enforce any right or provision of these Terms will not be considered a waiver of that right or provision.

## 15. Contact Us
If you have any questions about these Terms, please contact us at:

**Email:** lefture.app@gmail.com
$md$,
  '2026-07-31'
)
on conflict (slug, locale) do update set
  version = excluded.version,
  title = excluded.title,
  content_markdown = excluded.content_markdown,
  effective_date = excluded.effective_date;
