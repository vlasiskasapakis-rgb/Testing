// Metadata on the device (IndexedDB): settings, testimonies, items. Media files live in files.ts.
import type { Item, Testimony } from './types';

const DB_NAME = 'wm-field';
let dbp: Promise<IDBDatabase> | null = null;

export function db(): Promise<IDBDatabase> {
  if (!dbp) dbp = new Promise((resolve, reject) => {
    const r = indexedDB.open(DB_NAME, 1);
    r.onupgradeneeded = () => {
      const d = r.result;
      d.createObjectStore('settings', { keyPath: 'k' });
      d.createObjectStore('testimonies', { keyPath: 'id' });
      d.createObjectStore('items', { keyPath: 'id' }).createIndex('tid', 'tid');
      d.createObjectStore('chunks', { keyPath: 'k' });      // media, only when the browser has no OPFS
    };
    r.onsuccess = () => resolve(r.result);
    r.onerror = () => reject(r.error);
  });
  return dbp;
}

export function req<T>(r: IDBRequest<T>): Promise<T> {
  return new Promise((resolve, reject) => { r.onsuccess = () => resolve(r.result); r.onerror = () => reject(r.error); });
}
export async function tx(stores: string[], mode: IDBTransactionMode, fn: (t: IDBTransaction) => void): Promise<void> {
  const d = await db();
  return new Promise((resolve, reject) => {
    const t = d.transaction(stores, mode);
    t.oncomplete = () => resolve(); t.onerror = () => reject(t.error); t.onabort = () => reject(t.error);
    fn(t);
  });
}

export async function getSetting<T>(k: string): Promise<T | undefined> {
  const d = await db();
  const r = await req(d.transaction('settings').objectStore('settings').get(k));
  return r ? (r.v as T) : undefined;
}
export function setSetting(k: string, v: unknown): Promise<void> {
  return tx(['settings'], 'readwrite', (t) => { t.objectStore('settings').put({ k, v }); });
}

export async function listTestimonies(): Promise<Testimony[]> {
  const d = await db();
  const all = await req(d.transaction('testimonies').objectStore('testimonies').getAll()) as Testimony[];
  return all.sort((a, b) => b.created.localeCompare(a.created));
}
export async function getTestimony(id: string): Promise<Testimony | undefined> {
  const d = await db();
  return req(d.transaction('testimonies').objectStore('testimonies').get(id)) as Promise<Testimony | undefined>;
}
export function putTestimony(t: Testimony): Promise<void> {
  return tx(['testimonies'], 'readwrite', (x) => { x.objectStore('testimonies').put(t); });
}
export function deleteTestimonyMeta(id: string): Promise<void> {
  return tx(['testimonies', 'items'], 'readwrite', (x) => {
    x.objectStore('testimonies').delete(id);
    const idx = x.objectStore('items').index('tid');
    idx.openCursor(IDBKeyRange.only(id)).onsuccess = (e) => {
      const c = (e.target as IDBRequest<IDBCursorWithValue | null>).result;
      if (c) { c.delete(); c.continue(); }
    };
  });
}

export async function listItems(tid: string): Promise<Item[]> {
  const d = await db();
  const all = await req(d.transaction('items').objectStore('items').index('tid').getAll(IDBKeyRange.only(tid))) as Item[];
  return all.sort((a, b) => a.order - b.order);
}
export function putItem(i: Item): Promise<void> {
  return tx(['items'], 'readwrite', (x) => { x.objectStore('items').put(i); });
}
export function deleteItem(id: string): Promise<void> {
  return tx(['items'], 'readwrite', (x) => { x.objectStore('items').delete(id); });
}
