import './styles.css';
import { initLang } from './i18n';
import { initFiles } from './files';
import { boot } from './ui';

initLang();
if ('serviceWorker' in navigator && import.meta.env.PROD) {
  window.addEventListener('load', () => { navigator.serviceWorker.register('./sw.js').catch(() => undefined); });
}
initFiles().then(boot, boot);
