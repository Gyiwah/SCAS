import React, { useCallback, useEffect, useState } from 'react';
import { Screen, Field, RowCard, Loading, ErrorText } from '../components/Screen';
import { Badge, Button } from '../components/ui';
import { apiClient } from '../api/client';
import { apiError, monthStartISO, todayISO } from '../roles';
import { statusColors } from '../theme';

export function TeachersScreen() {
  const [q, setQ] = useState('');
  const [dept, setDept] = useState('');
  const [from, setFrom] = useState(monthStartISO());
  const [to, setTo] = useState(todayISO());
  const [rows, setRows] = useState<any[]>([]);
  const [stats, setStats] = useState<any>({});
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    try {
      setError('');
      const res = await apiClient.get('/teachers.php', { params: { q, dept, from, to } });
      setRows(res.data.data || []);
      setStats(res.data.stats || {});
    } catch (e) {
      setError(apiError(e));
    } finally {
      setLoading(false);
    }
  }, [q, dept, from, to]);

  useEffect(() => {
    void load();
  }, [load]);

  if (loading) return <Loading />;

  return (
    <Screen title="Staff directory" subtitle="Teaching staff visible to your account.">
      {error ? <ErrorText message={error} /> : null}
      <Field label="Search name or staff number" value={q} onChangeText={setQ} />
      <Field label="Department" value={dept} onChangeText={setDept} placeholder="leave blank for all" />
      <Field label="From" value={from} onChangeText={setFrom} />
      <Field label="To" value={to} onChangeText={setTo} />
      <Button label="Apply" variant="secondary" onPress={() => void load()} />
      {rows.map((t) => {
        const s = stats[String(t.teacher_id)] || stats[t.teacher_id] || {};
        const c = statusColors(t.is_active ? 'Present' : 'Absent');
        return (
          <RowCard
            key={t.teacher_id}
            title={t.full_name}
            lines={[
              `${t.staff_number} · ${t.department} · ${t.school_name}`,
              t.phone_masked ? `Phone ${t.phone_masked}` : '',
              `Present ${s.present_count ?? 0} · Late ${s.late_count ?? 0} · Absent ${s.absent_count ?? 0}`,
            ]}
            right={<Badge label={t.is_active ? 'Active' : 'Inactive'} fg={c.fg} bg={c.bg} />}
          />
        );
      })}
    </Screen>
  );
}
