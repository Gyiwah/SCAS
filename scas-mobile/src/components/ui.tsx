/**
 * SCAS Mobile - small shared presentational pieces.
 * Kept in one file because each is a few lines; splitting them across four
 * files would add imports without adding clarity.
 */
import React from 'react';
import {
  ActivityIndicator,
  Pressable,
  StyleSheet,
  Text,
  View,
  ViewStyle,
} from 'react-native';
import { colors, radius, spacing, typography } from '../theme';

/* --------------------------------- Card -------------------------------- */

export function Card({
  children,
  style,
}: {
  children: React.ReactNode;
  style?: ViewStyle;
}) {
  return <View style={[styles.card, style]}>{children}</View>;
}

/* -------------------------------- Badge -------------------------------- */

export function Badge({
  label,
  fg,
  bg,
  dot = false,
}: {
  label: string;
  fg: string;
  bg: string;
  dot?: boolean;
}) {
  return (
    <View style={[styles.badge, { backgroundColor: bg }]}>
      {dot && <View style={[styles.dot, { backgroundColor: fg }]} />}
      <Text style={[styles.badgeText, { color: fg }]}>{label}</Text>
    </View>
  );
}

/* -------------------------------- Button ------------------------------- */

export function Button({
  label,
  onPress,
  loading = false,
  disabled = false,
  variant = 'primary',
  style,
}: {
  label: string;
  onPress: () => void;
  loading?: boolean;
  disabled?: boolean;
  variant?: 'primary' | 'secondary' | 'ghost';
  style?: ViewStyle;
}) {
  const isDisabled = disabled || loading;

  const palette =
    variant === 'primary'
      ? { bg: colors.primary, fg: colors.white, border: colors.primary }
      : variant === 'secondary'
      ? { bg: colors.white, fg: colors.primary, border: colors.primary }
      : { bg: 'transparent', fg: colors.textMuted, border: 'transparent' };

  return (
    <Pressable
      onPress={onPress}
      disabled={isDisabled}
      accessibilityRole="button"
      accessibilityLabel={label}
      accessibilityState={{ disabled: isDisabled, busy: loading }}
      style={({ pressed }) => [
        styles.button,
        {
          backgroundColor: palette.bg,
          borderColor: palette.border,
          opacity: isDisabled ? 0.55 : pressed ? 0.85 : 1,
        },
        style,
      ]}
    >
      {loading ? (
        <ActivityIndicator color={palette.fg} />
      ) : (
        <Text style={[styles.buttonText, { color: palette.fg }]}>{label}</Text>
      )}
    </Pressable>
  );
}

/* ------------------------------ Empty state ----------------------------- */

export function EmptyState({
  title,
  message,
}: {
  title: string;
  message: string;
}) {
  return (
    <View style={styles.empty}>
      <Text style={styles.emptyTitle}>{title}</Text>
      <Text style={styles.emptyMessage}>{message}</Text>
    </View>
  );
}

/* ------------------------------ Error banner ---------------------------- */

export function ErrorBanner({ message }: { message: string }) {
  return (
    <View style={styles.errorBanner} accessibilityRole="alert">
      <Text style={styles.errorText}>{message}</Text>
    </View>
  );
}

/* -------------------------------- Loading ------------------------------- */

export function LoadingBlock({ label = 'Loading…' }: { label?: string }) {
  return (
    <View style={styles.loading}>
      <ActivityIndicator color={colors.primary} size="large" />
      <Text style={styles.loadingText}>{label}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  card: {
    backgroundColor: colors.surface,
    borderRadius: radius.lg,
    borderWidth: 1,
    borderColor: colors.border,
    padding: spacing.lg,
  },
  badge: {
    flexDirection: 'row',
    alignItems: 'center',
    alignSelf: 'flex-start',
    paddingHorizontal: spacing.md,
    paddingVertical: 5,
    borderRadius: radius.pill,
  },
  badgeText: {
    ...typography.tiny,
    letterSpacing: 0.4,
    textTransform: 'none',
  },
  dot: {
    width: 7,
    height: 7,
    borderRadius: 4,
    marginRight: 6,
  },
  button: {
    minHeight: 50,
    borderRadius: radius.md,
    borderWidth: 1,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: spacing.lg,
  },
  buttonText: {
    fontSize: 16,
    fontWeight: '600',
  },
  empty: {
    padding: spacing.xl,
    alignItems: 'center',
  },
  emptyTitle: {
    ...typography.h3,
    color: colors.text,
    marginBottom: spacing.xs,
    textAlign: 'center',
  },
  emptyMessage: {
    ...typography.small,
    color: colors.textMuted,
    textAlign: 'center',
    lineHeight: 19,
  },
  errorBanner: {
    backgroundColor: colors.dangerBg,
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: '#F0C4BF',
    padding: spacing.md,
  },
  errorText: {
    ...typography.small,
    color: colors.danger,
    lineHeight: 19,
  },
  loading: {
    padding: spacing.xxl,
    alignItems: 'center',
  },
  loadingText: {
    ...typography.small,
    color: colors.textMuted,
    marginTop: spacing.md,
  },
});
