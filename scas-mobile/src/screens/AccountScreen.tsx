import React, { useCallback, useEffect, useState } from 'react';
import { Text } from 'react-native';
import { Screen, Field, RowCard, Loading, ErrorText } from '../components/Screen';
import { Button } from '../components/ui';
import { apiClient } from '../api/client';
import { useAuth } from '../context/AuthContext';
import { apiError, fmtDate } from '../roles';
import { colors } from '../theme';

export function AccountScreen() {
  const { user, logout } = useAuth();
  const [profile, setProfile] = useState<any>(user);
  const [events, setEvents] = useState<any[]>([]);
  const [current, setCurrent] = useState('');
  const [next, setNext] = useState('');
  const [confirm, setConfirm] = useState('');
  const [msg, setMsg] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);

  const load = useCallback(async () => {
    try {
      const res = await apiClient.get('/profile.php');
      setProfile(res.data.user);
      setEvents(res.data.events || []);
    } catch (e) {
      setError(apiError(e));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  const changePassword = async () => {
    setSaving(true);
    setError('');
    setMsg('');
    try {
      const res = await apiClient.post('/profile.php', {
        current_password: current,
        new_password: next,
        confirm_password: confirm,
      });
      setMsg(res.data.message);
      setCurrent('');
      setNext('');
      setConfirm('');
    } catch (e) {
      setError(apiError(e));
    } finally {
      setSaving(false);
    }
  };

  if (loading) return <Loading />;

  return (
    <Screen title="My account" subtitle="Your details and recent sign-in activity.">
      {error ? <ErrorText message={error} /> : null}
      {msg ? <Text style={{ color: colors.present, marginBottom: 12 }}>{msg}</Text> : null}
      <RowCard
        title={profile?.full_name || user?.full_name || ''}
        lines={[
          `Username ${profile?.username || user?.username}`,
          `${profile?.role_name || user?.role_name} (privilege ${profile?.privilege_level ?? user?.privilege_level})`,
          profile?.school_name || user?.school_name || 'All schools',
          profile?.staff_number ? `Staff ${profile.staff_number} · ${profile.department || ''}` : '',
          profile?.last_login_at ? `Previous sign-in ${fmtDate(profile.last_login_at)}` : '',
        ]}
      />
      <Field label="Current password" value={current} onChangeText={setCurrent} secure />
      <Field label="New password — at least 8 characters" value={next} onChangeText={setNext} secure />
      <Field label="Confirm new password" value={confirm} onChangeText={setConfirm} secure />
      <Button label="Change password" onPress={changePassword} loading={saving} />
      <Text style={{ color: colors.textMuted, fontSize: 13, marginVertical: 16 }}>
        Passwords are stored only as bcrypt hashes. Nobody can read your password out of the database.
      </Text>
      {events.map((e, i) => (
        <RowCard
          key={`${e.occurred_at}-${i}`}
          title={e.event_type}
          lines={[fmtDate(e.occurred_at), e.ip_address, e.detail]}
        />
      ))}
      <Button label="Sign out" variant="secondary" onPress={() => logout()} />
    </Screen>
  );
}
