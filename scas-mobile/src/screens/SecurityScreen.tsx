import React, { useCallback, useEffect, useState } from 'react';
import { View } from 'react-native';
import { Screen, Field, Tile, RowCard, Loading, ErrorText } from '../components/Screen';
import { Badge, Button } from '../components/ui';
import { apiClient } from '../api/client';
import { apiError, fmtDate } from '../roles';
import { statusColors } from '../theme';

export function SecurityScreen() {
  const [hours, setHours] = useState('24');
  const [data, setData] = useState<any>(null);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    try {
      setError('');
      const res = await apiClient.get('/security.php', { params: { hours } });
      setData(res.data);
    } catch (e) {
      setError(apiError(e));
    } finally {
      setLoading(false);
    }
  }, [hours]);

  useEffect(() => {
    void load();
  }, [load]);

  const unlock = async (userId: number) => {
    try {
      await apiClient.post('/security.php', { action: 'unlock', user_id: userId });
      await load();
    } catch (e) {
      setError(apiError(e));
    }
  };

  if (loading) return <Loading />;
  const events = data?.events || [];
  const locked = data?.locked || [];
  const critical = (data?.summary || []).reduce(
    (n: number, s: any) => n + (s.severity === 'CRITICAL' ? Number(s.occurrences) : 0),
    0
  );

  return (
    <Screen title="Security" subtitle={`Authentication telemetry for the last ${hours} hours.`}>
      {error ? <ErrorText message={error} /> : null}
      <Field label="Hours" value={hours} onChangeText={setHours} keyboardType="numeric" />
      <Button label="Apply" variant="secondary" onPress={() => void load()} />
      <View style={{ flexDirection: 'row', flexWrap: 'wrap', justifyContent: 'space-between' }}>
        <Tile label="Events recorded" value={events.length} />
        <Tile label="Critical events" value={critical} tone={critical ? 'bad' : 'ok'} />
        <Tile label="Locked accounts" value={locked.length} tone={locked.length ? 'warn' : 'ok'} />
      </View>
      {locked.map((u: any) => (
        <Button key={u.user_id} label={`Unlock ${u.username}`} onPress={() => unlock(u.user_id)} />
      ))}
      {events.slice(0, 80).map((e: any) => {
        const c = statusColors(e.severity === 'CRITICAL' ? 'Absent' : e.severity === 'WARNING' ? 'Late' : 'Present');
        return (
          <RowCard
            key={e.event_id}
            title={e.event_type}
            lines={[fmtDate(e.occurred_at), e.username_attempted, e.ip_address, e.detail]}
            right={<Badge label={e.severity} fg={c.fg} bg={c.bg} />}
          />
        );
      })}
    </Screen>
  );
}
