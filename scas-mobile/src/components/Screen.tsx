import React from 'react';
import {
  ActivityIndicator,
  RefreshControl,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { colors, spacing, typography } from '../theme';

export function Screen({
  title,
  subtitle,
  children,
  refreshing = false,
  onRefresh,
}: {
  title: string;
  subtitle?: string;
  children: React.ReactNode;
  refreshing?: boolean;
  onRefresh?: () => void;
}) {
  return (
    <SafeAreaView style={styles.safe} edges={['top']}>
      <View style={styles.header}>
        <Text style={styles.title}>{title}</Text>
        {subtitle ? <Text style={styles.subtitle}>{subtitle}</Text> : null}
      </View>
      <ScrollView
        contentContainerStyle={styles.body}
        refreshControl={
          onRefresh ? (
            <RefreshControl
              refreshing={refreshing}
              onRefresh={onRefresh}
              tintColor={colors.primaryLight}
              colors={[colors.primary]}
            />
          ) : undefined
        }
      >
        {children}
      </ScrollView>
    </SafeAreaView>
  );
}

export function Centered({ children }: { children: React.ReactNode }) {
  return <View style={styles.center}>{children}</View>;
}

export function Loading() {
  return (
    <Centered>
      <ActivityIndicator size="large" color={colors.primary} />
    </Centered>
  );
}

export function ErrorText({ message }: { message: string }) {
  return <Text style={styles.error}>{message}</Text>;
}

export function Tile({
  label,
  value,
  foot,
  tone,
}: {
  label: string;
  value: string | number;
  foot?: string;
  tone?: 'ok' | 'warn' | 'bad' | 'info' | 'plain';
}) {
  const color =
    tone === 'ok' ? colors.present : tone === 'warn' ? colors.late : tone === 'bad' ? colors.absent : tone === 'info' ? colors.primaryLight : colors.text;
  return (
    <View style={styles.tile}>
      <Text style={styles.tileLabel}>{label}</Text>
      <Text style={[styles.tileValue, { color }]}>{value}</Text>
      {foot ? <Text style={styles.tileFoot}>{foot}</Text> : null}
    </View>
  );
}

export function Field({
  label,
  value,
  onChangeText,
  placeholder,
  secure,
  multiline,
  keyboardType,
}: {
  label: string;
  value: string;
  onChangeText: (t: string) => void;
  placeholder?: string;
  secure?: boolean;
  multiline?: boolean;
  keyboardType?: 'default' | 'numeric' | 'email-address';
}) {
  return (
    <View style={styles.field}>
      <Text style={styles.fieldLabel}>{label}</Text>
      <TextInput
        style={[styles.input, multiline && styles.textarea]}
        value={value}
        onChangeText={onChangeText}
        placeholder={placeholder}
        placeholderTextColor={colors.textFaint}
        secureTextEntry={secure}
        multiline={multiline}
        keyboardType={keyboardType}
        autoCapitalize="none"
      />
    </View>
  );
}

export function RowCard({
  title,
  lines,
  right,
}: {
  title: string;
  lines?: string[];
  right?: React.ReactNode;
}) {
  return (
    <View style={styles.card}>
      <View style={styles.cardTop}>
        <Text style={styles.cardTitle}>{title}</Text>
        {right}
      </View>
                  {(lines || []).filter(Boolean).map((line, i) => (
        <Text key={`${i}-${line}`} style={styles.cardLine}>
          {line}
        </Text>
      ))}
    </View>
  );
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: colors.background },
  header: { paddingHorizontal: 20, paddingTop: 16, paddingBottom: 12 },
  title: { ...typography.h1, color: colors.text },
  subtitle: { fontSize: 14, color: colors.textMuted, marginTop: 2 },
  body: { padding: 20, paddingTop: 8, paddingBottom: 40 },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center', padding: 24, backgroundColor: colors.background },
  error: { color: colors.absent, textAlign: 'center', marginVertical: 12 },
  tile: {
    backgroundColor: colors.surface,
    borderColor: colors.border,
    borderWidth: 1,
    borderRadius: 16,
    padding: 14,
    width: '48%',
    marginBottom: 12,
  },
  tileLabel: { fontSize: 11, color: colors.textMuted, textTransform: 'uppercase', letterSpacing: 0.6, marginBottom: 4 },
  tileValue: { fontSize: 22, fontWeight: '800' },
  tileFoot: { fontSize: 12, color: colors.textMuted, marginTop: 4 },
  card: {
    backgroundColor: colors.surface,
    borderColor: colors.border,
    borderWidth: 1,
    borderRadius: 16,
    padding: 16,
    marginBottom: 12,
  },
  cardTop: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'flex-start', gap: 8 },
  cardTitle: { color: colors.text, fontSize: 16, fontWeight: '700', flex: 1 },
  cardLine: { color: colors.textMuted, fontSize: 13, marginTop: 4 },
  field: { marginBottom: 12 },
  fieldLabel: { color: colors.textMuted, fontSize: 13, fontWeight: '600', marginBottom: 6 },
  input: {
    backgroundColor: colors.background,
    borderColor: colors.border,
    borderWidth: 1,
    borderRadius: 12,
    color: colors.text,
    paddingHorizontal: 14,
    paddingVertical: 12,
    fontSize: 15,
  },
  textarea: { minHeight: 80, textAlignVertical: 'top' },
});
