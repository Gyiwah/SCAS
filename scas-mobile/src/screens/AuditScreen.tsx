import React, { useCallback, useEffect, useState } from 'react';
import { Screen, Field, RowCard, Loading, ErrorText } from '../components/Screen';
import { Badge, Button } from '../components/ui';
import { apiClient } from '../api/client';
import { apiError, fmtDate, todayISO } from '../roles';
import { statusColors } from '../theme';

export function AuditScreen() {
  const [from, setFrom] = useState(new Date(Date.now() - 7 * 86400000).toISOString().slice(0, 10));
  const [to, setTo] = useState(todayISO());
  const [table, setTable] = useState('');
  const [action, setAction] = useState('');
  const [rows, setRows] = useState<any[]>([]);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    try {
      setError('');
      const res = await apiClient.get('/audit.php', { params: { from, to, table, action_type: action } });
      setRows(res.data.data || []);
    } catch (e) {
      setError(apiError(e));
    } finally {
      setLoading(false);
    }
  }, [from, to, table, action]);

  useEffect(() => {
    void load();
  }, [load]);

  if (loading) return <Loading />;

  return (
    <Screen title="Audit trail" subtitle="Who changed what, and when. Written by database triggers.">
      {error ? <ErrorText message={error} /> : null}
      <Field label="Table" value={table} onChangeText={setTable} placeholder="all tables" />
      <Field label="Action (INSERT, UPDATE, DELETE)" value={action} onChangeText={setAction} />
      <Field label="From" value={from} onChangeText={setFrom} />
      <Field label="To" value={to} onChangeText={setTo} />
      <Button label="Apply" variant="secondary" onPress={() => void load()} />
      {rows.map((r) => {
        const c = statusColors(r.action === 'DELETE' ? 'Absent' : r.action === 'INSERT' ? 'Present' : 'Late');
        return (
          <RowCard
            key={r.audit_id}
            title={`${r.table_name} #${r.record_id}`}
            lines={[fmtDate(r.changed_at), r.changed_by_name || r.db_user, String(r.new_values || r.old_values || '').slice(0, 180)]}
            right={<Badge label={r.action} fg={c.fg} bg={c.bg} />}
          />
        );
      })}
    </Screen>
  );
}
