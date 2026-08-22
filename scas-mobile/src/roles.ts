export const PRIV = {
  TEACHER: 10,
  HEADTEACHER: 50,
  SCHOOL_ADMIN: 90,
  SYS_ADMIN: 99,
} as const;

export type MenuItem = {
  key: string;
  label: string;
  group: string;
  route: string;
  minPriv: number;
  teacherOnly?: boolean;
};

/** Same groups as the web navigation, gated the same way. */
export const MENU: MenuItem[] = [
  { key: 'dashboard', label: 'Dashboard', group: 'Attendance', route: 'Dashboard', minPriv: 0 },
  { key: 'checkin', label: 'Check in', group: 'Attendance', route: 'Checkin', minPriv: 0, teacherOnly: true },
  { key: 'my_attendance', label: 'My attendance', group: 'Attendance', route: 'Attendance', minPriv: 0, teacherOnly: true },
  { key: 'my_timetable', label: 'My timetable', group: 'Attendance', route: 'MyTimetable', minPriv: 0, teacherOnly: true },
  { key: 'board', label: 'Live board', group: 'Attendance', route: 'Board', minPriv: PRIV.HEADTEACHER },
  { key: 'qrcodes', label: 'Session codes', group: 'Attendance', route: 'QrCodes', minPriv: PRIV.HEADTEACHER },
  { key: 'leave', label: 'My leave', group: 'People', route: 'Leave', minPriv: 0, teacherOnly: true },
  { key: 'approvals', label: 'Leave approvals', group: 'People', route: 'Approvals', minPriv: PRIV.HEADTEACHER },
  { key: 'teachers', label: 'Staff directory', group: 'People', route: 'Teachers', minPriv: PRIV.HEADTEACHER },
  { key: 'admin_timetable', label: 'Timetable', group: 'People', route: 'AdminTimetable', minPriv: PRIV.SCHOOL_ADMIN },
  { key: 'users', label: 'User accounts', group: 'People', route: 'Users', minPriv: PRIV.SCHOOL_ADMIN },
  { key: 'reports', label: 'Reports', group: 'Insight', route: 'Reports', minPriv: PRIV.HEADTEACHER },
  { key: 'audit', label: 'Audit trail', group: 'Insight', route: 'Audit', minPriv: PRIV.SCHOOL_ADMIN },
  { key: 'security', label: 'Security', group: 'Insight', route: 'Security', minPriv: PRIV.SCHOOL_ADMIN },
  { key: 'dba', label: 'DBA console', group: 'Insight', route: 'Dba', minPriv: PRIV.SYS_ADMIN },
  { key: 'notifications', label: 'Notifications', group: 'Account', route: 'Notifications', minPriv: 0 },
  { key: 'profile', label: 'My account', group: 'Account', route: 'Account', minPriv: 0 },
];

export function visibleMenu(
  privilege: number,
  isTeacher: boolean
): MenuItem[] {
  return MENU.filter((item) => {
    if (item.teacherOnly && !isTeacher) return false;
    return privilege >= item.minPriv;
  });
}

export function fmtTime(value?: string | null): string {
  if (!value) return '-';
  const part = value.length > 8 ? value.slice(11, 16) : value.slice(0, 5);
  const [hStr, mStr] = part.split(':');
  const h = Number(hStr);
  const m = mStr ?? '00';
  if (Number.isNaN(h)) return value;
  const suffix = h >= 12 ? 'pm' : 'am';
  const hour = ((h + 11) % 12) + 1;
  return `${hour}:${m} ${suffix}`;
}

export function fmtDate(value?: string | null): string {
  if (!value) return '-';
  const d = new Date(value.replace(' ', 'T'));
  if (Number.isNaN(d.getTime())) return value;
  return d.toLocaleDateString('en-GB', { weekday: 'short', day: 'numeric', month: 'short', year: 'numeric' });
}

export function todayISO(): string {
  return new Date().toISOString().slice(0, 10);
}

export function monthStartISO(): string {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-01`;
}

export function apiError(error: any, fallback = 'Could not reach the SCAS server.'): string {
  return error?.response?.data?.message || error?.message || fallback;
}
