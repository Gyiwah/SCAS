import React, { useEffect, useState } from 'react';
import {
  StyleSheet,
  Text,
  View,
  TextInput,
  TouchableOpacity,
  ActivityIndicator,
  KeyboardAvoidingView,
  Platform,
  ScrollView,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useAuth } from '../context/AuthContext';
import { Ionicons } from '@expo/vector-icons';
import { defaultApiBaseUrl, resolveApiBaseUrl } from '../config';

export const LoginScreen = () => {
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [serverUrl, setServerUrl] = useState(defaultApiBaseUrl());
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errorMsg, setErrorMsg] = useState('');

  const { login } = useAuth();

  useEffect(() => {
    void resolveApiBaseUrl().then(setServerUrl);
  }, []);

  const handleLogin = async () => {
    if (!username.trim() || !password.trim()) {
      setErrorMsg('Please enter both username and password.');
      return;
    }

    setErrorMsg('');
    setIsSubmitting(true);

    const res = await login(username, password, serverUrl);
    setIsSubmitting(false);

    if (!res.ok) {
      setErrorMsg(res.message);
    }
  };

  const fillDemoAccount = (demoUser: string, demoPass: string) => {
    setUsername(demoUser);
    setPassword(demoPass);
    setErrorMsg('');
  };

  return (
    <SafeAreaView style={styles.container}>
      <KeyboardAvoidingView
        behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
        style={{ flex: 1 }}
      >
        <ScrollView contentContainerStyle={styles.scrollContent} keyboardShouldPersistTaps="handled">
          
          {/* Header */}
          <View style={styles.header}>
            <View style={styles.logoBadge}>
              <Ionicons name="qr-code-outline" size={44} color="#FFFFFF" />
            </View>
            <Text style={styles.title}>SCAS Mobile</Text>
            <Text style={styles.subtitle}>Smart Classroom Attendance System</Text>
          </View>

          {/* Form Card */}
          <View style={styles.card}>
            <Text style={styles.cardTitle}>Sign in</Text>

            {errorMsg ? (
              <View style={styles.errorBox}>
                <Ionicons name="alert-circle" size={20} color="#C53030" />
                <Text style={styles.errorText}>{errorMsg}</Text>
              </View>
            ) : null}

            {/* Server URL */}
            <View style={styles.fieldGroup}>
              <Text style={styles.label}>SCAS server</Text>
              <View style={styles.inputWrapper}>
                <Ionicons name="globe-outline" size={20} color="#718096" style={styles.inputIcon} />
                <TextInput
                  style={styles.input}
                  placeholder="http://10.64.146.183/scas/api"
                  placeholderTextColor="#A0AEC0"
                  value={serverUrl}
                  onChangeText={setServerUrl}
                  autoCapitalize="none"
                  autoCorrect={false}
                />
              </View>
            </View>

            {/* Username Input */}
            <View style={styles.fieldGroup}>
              <Text style={styles.label}>Username</Text>
              <View style={styles.inputWrapper}>
                <Ionicons name="person-outline" size={20} color="#718096" style={styles.inputIcon} />
                <TextInput
                  style={styles.input}
                  placeholder="e.g. k.mensah"
                  placeholderTextColor="#A0AEC0"
                  value={username}
                  onChangeText={setUsername}
                  autoCapitalize="none"
                  autoCorrect={false}
                />
              </View>
            </View>

            {/* Password Input */}
            <View style={styles.fieldGroup}>
              <Text style={styles.label}>Password</Text>
              <View style={styles.inputWrapper}>
                <Ionicons name="lock-closed-outline" size={20} color="#718096" style={styles.inputIcon} />
                <TextInput
                  style={styles.input}
                  placeholder="••••••••"
                  placeholderTextColor="#A0AEC0"
                  value={password}
                  onChangeText={setPassword}
                  secureTextEntry
                />
              </View>
            </View>

            {/* Submit Button */}
            <TouchableOpacity
              style={[styles.button, isSubmitting && styles.buttonDisabled]}
              onPress={handleLogin}
              disabled={isSubmitting}
            >
              {isSubmitting ? (
                <ActivityIndicator color="#FFFFFF" />
              ) : (
                <Text style={styles.buttonText}>Sign In</Text>
              )}
            </TouchableOpacity>

            {/* Demo Account Quick Fill */}
            <View style={styles.demoSection}>
              <Text style={styles.demoTitle}>Demonstration accounts</Text>
              {[
                ['Teacher', 'k.mensah', 'Teach@2026'],
                ['Headteacher', 'head.winneba', 'Head@2026'],
                ['School administrator', 'admin.winneba', 'School@2026'],
                ['System administrator', 'sysadmin', 'Sys@dmin2026'],
              ].map(([label, u, p]) => (
                <TouchableOpacity
                  key={u}
                  style={styles.demoChip}
                  onPress={() => fillDemoAccount(u, p)}
                >
                  <Ionicons name="person" size={14} color="#60A5FA" />
                  <Text style={styles.demoChipText}>{label} ({u})</Text>
                </TouchableOpacity>
              ))}
            </View>

          </View>
        </ScrollView>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#0F172A',
  },
  scrollContent: {
    flexGrow: 1,
    justifyContent: 'center',
    padding: 24,
  },
  header: {
    alignItems: 'center',
    marginBottom: 32,
  },
  logoBadge: {
    width: 80,
    height: 80,
    borderRadius: 20,
    backgroundColor: '#2563EB',
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: 16,
    shadowColor: '#2563EB',
    shadowOffset: { width: 0, height: 8 },
    shadowOpacity: 0.4,
    shadowRadius: 16,
    elevation: 8,
  },
  title: {
    fontSize: 28,
    fontWeight: '800',
    color: '#FFFFFF',
    letterSpacing: 0.5,
  },
  subtitle: {
    fontSize: 14,
    color: '#94A3B8',
    marginTop: 4,
  },
  card: {
    backgroundColor: '#1E293B',
    borderRadius: 20,
    padding: 24,
    borderWidth: 1,
    borderColor: '#334155',
  },
  cardTitle: {
    fontSize: 20,
    fontWeight: '700',
    color: '#F8FAFC',
    marginBottom: 20,
  },
  errorBox: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#451A1A',
    borderWidth: 1,
    borderColor: '#991B1B',
    borderRadius: 10,
    padding: 12,
    marginBottom: 16,
  },
  errorText: {
    color: '#FCA5A5',
    fontSize: 14,
    marginLeft: 8,
    flex: 1,
  },
  fieldGroup: {
    marginBottom: 18,
  },
  label: {
    fontSize: 14,
    fontWeight: '600',
    color: '#CBD5E1',
    marginBottom: 8,
  },
  inputWrapper: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#0F172A',
    borderRadius: 12,
    borderWidth: 1,
    borderColor: '#334155',
    paddingHorizontal: 14,
  },
  inputIcon: {
    marginRight: 10,
  },
  input: {
    flex: 1,
    height: 48,
    color: '#FFFFFF',
    fontSize: 16,
  },
  button: {
    backgroundColor: '#2563EB',
    borderRadius: 12,
    height: 52,
    justifyContent: 'center',
    alignItems: 'center',
    marginTop: 10,
  },
  buttonDisabled: {
    opacity: 0.7,
  },
  buttonText: {
    color: '#FFFFFF',
    fontSize: 16,
    fontWeight: '700',
  },
  demoSection: {
    marginTop: 24,
    paddingTop: 16,
    borderTopWidth: 1,
    borderTopColor: '#334155',
  },
  demoTitle: {
    fontSize: 13,
    color: '#94A3B8',
    marginBottom: 10,
  },
  demoChip: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#1E3A8A',
    paddingVertical: 10,
    paddingHorizontal: 14,
    borderRadius: 8,
    alignSelf: 'flex-start',
    marginBottom: 8,
  },
  demoChipText: {
    color: '#60A5FA',
    fontWeight: '600',
    fontSize: 14,
    marginLeft: 6,
  },
});
