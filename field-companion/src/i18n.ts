// Interface texts in Greek and English.
type Dict = Record<string, string>;

const el: Dict = {
  appName: 'Walking Memory · Πεδίο',
  setupTitle: 'Καλώς ήρθες',
  setupLead: 'Γράψε τον κωδικό του τόπου σου και το όνομά σου. Μένουν μόνο σε αυτή τη συσκευή.',
  siteCode: 'Κωδικός τόπου', yourName: 'Το όνομά σου', start: 'Έναρξη', checking: 'Έλεγχος…',
  badSite: 'Άγνωστος κωδικός τόπου.', needOnline: 'Χρειάζεται σύνδεση στο διαδίκτυο την πρώτη φορά.',
  needName: 'Γράψε το όνομά σου.',
  newT: 'Νέα μαρτυρία', noTestimonies: 'Δεν υπάρχουν μαρτυρίες σε αυτή τη συσκευή.',
  nItems: '{n} στοιχεία', nItems1: '1 στοιχείο',
  st_unsent: 'Δεν στάλθηκε', st_partial: 'Στάλθηκε εν μέρει', st_sent: 'Στάλθηκε ✓',
  unsentBanner: 'Έχεις {n} μαρτυρίες που δεν στάλθηκαν.', sendNow: 'Αποστολή τώρα',
  persistWarn: 'Η συσκευή δεν εγγυάται ότι θα κρατήσει τα αρχεία. Πρόσθεσε την εφαρμογή στην αρχική οθόνη και στείλε τις μαρτυρίες σύντομα.',
  httpsWarn: 'Η εφαρμογή πρέπει να ανοίγει με https://.',
  lowSpace: 'Λίγος ελεύθερος χώρος: περίπου {mb} MB.',
  noRecord: 'Αυτός ο browser δεν μπορεί να ηχογραφήσει. Χρησιμοποίησε Chrome (Android) ή Safari (iPhone).',
  settings: 'Ρυθμίσεις', lang: 'English', change: 'Αλλαγή', site: 'Τόπος', collector: 'Καταγραφή από',
  checkConn: 'Έλεγχος σύνδεσης με το Nextcloud', conn_ok: 'Το Nextcloud απαντά ✓', conn_denied: 'Το Nextcloud αρνείται τη σύνδεση (ο σύνδεσμος ή ο κωδικός του δεν ισχύει).',
  conn_blocked: 'Δεν υπάρχει σύνδεση με το Nextcloud (εκτός δικτύου, ή ο διακομιστής δεν επιτρέπει αυτή την εφαρμογή).',
  storage: 'Αποθήκευση: {k}', back: '← Πίσω',
  tTitle: 'Τίτλος μαρτυρίας', tTitlePh: 'π.χ. Το πανηγύρι του χωριού', next: 'Συνέχεια', needTTitle: 'Γράψε τίτλο.',
  consentTitle: 'Συναίνεση', consentLead: 'Χωρίς συναίνεση δεν γίνεται καταγραφή.',
  consentSpoken: '🎙 Ηχογράφηση προφορικής συναίνεσης', consentForm: '✍ Υπογεγραμμένο έντυπο συναίνεσης',
  formSigned: 'Το έντυπο συναίνεσης υπογράφηκε', licence: 'Άδεια', anonymous: 'Ανωνυμία', yes: 'Ναι', no: 'Όχι',
  saveConsent: 'Αποθήκευση συναίνεσης', needSigned: 'Τσέκαρε ότι το έντυπο υπογράφηκε και διάλεξε ανωνυμία.',
  consentSpokenDone: '✓ Προφορική συναίνεση ηχογραφημένη', consentFormDone: '✓ Έντυπο συναίνεσης · {l} · ανωνυμία: {a}',
  captureLocked: '🔒 Πρώτα η συναίνεση.',
  audio: 'Ήχος', video: 'Βίντεο', photo: 'Φωτογραφία',
  record: '● Έναρξη', pause: '❚❚ Παύση', resume: '● Συνέχεια', stop: '■ Τέλος', cancel: 'Ακύρωση', shutter: '◉ Λήψη', switchCam: '⟲ Κάμερα',
  recording: 'Εγγραφή', paused: 'Σε παύση',
  itemTitle: 'Σύντομος τίτλος', itemTitlePh: 'π.χ. Η πλατεία το πρωί', save: 'Αποθήκευση', discard: 'Διαγραφή',
  discardQ: 'Να διαγραφεί αυτή η λήψη;', needTitle: 'Χρειάζεται τίτλος', longVideo: 'Το βίντεο ξεπέρασε τα 3 λεπτά: σκέψου να το σταματήσεις.',
  noLocation: 'χωρίς θέση', roughLoc: 'κατά προσέγγιση: άνοιξε το GPS / την «Ακριβή τοποθεσία»', play: '▶ Άνοιγμα', rename: '✎ Τίτλος', del: '✕ Διαγραφή', delItemQ: 'Να διαγραφεί το «{t}»;',
  delTestimony: 'Διαγραφή μαρτυρίας', delTestimonyQ: 'Να διαγραφεί η μαρτυρία «{t}» με όλα τα στοιχεία της από τη συσκευή;',
  sendAll: '⬆ Αποστολή όλων', sending: 'Αποστολή {i} από {n}…', sentDone: 'Η μαρτυρία «{t}» στάλθηκε και διαγράφηκε από τη συσκευή ✓',
  sendFailed: 'Η αποστολή διακόπηκε: απομένουν {n} αρχεία. Όλα μένουν στη συσκευή· ξαναπάτησε «Αποστολή» αργότερα.',
  sendHttps: 'Η αποστολή γίνεται μόνο μέσω https://.',
  why_network: 'Αιτία: καμία απάντηση από το Nextcloud (εκτός σύνδεσης, ή ο διακομιστής δεν επιτρέπει αποστολές από αυτή την εφαρμογή – CORS).',
  why_denied: 'Αιτία: το Nextcloud αρνήθηκε ({c}): ο σύνδεσμος δεν επιτρέπει ανέβασμα, ή χρειάζεται κωδικό.',
  why_notfound: 'Αιτία: το Nextcloud δεν βρήκε τον σύνδεσμο ({c}): μπορεί να έληξε ή να διαγράφηκε.',
  why_full: 'Αιτία: το Nextcloud δεν δέχτηκε το μέγεθος ή δεν έχει χώρο ({c}).',
  why_http: 'Αιτία: σφάλμα του Nextcloud ({c}).', why_timeout: 'Αιτία: η σύνδεση άργησε πολύ.',
  pr_consent: 'λείπει η συναίνεση', pr_items: 'δεν υπάρχει καμία λήψη', pr_recording: 'μια εγγραφή δεν ολοκληρώθηκε', pr_titles: 'κάποια στοιχεία δεν έχουν τίτλο',
  cannotSend: 'Δεν μπορεί να σταλεί ακόμα: {p}.', offline: 'Εκτός σύνδεσης: η αποστολή θα γίνει όταν υπάρξει σύνδεση.',
  permDenied: 'Δεν δόθηκε άδεια για μικρόφωνο/κάμερα. Επίτρεψέ την στις ρυθμίσεις του browser.',
  map: 'Χάρτης', mapNote: 'Χωρίς σύνδεση φαίνονται μόνο τα σημεία.', items: 'Στοιχεία', none: 'Καμία λήψη ακόμα.',
  recovered: 'Ανακτήθηκε μετά από διακοπή', created: 'Δημιουργία', sentSession: 'Στάλθηκαν σε αυτή τη χρήση',
  install: 'Συμβουλή: πρόσθεσε την εφαρμογή στην αρχική οθόνη (μενού → «Προσθήκη στην αρχική οθόνη»).',
  close: 'Κλείσιμο', saved: 'Αποθηκεύτηκε',
};

const en: Dict = {
  appName: 'Walking Memory · Field',
  setupTitle: 'Welcome',
  setupLead: 'Enter your site code and your name. They stay on this device only.',
  siteCode: 'Site code', yourName: 'Your name', start: 'Start', checking: 'Checking…',
  badSite: 'Unknown site code.', needOnline: 'An internet connection is needed the first time.', needName: 'Enter your name.',
  newT: 'New testimony', noTestimonies: 'No testimonies on this device.',
  nItems: '{n} items', nItems1: '1 item',
  st_unsent: 'Not sent', st_partial: 'Partly sent', st_sent: 'Sent ✓',
  unsentBanner: 'You have {n} unsent testimonies.', sendNow: 'Send now',
  persistWarn: 'This device does not guarantee to keep the files. Add the app to your home screen and send testimonies soon.',
  httpsWarn: 'The app must be opened with https://.',
  lowSpace: 'Low free space: about {mb} MB.',
  noRecord: 'This browser cannot record. Use Chrome (Android) or Safari (iPhone).',
  settings: 'Settings', lang: 'Ελληνικά', change: 'Change', site: 'Site', collector: 'Collected by',
  checkConn: 'Check the connection to Nextcloud', conn_ok: 'Nextcloud answers ✓', conn_denied: 'Nextcloud refuses (the link or its password is not valid).',
  conn_blocked: 'No connection to Nextcloud (offline, or the server does not allow this app).',
  storage: 'Storage: {k}', back: '← Back',
  tTitle: 'Testimony title', tTitlePh: 'e.g. The village feast', next: 'Continue', needTTitle: 'Enter a title.',
  consentTitle: 'Consent', consentLead: 'Nothing can be recorded without consent.',
  consentSpoken: '🎙 Record spoken consent', consentForm: '✍ Consent form signed',
  formSigned: 'The consent form has been signed', licence: 'Licence', anonymous: 'Anonymous', yes: 'Yes', no: 'No',
  saveConsent: 'Save consent', needSigned: 'Tick that the form is signed and choose anonymity.',
  consentSpokenDone: '✓ Spoken consent recorded', consentFormDone: '✓ Consent form · {l} · anonymous: {a}',
  captureLocked: '🔒 Consent first.',
  audio: 'Audio', video: 'Video', photo: 'Photo',
  record: '● Record', pause: '❚❚ Pause', resume: '● Resume', stop: '■ Stop', cancel: 'Cancel', shutter: '◉ Take photo', switchCam: '⟲ Camera',
  recording: 'Recording', paused: 'Paused',
  itemTitle: 'Short title', itemTitlePh: 'e.g. The square in the morning', save: 'Save', discard: 'Delete',
  discardQ: 'Delete this capture?', needTitle: 'Title needed', longVideo: 'The video is over 3 minutes: consider stopping it.',
  noLocation: 'no location', roughLoc: 'approximate: turn on GPS / “Precise location”', play: '▶ Open', rename: '✎ Title', del: '✕ Delete', delItemQ: 'Delete “{t}”?',
  delTestimony: 'Delete testimony', delTestimonyQ: 'Delete the testimony “{t}” and all its items from this device?',
  sendAll: '⬆ Send all', sending: 'Sending {i} of {n}…', sentDone: 'The testimony “{t}” was sent and deleted from this device ✓',
  sendFailed: 'Sending stopped: {n} files remain. Everything stays on the device; press “Send” again later.',
  sendHttps: 'Sending works only over https://.',
  why_network: 'Reason: no answer from Nextcloud (offline, or the server does not allow uploads from this app – CORS).',
  why_denied: 'Reason: Nextcloud refused ({c}): the link does not allow uploading, or needs a password.',
  why_notfound: 'Reason: Nextcloud did not find the link ({c}): it may have expired or been deleted.',
  why_full: 'Reason: Nextcloud did not accept the size or has no space ({c}).',
  why_http: 'Reason: Nextcloud error ({c}).', why_timeout: 'Reason: the connection took too long.',
  pr_consent: 'consent is missing', pr_items: 'nothing captured yet', pr_recording: 'a recording did not finish', pr_titles: 'some items have no title',
  cannotSend: 'Cannot be sent yet: {p}.', offline: 'Offline: sending will be possible when connected.',
  permDenied: 'No permission for the microphone/camera. Allow it in the browser settings.',
  map: 'Map', mapNote: 'Offline, only the pins are shown.', items: 'Items', none: 'Nothing captured yet.',
  recovered: 'Recovered after an interruption', created: 'Created', sentSession: 'Sent during this session',
  install: 'Tip: add the app to your home screen (menu → “Add to Home Screen”).',
  close: 'Close', saved: 'Saved',
};

let lang: 'el' | 'en' = 'el';
export function setLang(l: 'el' | 'en'): void { lang = l; document.documentElement.lang = l; try { localStorage.setItem('wmf_lang', l); } catch { /* private mode */ } }
export function getLang(): 'el' | 'en' { return lang; }
export function initLang(): void {
  let l: string | null = null;
  try { l = localStorage.getItem('wmf_lang'); } catch { /* private mode */ }
  setLang(l === 'el' || l === 'en' ? l : (navigator.language || '').toLowerCase().startsWith('el') ? 'el' : 'en');
}
export function t(k: string, vars?: Record<string, string | number>): string {
  let s = (lang === 'el' ? el : en)[k] ?? en[k] ?? k;
  if (vars) for (const v of Object.keys(vars)) s = s.split('{' + v + '}').join(String(vars[v]));
  return s;
}
export const LICENCES = ['CC BY', 'CC BY-SA', 'CC BY-NC', 'CC BY-NC-SA', 'CC BY-NC-ND'];
