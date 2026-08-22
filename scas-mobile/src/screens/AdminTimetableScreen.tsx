import React, { useCallback, useEffect, useState } from 'react';
import { Text } from 'react-native';
import { Screen, Field, RowCard, Loading, ErrorText } from '../components/Screen';
import { Badge, Button } from '../components/ui';
import { apiClient } from '../api/client';
import { apiError, fmtTime } from '../roles';
import { colors, statusColors } from '../theme';

const DAYS = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'];

export function AdminTimetableScreen() {
  const [rows, setRows] = useState<any[]>([]);
  const [teachers, setTeachers] = useState<any[]>([]);
  const [classrooms, setClassrooms] = useState<any[]>([]);
  const [terms, setTerms] = useState<any[]>([]);
  const [conflicts, setConflicts] = useState<any[]>([]);
  const [form, setForm] = useState({
    teacher_id: '',
    classroom_id: '',
    term_id: '',
    subject: '',
    class_group: '',
    day_of_week: 'Monday',
    start_time: '07:30',
    end_time: '08:40',
  });
  const [msg, setMsg] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    try {
      setError('');
      const res = await apiClient.get('/admin_timetable.php');
      setRows(res.data.data || []);
      setTeachers(res.data.teachers || []);
      setClassrooms(res.data.classrooms || []);
      setTerms(res.data.terms || []);
      setConflicts(res.data.conflicts || []);
      setForm((f) => (f.term_id || !res.data.terms?.[0] ? f : { ...f, term_id: String(res.data.terms[0].term_id) }));
    } catch (e) {
      setError(apiError(e));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  const create = async () => {
    try {
      const res = await apiClient.post('/admin_timetable.php', { action: 'create', ...form });
      setMsg(res.data.message);
      await load();
    } catch (e) {
      setError(apiError(e));
    }
  };

  const toggle = async (id: number, active: number) => {
    try {
      await apiClient.post('/admin_timetable.php', { action: 'toggle', timetable_id: id, active });
      await load();
    } catch (e) {
      setError(apiError(e));
    }
  };

  if (loading) return <Loading />;

  return (
    <Screen title="Timetable" subtitle="Sessions in the current term. A session is retired rather than deleted.">
      {error ? <ErrorText message={error} /> : null}
      {msg ? <Text style={{ color: colors.present, marginBottom: 12 }}>{msg}</Text> : null}
      {conflicts.length ? <ErrorText message={`${conflicts.length} scheduling conflict(s) detected.`} /> : null}
      <Field label="Teacher id" value={form.teacher_id} onChangeText={(t) => setForm({ ...form, teacher_id: t })} keyboardType="numeric" placeholder={teachers[0] ? String(teachers[0].teacher_id) : ''} />
      <Field label="Classroom id" value={form.classroom_id} onChangeText={(t) => setForm({ ...form, classroom_id: t })} keyboardType="numeric" />
      <Field label="Term id" value={form.term_id} onChangeText={(t) => setForm({ ...form, term_id: t })} keyboardType="numeric" />
      <Field label="Subject" value={form.subject} onChangeText={(t) => setForm({ ...form, subject: t })} />
      <Field label="Class group" value={form.class_group} onChangeText={(t) => setForm({ ...form, class_group: t })} />
      <Field label={`Day (${DAYS.join(', ')})`} value={form.day_of_week} onChangeText={(t) => setForm({ ...form, day_of_week: t })} />
      <Field label="Start time" value={form.start_time} onChangeText={(t) => setForm({ ...form, start_time: t })} />
      <Field label="End time" value={form.end_time} onChangeText={(t) => setForm({ ...form, end_time: t })} />
      <Button label="Add session" onPress={create} />
      {rows.map((r) => {
        const c = statusColors(r.is_active ? 'Present' : '');
        return (
          <RowCard
            key={r.timetable_id}
            title={`${r.day_of_week} · ${r.subject}`}
            lines={[
              `${fmtTime(r.start_time)} – ${fmtTime(r.end_time)} · ${r.class_group} · ${r.room_name}`,
              `${r.teacher_name} · ${r.term_name}`,
            ]}
            right={<Badge label={r.is_active ? 'Active' : 'Retired'} fg={c.fg} bg={c.bg} />}
          />
        );
      })}
      {rows.map((r) => (
        <Button
          key={`t-${r.timetable_id}`}
          label={r.is_active ? `Retire ${r.subject} (${r.day_of_week})` : `Reactivate ${r.subject}`}
          variant="secondary"
          onPress={() => toggle(r.timetable_id, r.is_active ? 0 : 1)}
        />
      ))}
    </Screen>
  );
}
