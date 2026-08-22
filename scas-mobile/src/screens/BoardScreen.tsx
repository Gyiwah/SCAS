import React, { useCallback, useEffect, useState } from 'react';
import { View } from 'react-native';
import { Screen, Tile, RowCard, Loading, ErrorText } from '../components/Screen';
import { Badge } from '../components/ui';
import { apiClient } from '../api/client';
import { apiError, fmtTime } from '../roles';
import { sessionStateColors, statusColors } from '../theme';

export function BoardScreen() {
  const [data, setData] = useState<any>(null);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);

  const load = useCallback(async () => {
    try {
      setError('');
      const res = await apiClient.get('/board.php');
      setData(res.data);
    } catch (e) {
      setError(apiError(e));
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  if (loading) return <Loading />;
  const counts = data?.counts || {};
  const rows = data?.data || [];

  return (
    <Screen
      title="Live board"
      subtitle="Every session scheduled today and its current check-in state."
      refreshing={refreshing}
      onRefresh={() => {
        setRefreshing(true);
        void load();
      }}
    >
      {error ? <ErrorText message={error} /> : null}
      <View style={{ flexDirection: 'row', flexWrap: 'wrap', justifyContent: 'space-between' }}>
        <Tile label="Scheduled today" value={rows.length} foot={`${data?.running ?? 0} in progress`} />
        <Tile label="Present" value={counts.Present ?? 0} tone="ok" />
        <Tile label="Late" value={counts.Late ?? 0} tone="warn" />
        <Tile label="No check-in" value={counts['No Scan'] ?? 0} foot={`${counts['On Leave'] ?? 0} on approved leave`} tone="bad" />
      </View>
      {rows.map((r: any, i: number) => {
        const st = sessionStateColors(r.session_state);
        const att = statusColors(r.attendance_state);
        return (
          <RowCard
            key={`${r.teacher_name}-${i}`}
            title={r.teacher_name}
            lines={[
              `${fmtTime(r.start_time)} – ${fmtTime(r.end_time)} · ${r.subject} · ${r.class_group} · ${r.room_name}`,
              `Code ${r.qr_state || '-'} · scanned ${r.scan_datetime ? fmtTime(r.scan_datetime) : '-'}`,
            ]}
            right={
              <View style={{ alignItems: 'flex-end', gap: 6 }}>
                <Badge label={r.session_state} fg={st.fg} bg={st.bg} />
                <Badge label={r.attendance_state} fg={att.fg} bg={att.bg} />
              </View>
            }
          />
        );
      })}
    </Screen>
  );
}
