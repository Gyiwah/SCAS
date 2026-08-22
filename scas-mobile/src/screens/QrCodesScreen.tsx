import React, { useCallback, useEffect, useState } from 'react';
import { Text } from 'react-native';
import { Screen, Field, RowCard, Loading, ErrorText } from '../components/Screen';
import { Badge, Button } from '../components/ui';
import { apiClient } from '../api/client';
import { apiError, fmtTime, todayISO } from '../roles';
import { colors, statusColors } from '../theme';

export function QrCodesScreen() {
  const [date, setDate] = useState(todayISO());
  const [validity, setValidity] = useState('60');
  const [rows, setRows] = useState<any[]>([]);
  const [holiday, setHoliday] = useState(false);
  const [msg, setMsg] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    try {
      setError('');
      const res = await apiClient.get('/qrcodes.php', { params: { date } });
      setRows(res.data.data || []);
      setHoliday(Boolean(res.data.is_holiday));
    } catch (e) {
      setError(apiError(e));
    } finally {
      setLoading(false);
    }
  }, [date]);

  useEffect(() => {
    void load();
  }, [load]);

  const act = async (body: object) => {
    setMsg('');
    setError('');
    try {
      const res = await apiClient.post('/qrcodes.php', { date, validity: Number(validity), ...body });
      setMsg(res.data.message);
      await load();
    } catch (e) {
      setError(apiError(e));
    }
  };

  if (loading) return <Loading />;

  return (
    <Screen title="Session codes" subtitle="Issue the QR code a teacher scans to check in. Codes are single-use and expire.">
      {error ? <ErrorText message={error} /> : null}
      {msg ? <Text style={{ color: colors.present, marginBottom: 12 }}>{msg}</Text> : null}
      <Field label="Session date (YYYY-MM-DD)" value={date} onChangeText={setDate} />
      <Button label="Show" variant="secondary" onPress={() => void load()} />
      {holiday ? (
        <ErrorText message="This date is a holiday. The database refuses to create a session code." />
      ) : (
        <>
          <Field label="Validity (minutes)" value={validity} onChangeText={setValidity} keyboardType="numeric" />
          <Button label="Issue codes for every session" onPress={() => act({ action: 'generate_all' })} />
        </>
      )}
      {rows.map((s) => {
        const c = statusColors(s.code_state === 'VALID' ? 'Present' : s.code_state === 'Not issued' ? '' : 'Late');
        return (
          <RowCard
            key={s.timetable_id}
            title={`${s.teacher_name} · ${s.subject}`}
            lines={[
              `${fmtTime(s.start_time)} · ${s.room_name} · ${s.class_group}`,
              s.code_value ? `Code ${s.code_value}` : 'Not issued',
              s.expiry_datetime ? `Expires ${s.expiry_datetime}` : '',
              s.attendance_status ? `Attendance ${s.attendance_status}` : '',
            ]}
            right={<Badge label={s.code_state} fg={c.fg} bg={c.bg} />}
          />
        );
      })}
      {rows.filter((s) => s.qr_code_id && s.code_state === 'VALID').map((s) => (
        <Button
          key={`rev-${s.qr_code_id}`}
          label={`Revoke ${s.subject} (${s.teacher_name})`}
          variant="secondary"
          onPress={() => act({ action: 'revoke', qr_code_id: s.qr_code_id, reason: 'Revoked by administrator' })}
        />
      ))}
    </Screen>
  );
}
