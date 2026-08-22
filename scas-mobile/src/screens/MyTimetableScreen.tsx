import React, { useCallback, useEffect, useState } from 'react';
import { Screen, RowCard, Loading, ErrorText } from '../components/Screen';
import { Badge } from '../components/ui';
import { apiClient } from '../api/client';
import { apiError, fmtTime } from '../roles';
import { sessionStateColors, statusColors } from '../theme';

export function MyTimetableScreen() {
  const [rows, setRows] = useState<any[]>([]);
  const [term, setTerm] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);

  const load = useCallback(async () => {
    try {
      setError('');
      const res = await apiClient.get('/timetable.php', { params: { scope: 'week' } });
      setRows(res.data.data || []);
      setTerm(res.data.term_name || 'Current term');
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

  const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  const today = new Date().toLocaleDateString('en-US', { weekday: 'long' });

  return (
    <Screen
      title="My timetable"
      subtitle={term}
      refreshing={refreshing}
      onRefresh={() => {
        setRefreshing(true);
        void load();
      }}
    >
      {error ? <ErrorText message={error} /> : null}
      {rows.length === 0 ? <ErrorText message="You have no active sessions in the current term." /> : null}
      {days.map((day) => {
        const items = rows.filter((r) => r.day_of_week === day);
        if (!items.length) return null;
        return (
          <React.Fragment key={day}>
            {items.map((s: any) => (
              <RowCard
                key={s.timetable_id}
                title={`${day === today ? `${day} · today` : day} · ${s.subject}`}
                lines={[
                  `${fmtTime(s.start_time)} – ${fmtTime(s.end_time)} · ${s.duration_minutes || ''} min`,
                  `${s.class_group} · ${s.room_name}${s.building ? ` · ${s.building}` : ''}`,
                ]}
              />
            ))}
          </React.Fragment>
        );
      })}
    </Screen>
  );
}
