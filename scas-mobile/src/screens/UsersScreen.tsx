import React, { useCallback, useEffect, useState } from 'react';
import { Text } from 'react-native';
import { Screen, Field, RowCard, Loading, ErrorText } from '../components/Screen';
import { Badge, Button } from '../components/ui';
import { apiClient } from '../api/client';
import { apiError, fmtDate, todayISO } from '../roles';
import { colors, statusColors } from '../theme';

export function UsersScreen() {
  const [rows, setRows] = useState<any[]>([]);
  const [roles, setRoles] = useState<any[]>([]);
  const [form, setForm] = useState({
    full_name: '',
    username: '',
    password: '',
    role_id: '1',
    staff_number: '',
    department: '',
    date_employed: todayISO(),
  });
  const [msg, setMsg] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    try {
      setError('');
      const res = await apiClient.get('/users.php');
      setRows(res.data.data || []);
      setRoles(res.data.roles || []);
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
      const res = await apiClient.post('/users.php', { action: 'create', ...form, role_id: Number(form.role_id) });
      setMsg(res.data.message);
      await load();
    } catch (e) {
      setError(apiError(e));
    }
  };

  const act = async (body: object) => {
    try {
      const res = await apiClient.post('/users.php', body);
      setMsg(res.data.message);
      await load();
    } catch (e) {
      setError(apiError(e));
    }
  };

  if (loading) return <Loading />;

  return (
    <Screen title="User accounts" subtitle="Accounts are deactivated, never deleted.">
      {error ? <ErrorText message={error} /> : null}
      {msg ? <Text style={{ color: colors.present, marginBottom: 12 }}>{msg}</Text> : null}
      <Field label="Full name" value={form.full_name} onChangeText={(t) => setForm({ ...form, full_name: t })} />
      <Field label="Username" value={form.username} onChangeText={(t) => setForm({ ...form, username: t })} />
      <Field label="Temporary password" value={form.password} onChangeText={(t) => setForm({ ...form, password: t })} secure />
      <Field
        label={`Role id (${roles.map((r) => `${r.role_id}=${r.role_name}`).join(', ')})`}
        value={form.role_id}
        onChangeText={(t) => setForm({ ...form, role_id: t })}
        keyboardType="numeric"
      />
      <Field label="Staff number (teachers)" value={form.staff_number} onChangeText={(t) => setForm({ ...form, staff_number: t })} />
      <Field label="Department" value={form.department} onChangeText={(t) => setForm({ ...form, department: t })} />
      <Button label="Create account" onPress={create} />
      {rows.map((u) => {
        const c = statusColors(u.is_active ? 'Present' : 'Absent');
        return (
          <RowCard
            key={u.user_id}
            title={u.full_name}
            lines={[
              `${u.username} · ${u.role_name} · ${u.school_name || ''}`,
              u.locked_until ? `Locked until ${u.locked_until}` : `Last login ${u.last_login_at ? fmtDate(u.last_login_at) : 'never'}`,
            ]}
            right={<Badge label={u.is_active ? 'Active' : 'Inactive'} fg={c.fg} bg={c.bg} />}
          />
        );
      })}
      {rows.map((u) => (
        <Button
          key={`a-${u.user_id}`}
          label={u.is_active ? `Deactivate ${u.username}` : `Activate ${u.username}`}
          variant="secondary"
          onPress={() => act({ action: 'toggle', user_id: u.user_id, active: u.is_active ? 0 : 1 })}
        />
      ))}
      {rows
        .filter((u) => u.locked_until)
        .map((u) => (
          <Button key={`u-${u.user_id}`} label={`Unlock ${u.username}`} onPress={() => act({ action: 'unlock', user_id: u.user_id })} />
        ))}
    </Screen>
  );
}
