/**
 * SCAS Mobile - colours already used by the existing screens.
 * Do not switch to the web light theme; keep this dark palette.
 */
export const colors = {
  primary: '#2563EB',
  primaryDark: '#1D4ED8',
  primaryLight: '#60A5FA',

  accent: '#60A5FA',
  accentLight: 'rgba(37, 99, 235, 0.2)',

  present: '#4ADE80',
  presentBg: 'rgba(34, 197, 94, 0.15)',
  late: '#FBBF24',
  lateBg: 'rgba(245, 158, 11, 0.15)',
  absent: '#FCA5A5',
  absentBg: 'rgba(239, 68, 68, 0.15)',
  excused: '#60A5FA',
  excusedBg: 'rgba(59, 130, 246, 0.15)',

  inProgress: '#4ADE80',
  upcoming: '#60A5FA',
  ended: '#94A3B8',

  text: '#F8FAFC',
  textMuted: '#94A3B8',
  textFaint: '#64748B',
  border: '#334155',
  surface: '#1E293B',
  background: '#0F172A',
  overlay: 'rgba(0,0,0,0.75)',

  danger: '#EF4444',
  dangerBg: 'rgba(239, 68, 68, 0.15)',
  white: '#FFFFFF',
  ok: '#16A34A',
  warn: '#FBBF24',
};

export const spacing = {
  xs: 4,
  sm: 8,
  md: 12,
  lg: 16,
  xl: 24,
  xxl: 32,
};

export const radius = {
  sm: 6,
  md: 10,
  lg: 14,
  pill: 999,
};

export const typography = {
  h1: { fontSize: 24, fontWeight: '800' as const },
  h2: { fontSize: 18, fontWeight: '700' as const },
  h3: { fontSize: 16, fontWeight: '600' as const },
  body: { fontSize: 15, fontWeight: '400' as const },
  small: { fontSize: 13, fontWeight: '400' as const },
  tiny: { fontSize: 11, fontWeight: '600' as const },
};

export function statusColors(status?: string | null): { fg: string; bg: string } {
  switch ((status || '').toLowerCase()) {
    case 'present':
      return { fg: colors.present, bg: colors.presentBg };
    case 'late':
      return { fg: colors.late, bg: colors.lateBg };
    case 'absent':
    case 'no scan':
      return { fg: colors.absent, bg: colors.absentBg };
    case 'excused':
    case 'on leave':
      return { fg: colors.excused, bg: colors.excusedBg };
    default:
      return { fg: colors.textMuted, bg: colors.border };
  }
}

export function sessionStateColors(state?: string | null): { fg: string; bg: string } {
  switch ((state || '').toLowerCase()) {
    case 'in progress':
      return { fg: colors.inProgress, bg: colors.presentBg };
    case 'upcoming':
      return { fg: colors.upcoming, bg: colors.accentLight };
    default:
      return { fg: colors.ended, bg: 'rgba(71, 85, 105, 0.3)' };
  }
}
