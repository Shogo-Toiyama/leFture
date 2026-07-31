/// The legal/regulatory region this build of the app is released under.
///
/// Unlike [displayLanguageControllerProvider] (which the user picks), this
/// is not user-configurable -- it reflects which jurisdiction's legal
/// document content (see the `region` column on the `legal_documents`
/// Supabase table) should be shown. Update this when leFture is actually
/// released into a new region with its own legal requirements (e.g. Japan
/// under the Act on the Protection of Personal Information).
const String kAppLegalRegion = 'us';
