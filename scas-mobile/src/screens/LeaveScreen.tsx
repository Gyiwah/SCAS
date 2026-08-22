import React, { useCallback, useEffect, useState } from 'react';
import { Text } from 'react-native';
import { Screen, Field, RowCard, Loading, ErrorText } from '../components/Screen';
import { Badge, Button } from '../components/ui';
import { apiClient } from '../api/client';
import { apiError, fmtDate, todayISO } from '../roles';
import { colors, statusColors } from '../theme';

const TYPES = ['Casual', 'Sick', 'Maternity', 'Study', 'Compassionate', 'Official Duty'];

export function LeaveScreen() {
  const [rows, setRows] = useState<any[]>([]);
  const [maxBack, setMaxBack] = useState('');
  const [leaveType, setLeaveType] = useState('Casual');
  const [start, setStart] = useState(todayISO());
  const [end, setEnd] = useState(todayISO());
  const [reason, setReason] = useState('');
  const [msg, setMsg] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);

  const load = useCallback(async () => {
    try {
      setError('');
      const res = await apiClient.get('/leave.php');
      setRows(res.data.data || []);
      setMaxBack(String(res.data.max_backdate_days ?? ''));
    } catch (e) {
      setError(apiError(e));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  const submit = async () => {
    setSaving(true);
    setMsg('');
    try {
      const res = await apiClient.post('/leave.php', {
        leave_type: leaveType,
        start_date: start,
        end_date: end,
        reason,
      });
      setMsg(res.data.message);
      setReason('');
      await load();
    } catch (e) {
      setError(apiError(e));
    } finally {
      setSaving(false);
    }
  };

  if (loading) return <Loading />;

  return (
    <Screen title="My leave" subtitle="Approved leave is recorded as Excused rather than Absent.">
      {error ? <ErrorText message={error} /> : null}
      {msg ? <Text style={{ color: colors.present, marginBottom: 12 }}>{msg}</Text> : null}
      <Field label="Type of leave" value={leaveType} onChangeText={setLeaveType} placeholder={TYPES.join(', ')} />
      <Field label="First day (YYYY-MM-DD)" value={start} onChangeText={setStart} />
      <Field label="Last day (YYYY-MM-DD)" value={end} onChangeText={setEnd} />
      <Field label="Reason — at least 5 characters" value={reason} onChangeText={setReason} multiline />
      <Button label="Submit request" onPress={submit} loading={saving} />
      <Text style={{ color: colors.textMuted, fontSize: 13, marginTop: 10, marginBottom: 16 }}>
        Leave cannot be backdated by more than {maxBack || '...'} days, and cannot overlap a pending or approved request.
      </Text>
      {rows.map((r) => {
        const c = statusColors(r.status === 'Approved' ? 'Present' : r.status === 'Rejected' ? 'Absent' : 'Late');
        return (
          <RowCard
            key={r.leave_request_id}
            title={r.leave_type}
            lines={[
              `${fmtDate(r.start_date)} – ${fmtDate(r.end_date)} · ${r.days_requested} day(s)`,
              r.reason,
              r.approved_by_name ? `Actioned by ${r.approved_by_name}` : '',
              r.remarks || '',
            ]}
            right={<Badge label={r.status} fg={c.fg} bg={c.bg} />}
          />
        );
      })}
    </Screen>
  );
}
