import axios from 'axios';
import * as SecureStore from 'expo-secure-store';
import {
  API_BASE_URL,
  API_TIMEOUT_MS,
  TOKEN_STORAGE_KEY,
  resolveApiBaseUrl,
} from '../config';

export const apiClient = axios.create({
  baseURL: API_BASE_URL,
  headers: {
    'Content-Type': 'application/json',
    Accept: 'application/json',
  },
  timeout: API_TIMEOUT_MS,
});

/** Called by AuthProvider when any API request returns HTTP 401. */
let onUnauthorized: (() => void) | null = null;

export function setUnauthorizedHandler(handler: (() => void) | null): void {
  onUnauthorized = handler;
}

apiClient.interceptors.request.use(
  async (config) => {
    config.baseURL = await resolveApiBaseUrl();
    try {
      const token = await SecureStore.getItemAsync(TOKEN_STORAGE_KEY);
      if (token) {
        config.headers.Authorization = `Bearer ${token}`;
      }
    } catch (err) {
      console.error('Error fetching token from SecureStore', err);
    }
    return config;
  },
  (error) => Promise.reject(error)
);

apiClient.interceptors.response.use(
  (response) => response,
  (error) => {
    const url = error.config?.url ?? '';
    if (error.response?.status === 401 && onUnauthorized && !url.includes('login.php')) {
      onUnauthorized();
    }
    return Promise.reject(error);
  }
);
