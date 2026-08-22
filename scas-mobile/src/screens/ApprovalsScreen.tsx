import React, { useCallback, useEffect, useState } from 'react';
import { Text } from 'react-native';
import { Screen, Field, RowCard, Loading, ErrorText } from '../components/Screen';
import { Badge, Button } from '../components/ui';
import { apiClient } from '../api/client';
import { apiError, fmtDate } from '../roles';
import { colors, statusColors } from '../theme';

export function ApprovalsScreen() {
  const [pending, setPending] = useState<any[]>([]);
  const [recent, setRecent] = useState<any[]>([]);
  const [remarks, setRemarks] = useState<Record<number, string>>({});
  const [msg, setMsg] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    try {
      setError('');
      const res = await apiClient.get('/approvals.php');
      setPending(res.data.pending || []);
      setRecent(res.data.recent || []);
    } catch (e) {
      setError(apiError(e));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  const decide = async (id: number, decision: string) => {
    setMsg('');
    try {
      const res = await apiClient.post('/approvals.php', {
        leave_request_id: id,
        decision,
        remarks: remarks[id] || '',
      });
      setMsg(res.data.message);
      await load();
    } catch (e) {
      setError(apiError(e));
    }
  };

  if (loading) return <Loading />;

  return (
    <Screen title="Leave approvals" subtitle="Approving a request also corrects Absent records already written for those dates.">
      {error ? <ErrorText message={error} /> : null}
      {msg ? <Text style={{ color: colors.present, marginBottom: 12 }}>{msg}</Text> : null}
      {pending.length === 0 ? <ErrorText message="The queue is empty. No requests are waiting." /> : null}
      {pending.map((p) => (
        <RowCard
          key={p.leave_request_id}
          title={p.teacher_name}
          lines={[
            `${p.staff_number} · ${p.department} · ${p.leave_type}`,
            `${fmtDate(p.start_date)} – ${fmtDate(p.end_date)} · ${p.days_requested} day(s)`,
            p.reason,
            `Waiting ${p.days_waiting}d · ${p.sessions_affected} sessions`,
          ]}
        />
      ))}
      {pending.map((p) => (
        <React.Fragment key={`act-${p.leave_request_id}`}>
          <Field
            label={`Remarks for ${p.teacher_name}`}
            value={remarks[p.leave_request_id] || ''}
            onChangeText={(t) => setRemarks((m) => ({ ...m, [p.leave_request_id]: t }))}
          />
          <Button label="Approve" onPress={() => decide(p.leave_request_id, 'Approved')} />
          <Button label="Reject" variant="secondary" onPress={() => decide(p.leave_request_id, 'Rejected')} />
        </React.Fragment>
      ))}
      {recent.map((r, i) => {
        const c = statusColors(r.status === 'Approved' ? 'Present' : 'Absent');
        return (
          <RowCard
            key={`${r.leave_request_id}-${i}`}
            title={r.teacher_name}
            lines={[`${r.leave_type} · ${fmtDate(r.start_date)} – ${fmtDate(r.end_date)}`, r.approved_by_name, r.remarks]}
            right={<Badge label={r.status} fg={c.fg} bg={c.bg} />}
          />
        );
      })}
    </Screen>
  );
}
