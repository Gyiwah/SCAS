import React, { useCallback, useEffect, useState } from 'react';
import { View } from 'react-native';
import { Screen, Tile, Field, RowCard, Loading, ErrorText } from '../components/Screen';
import { Badge, Button } from '../components/ui';
import { apiClient } from '../api/client';
import { apiError, fmtDate, fmtTime, monthStartISO, todayISO } from '../roles';
import { statusColors } from '../theme';

export function AttendanceScreen() {
  const [from, setFrom] = useState(monthStartISO());
  const [to, setTo] = useState(todayISO());
  const [rows, setRows] = useState<any[]>([]);
  const [sum, setSum] = useState<any>(null);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);

  const load = useCallback(async () => {
    try {
      setError('');
      const res = await apiClient.get('/attendance.php', { params: { from, to } });
      setRows(res.data.data || []);
      setSum(res.data.summary);
    } catch (e) {
      setError(apiError(e));
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, [from, to]);

  useEffect(() => {
    void load();
  }, [load]);

  if (loading) return <Loading />;

  return (
    <Screen
      title="My attendance"
      subtitle="Your own record. An attendance row cannot be edited once written."
      refreshing={refreshing}
      onRefresh={() => {
        setRefreshing(true);
        void load();
      }}
    >
      {error ? <ErrorText message={error} /> : null}
      <View style={{ flexDirection: 'row', flexWrap: 'wrap', justifyContent: 'space-between' }}>
        <Tile label="Attendance rate" value={sum?.rate != null ? `${Number(sum.rate).toFixed(1)}%` : '-'} foot={`${sum?.sessions ?? 0} sessions in range`} tone="info" />
        <Tile label="Present" value={sum?.present_count ?? 0} tone="ok" />
        <Tile label="Late" value={sum?.late_count ?? 0} foot={`${sum?.total_late_minutes ?? 0} minutes in total`} tone="warn" />
        <Tile label="Absent" value={sum?.absent_count ?? 0} foot={`${sum?.excused_count ?? 0} excused by approved leave`} tone="bad" />
      </View>
      <Field label="From (YYYY-MM-DD)" value={from} onChangeText={setFrom} />
      <Field label="To (YYYY-MM-DD)" value={to} onChangeText={setTo} />
      <Button label="Apply" onPress={() => { setLoading(true); void load(); }} />
      <View style={{ height: 12 }} />
      {rows.length === 0 ? <ErrorText message="No records in this range. Try widening the dates." /> : null}
      {rows.map((r, i) => {
        const c = statusColors(r.status);
        return (
          <RowCard
            key={`${r.session_date}-${r.start_time}-${i}`}
            title={r.subject}
            lines={[
              `${fmtDate(r.session_date)} · ${r.class_group} · ${r.room_name}`,
              `Bell ${fmtTime(r.start_time)}${r.scan_datetime ? ` · checked in ${fmtTime(r.scan_datetime)}` : ''}`,
              r.remarks || (Number(r.minutes_late) ? `${r.minutes_late} min late` : ''),
            ]}
            right={<Badge label={r.status} fg={c.fg} bg={c.bg} />}
          />
        );
      })}
    </Screen>
  );
}
