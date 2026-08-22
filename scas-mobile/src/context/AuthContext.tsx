import React, {
  createContext,
  useState,
  useEffect,
  useContext,
  useCallback,
  ReactNode,
} from 'react';
import * as SecureStore from 'expo-secure-store';
import { apiClient, setUnauthorizedHandler } from '../api/client';
import { TOKEN_STORAGE_KEY, USER_STORAGE_KEY, saveApiBaseUrl, resolveApiBaseUrl } from '../config';

export interface UserProfile {
  user_id: number;
  full_name: string;
  username: string;
  school_id: number | null;
  school_name: string | null;
  teacher_id: number | null;
  staff_number?: string | null;
  role_id: number;
  role_name: string;
  privilege_level: number;
  department: string | null;
  must_change_password?: number;
  last_login_at?: string | null;
}

interface AuthContextType {
  user: UserProfile | null;
  token: string | null;
  isLoading: boolean;
  login: (username: string, password: string, apiBase?: string) => Promise<{ ok: boolean; message: string }>;
  logout: () => Promise<void>;
}

export const AuthContext = createContext<AuthContextType>({
  user: null,
  token: null,
  isLoading: true,
  login: async () => ({ ok: false, message: '' }),
  logout: async () => {},
});

export function useAuth(): AuthContextType {
  return useContext(AuthContext);
}

export const AuthProvider: React.FC<{ children: ReactNode }> = ({ children }) => {
  const [user, setUser] = useState<UserProfile | null>(null);
  const [token, setToken] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState<boolean>(true);

  const logout = useCallback(async () => {
    try {
      await SecureStore.deleteItemAsync(TOKEN_STORAGE_KEY);
      await SecureStore.deleteItemAsync(USER_STORAGE_KEY);
    } catch (e) {
      console.error('Error clearing secure store on logout:', e);
    }
    setToken(null);
    setUser(null);
  }, []);

  useEffect(() => {
    restoreSession();
  }, []);

  useEffect(() => {
    setUnauthorizedHandler(() => {
      void logout();
    });
    return () => setUnauthorizedHandler(null);
  }, [logout]);

  const restoreSession = async () => {
    try {
      const storedToken = await SecureStore.getItemAsync(TOKEN_STORAGE_KEY);
      const storedUser = await SecureStore.getItemAsync(USER_STORAGE_KEY);

      if (storedToken && storedUser) {
        setToken(storedToken);
        setUser(JSON.parse(storedUser));
      }
    } catch (e) {
      console.error('Failed to restore auth session:', e);
    } finally {
      setIsLoading(false);
    }
  };

  const login = async (
    username: string,
    password: string,
    apiBase?: string
  ): Promise<{ ok: boolean; message: string }> => {
    const base = apiBase
      ? await saveApiBaseUrl(apiBase)
      : await resolveApiBaseUrl();
    try {
      const response = await apiClient.post('/login.php', { username, password });

      if (response.data?.status === 'success' && response.data?.token) {
        const authToken = response.data.token;
        const userPayload: UserProfile = response.data.user;

        await SecureStore.setItemAsync(TOKEN_STORAGE_KEY, authToken);
        await SecureStore.setItemAsync(USER_STORAGE_KEY, JSON.stringify(userPayload));

        setToken(authToken);
        setUser(userPayload);
        return { ok: true, message: response.data.message || 'Signed in.' };
      }

      return { ok: false, message: response.data?.message || 'Login failed.' };
    } catch (error: any) {
      if (!error.response) {
        return {
          ok: false,
          message:
            `Cannot reach ${base}. ` +
            'Use the same Wi-Fi as this PC, keep XAMPP Apache running, ' +
            'and allow port 80 through Windows Firewall if prompted.',
        };
      }
      const msg =
        error.response?.data?.message ||
        error.message ||
        'Network error. Could not connect to SCAS server.';
      return { ok: false, message: msg };
    }
  };

  return (
    <AuthContext.Provider value={{ user, token, isLoading, login, logout }}>
      {children}
    </AuthContext.Provider>
  );
};
