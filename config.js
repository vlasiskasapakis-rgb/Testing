// Walking Memory — backend settings.
// Fill these in from your Supabase project: Project Settings → API.
// The anon key is meant to be public; access is enforced by the row-level
// security policies in supabase/schema.sql, so never put the service_role key here.
// While these are empty the app still works as a read-only guide of the built-in stories.
window.WM_CONFIG = {
  SUPABASE_URL: 'https://sqxhzlwqqhodbhfdnaxv.supabase.co',
  SUPABASE_ANON_KEY: 'sb_publishable_mLGyvgBorl9W5iHgcyiIpg_o-AQT0Xg',
  // ECHOES Heritage Digital Twin Ontology (HDTO) namespace, as used by the ECHOES knowledge base
  // and other ECHOES applications (e.g. OCRA).
  HDT_NS: 'http://isl.ics.forth.gr/ontology/echoes/'
};
