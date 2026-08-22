import React, { useCallback, useEffect, useState } from 'react';
import { StyleSheet, Text, TouchableOpacity, View } from 'react-native';
import { useNavigation } from '@react-navigation/native';
import { Screen, Tile, RowCard, Loading, ErrorText } from '../components/Screen';
import { Badge } from '../components/ui';
import { apiClient } from '../api/client';
import { useAuth } from '../context/AuthContext';
import { apiError, fmtTime } from '../roles';
import { colors, sessionStateColors as stateCols, statusColors as statusCols } from '../theme';

export function DashboardScreen() {
  const { user } = useAuth();
  const nav = useNavigation<any>();
  const [data, setData] = useState<any>(null);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);

  const load = useCallback(async () => {
    try {
      setError('');
      const res = await apiClient.get('/dashboard.php');
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

  const teacher = data?.teacher;
  const school = data?.school;
  const sessions = teacher?.sessions || [];
  const stats = teacher?.stats;
  const todayCount = sessions.length;

  return (
    <Screen
      title="Dashboard"
      subtitle={`${user?.full_name || ''} · ${user?.role_name || ''} · ${new Date().toLocaleDateString('en-GB', { weekday: 'long', day: 'numeric', month: 'long' })}`}
      refreshing={refreshing}
      onRefresh={() => {
        setRefreshing(true);
        void load();
      }}
    >
      {error ? <ErrorText message={error} /> : null}

      {teacher ? (
        <>
          <View style={styles.grid}>
            <Tile label="Sessions today" value={todayCount} foot={new Date().toLocaleDateString('en-GB', { weekday: 'long' })} />
            <Tile
              label="My rate this month"
              value={stats?.rate != null ? `${Number(stats.rate).toFixed(1)}%` : '-'}
              foot={`${stats?.sessions ?? 0} sessions recorded`}
              tone="info"
            />
            <Tile label="Late this month" value={stats?.late_count ?? 0} foot="arrivals after the grace period" tone="warn" />
            <Tile
              label="Absent this month"
              value={stats?.absent_count ?? 0}
              foot={`${stats?.excused_count ?? 0} excused by approved leave`}
              tone="bad"
            />
          </View>
          <Text style={styles.section}>My sessions today</Text>
          {sessions.length === 0 ? (
            <Text style={styles.empty}>Nothing scheduled today.</Text>
          ) : (
            sessions.map((s: any) => {
              const st = stateCols(s.session_state);
              const att = statusCols(s.status);
              return (
                <RowCard
                  key={s.timetable_id}
                  title={s.subject}
                  lines={[
                    `${fmtTime(s.start_time)} – ${fmtTime(s.end_time)} · ${s.class_group} · ${s.room_name}`,
                    s.status && Number(s.minutes_late) > 0 ? `${s.minutes_late} min late` : '',
                  ]}
                  right={
                    <View style={{ alignItems: 'flex-end', gap: 6 }}>
                      <Badge label={s.session_state} fg={st.fg} bg={st.bg} />
                      <Badge label={s.status || 'Not checked in'} fg={att.fg} bg={att.bg} />
                      {!s.status && s.qr_code_id ? (
                        <TouchableOpacity onPress={() => (nav.getParent() ?? nav).navigate('Checkin')}>
                          <Text style={styles.link}>Check in</Text>
                        </TouchableOpacity>
                      ) : null}
                    </View>
                  }
                />
              );
            })
          )}
        </>
      ) : null}

      {school ? (
        <>
          <Text style={styles.section}>School today</Text>
          <View style={styles.grid}>
            <Tile label="Sessions scheduled" value={school.today?.sessions ?? 0} foot={`${school.today?.running_now ?? 0} running right now`} />
            <Tile
              label="Checked in"
              value={(Number(school.today?.present_count || 0) + Number(school.today?.late_count || 0))}
              foot={`${school.today?.late_count ?? 0} of them late`}
              tone="ok"
            />
            <Tile label="Unstaffed right now" value={(school.unstaffed || []).length} foot="running with no check-in" tone={(school.unstaffed || []).length ? 'bad' : 'ok'} />
            <Tile label="Pending leave" value={school.pending_leave ?? 0} tone={school.pending_leave ? 'warn' : 'plain'} />
          </View>
          {(school.unstaffed || []).map((u: any, i: number) => (
            <RowCard
              key={`${u.teacher_name}-${i}`}
              title={u.teacher_name}
              lines={[`${u.subject} · ${u.class_group} · ${u.room_name}`, `${fmtTime(u.start_time)} – ${fmtTime(u.end_time)} · ${u.minutes_into_session} min in`]}
            />
          ))}
          {(school.attention || []).length ? <Text style={styles.section}>Needs attention this month</Text> : null}
          {(school.attention || []).map((t: any) => (
            <RowCard
              key={t.teacher_name}
              title={t.teacher_name}
              lines={[`${t.department || ''} · rate ${t.attendance_rate ?? '-'}%`, `Absent ${t.absent_count} · Late ${t.late_count}`]}
            />
          ))}
        </>
      ) : null}

      {!teacher && !school ? (
        <Text style={styles.empty}>Your account has no teacher record and no school-wide privileges.</Text>
      ) : null}
    </Screen>
  );
}

const styles = StyleSheet.create({
  grid: { flexDirection: 'row', flexWrap: 'wrap', justifyContent: 'space-between' },
  section: { color: colors.text, fontWeight: '700', fontSize: 16, marginTop: 8, marginBottom: 10 },
  empty: { color: colors.textMuted, marginBottom: 16 },
  link: { color: colors.primaryLight, fontWeight: '700', fontSize: 13 },
});
