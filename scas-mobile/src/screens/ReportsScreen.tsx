import React, { useCallback, useEffect, useState } from 'react';
import { View } from 'react-native';
import { Screen, Field, Tile, RowCard, Loading, ErrorText } from '../components/Screen';
import { Button } from '../components/ui';
import { apiClient } from '../api/client';
import { apiError } from '../roles';

export function ReportsScreen() {
  const now = new Date();
  const [year, setYear] = useState(String(now.getFullYear()));
  const [month, setMonth] = useState(String(now.getMonth() + 1));
  const [schoolId, setSchoolId] = useState('');
  const [data, setData] = useState<any>(null);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    try {
      setError('');
      const params: any = { year, month };
      if (schoolId) params.school_id = schoolId;
      const res = await apiClient.get('/reports.php', { params });
      setData(res.data);
      if (!schoolId && res.data.school_id) setSchoolId(String(res.data.school_id));
    } catch (e) {
      setError(apiError(e));
    } finally {
      setLoading(false);
    }
  }, [year, month, schoolId]);

  useEffect(() => {
    void load();
  }, [load]);

  if (loading) return <Loading />;
  const report = data?.report || [];
  const totals = report.reduce(
    (a: any, r: any) => ({
      sessions: a.sessions + Number(r.sessions_recorded || 0),
      present: a.present + Number(r.present_count || 0),
      late: a.late + Number(r.late_count || 0),
      absent: a.absent + Number(r.absent_count || 0),
    }),
    { sessions: 0, present: 0, late: 0, absent: 0 }
  );

  return (
    <Screen title="Reports" subtitle={data?.school_name || ''}>
      {error ? <ErrorText message={error} /> : null}
      {(data?.schools || []).length ? (
        <Field label="School id" value={schoolId} onChangeText={setSchoolId} keyboardType="numeric" />
      ) : null}
      <Field label="Month (1-12)" value={month} onChangeText={setMonth} keyboardType="numeric" />
      <Field label="Year" value={year} onChangeText={setYear} keyboardType="numeric" />
      <Button label="Apply" variant="secondary" onPress={() => void load()} />
      <View style={{ flexDirection: 'row', flexWrap: 'wrap', justifyContent: 'space-between', marginTop: 12 }}>
        <Tile label="Sessions" value={totals.sessions} />
        <Tile label="Present" value={totals.present} tone="ok" />
        <Tile label="Late" value={totals.late} tone="warn" />
        <Tile label="Absent" value={totals.absent} tone="bad" />
      </View>
      {(data?.ranking || []).map((r: any) => (
        <RowCard
          key={r.teacher_name}
          title={`${r.school_rank}. ${r.teacher_name}`}
          lines={[`${r.department} · rate ${r.attendance_rate}%`, `P ${r.present_count} L ${r.late_count} A ${r.absent_count}`]}
        />
      ))}
    </Screen>
  );
}
