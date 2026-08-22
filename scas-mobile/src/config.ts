/**
 * SCAS Mobile - runtime configuration.
 *
 * The API cannot use "localhost": Expo Go on a phone would talk to the phone
 * itself. We prefer a saved server URL, then the same LAN address Metro is
 * using, then the last known address of this development PC.
 */
import Constants from 'expo-constants';
import * as SecureStore from 'expo-secure-store';

const FALLBACK_HOST = '10.64.146.183';

export const API_URL_STORAGE_KEY = 'scas.api.base';
export const TOKEN_STORAGE_KEY = 'scas.auth.token';
export const USER_STORAGE_KEY = 'scas.auth.user';
export const API_TIMEOUT_MS = 20000;

function lanHost(): string {
  const hints = [
    Constants.expoConfig?.hostUri,
    Constants.linkingUri,
    (Constants as { expoGoConfig?: { debuggerHost?: string } }).expoGoConfig?.debuggerHost,
  ];
  for (const hint of hints) {
    const match = String(hint ?? '').match(/(\d{1,3}(?:\.\d{1,3}){3})/);
    if (match && match[1] !== '127.0.0.1') {
      return match[1];
    }
  }
  return FALLBACK_HOST;
}

export function defaultApiBaseUrl(): string {
  return `http://${lanHost()}/scas/api`;
}

/** Snapshot used before SecureStore has been read. */
export let API_BASE_URL = defaultApiBaseUrl();

export async function resolveApiBaseUrl(): Promise<string> {
  try {
    const saved = await SecureStore.getItemAsync(API_URL_STORAGE_KEY);
    if (saved && /^https?:\/\//i.test(saved)) {
      API_BASE_URL = saved.replace(/\/+$/, '');
      return API_BASE_URL;
    }
  } catch {
    // keep default
  }
  API_BASE_URL = defaultApiBaseUrl();
  return API_BASE_URL;
}

export async function saveApiBaseUrl(url: string): Promise<string> {
  const cleaned = url.trim().replace(/\/+$/, '');
  API_BASE_URL = cleaned;
  await SecureStore.setItemAsync(API_URL_STORAGE_KEY, cleaned);
  return cleaned;
}
