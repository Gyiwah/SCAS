import React, { useCallback, useEffect, useState } from 'react';
import { Text, View } from 'react-native';
import { Screen, Field, Tile, RowCard, Loading, ErrorText } from '../components/Screen';
import { Badge, Button } from '../components/ui';
import { apiClient } from '../api/client';
import { apiError } from '../roles';
import { colors, statusColors } from '../theme';

const TABS = ['overview', 'indexes', 'integrity', 'transactions', 'recovery', 'performance'];

export function DbaScreen() {
  const [tab, setTab] = useState('overview');
  const [data, setData] = useState<any>(null);
  const [sql, setSql] = useState('SELECT * FROM v_live_session_board LIMIT 5');
  const [explain, setExplain] = useState<any[]>([]);
  const [demo, setDemo] = useState<any[]>([]);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    try {
      setError('');
      const res = await apiClient.get('/dba.php', { params: { tab } });
      setData(res.data);
    } catch (e) {
      setError(apiError(e));
    } finally {
      setLoading(false);
    }
  }, [tab]);

  useEffect(() => {
    setLoading(true);
    void load();
  }, [load]);

  const post = async (body: object) => {
    try {
      const res = await apiClient.post('/dba.php', body);
      if (res.data.data) {
        if ((body as any).action === 'explain') setExplain(res.data.data);
        else setDemo(res.data.data);
      }
    } catch (e) {
      setError(apiError(e));
    }
  };

  if (loading && !data) return <Loading />;

  return (
    <Screen title="DBA console" subtitle="Inspected through the least-privileged application account.">
      {error ? <ErrorText message={error} /> : null}
      <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 8, marginBottom: 12 }}>
        {TABS.map((t) => (
          <Button key={t} label={t} variant={tab === t ? 'primary' : 'secondary'} onPress={() => setTab(t)} />
        ))}
      </View>
      {tab === 'overview' ? (
        <View style={{ flexDirection: 'row', flexWrap: 'wrap', justifyContent: 'space-between' }}>
          {(data?.objects || []).map((o: any) => (
            <Tile key={o.object_type} label={o.object_type} value={o.count} />
          ))}
        </View>
      ) : null}
      {tab === 'overview' &&
        (data?.sizes || []).slice(0, 20).map((t: any) => (
          <RowCard key={t.TABLE_NAME} title={t.TABLE_NAME} lines={[`${t.ENGINE} · ${t.TABLE_ROWS} rows · ${t.data_kb} KB data`]} />
        ))}
      {tab === 'indexes' &&
        (data?.redundant || []).map((r: any, i: number) => (
          <RowCard key={i} title={`${r.TABLE_NAME}.${r.redundant_index}`} lines={[`Covered by ${r.covered_by}`]} />
        ))}
      {tab === 'indexes' && !(data?.redundant || []).length ? (
        <Text style={{ color: colors.textMuted, marginBottom: 12 }}>No redundant indexes.</Text>
      ) : null}
      {tab === 'integrity' &&
        (data?.checks || []).map((c: any) => {
          const col = statusColors(Number(c.violations) === 0 ? 'Present' : 'Absent');
          return (
            <RowCard
              key={c.check_name}
              title={c.check_name}
              lines={[`${c.violations} violation(s)`]}
              right={<Badge label={Number(c.violations) === 0 ? 'PASS' : 'FAIL'} fg={col.fg} bg={col.bg} />}
            />
          );
        })}
      {tab === 'transactions' ? (
        <>
          <Button label="Run savepoint demonstration" onPress={() => post({ action: 'demo_savepoint' })} />
          <Button label="Run consistency demonstration" variant="secondary" onPress={() => post({ action: 'demo_consistency' })} />
          {demo.map((row, i) => (
            <RowCard key={i} title={String(row.result || row.step || i)} lines={Object.values(row).map(String)} />
          ))}
          {(data?.locks || []).map((l: any, i: number) => (
            <RowCard key={i} title={l.trx_id || 'lock'} lines={Object.entries(l).map(([k, v]) => `${k}: ${v}`)} />
          ))}
        </>
      ) : null}
      {tab === 'recovery' &&
        (data?.recovery || []).map((r: any, i: number) => (
          <RowCard key={i} title={String(r.status || 'backup')} lines={Object.entries(r).map(([k, v]) => `${k}: ${v}`)} />
        ))}
      {tab === 'recovery' &&
        (data?.settings || []).map((s: any) => (
          <RowCard key={s.setting_key} title={s.setting_key} lines={[String(s.setting_value), s.description]} />
        ))}
      {tab === 'performance' &&
        (data?.worst || []).map((w: any) => (
          <RowCard key={w.query_label} title={w.query_label} lines={[`avg ${w.avg_ms} ms · max ${w.max_ms} ms · ${w.occurrences} times`]} />
        ))}
      <Text style={{ color: colors.text, fontWeight: '700', marginTop: 8, marginBottom: 8 }}>EXPLAIN (SELECT only)</Text>
      <Field label="SQL" value={sql} onChangeText={setSql} multiline />
      <Button label="Explain" variant="secondary" onPress={() => post({ action: 'explain', sql })} />
      {explain.map((row, i) => (
        <RowCard key={i} title={String(row.table || row.id || i)} lines={Object.entries(row).map(([k, v]) => `${k}: ${v}`)} />
      ))}
    </Screen>
  );
}
