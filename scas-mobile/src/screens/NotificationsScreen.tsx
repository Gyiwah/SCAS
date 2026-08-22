import React, { useCallback, useEffect, useState } from 'react';
import { Screen, RowCard, Loading, ErrorText } from '../components/Screen';
import { Badge, Button } from '../components/ui';
import { apiClient } from '../api/client';
import { apiError, fmtDate } from '../roles';
import { statusColors } from '../theme';

export function NotificationsScreen() {
  const [rows, setRows] = useState<any[]>([]);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);

  const load = useCallback(async () => {
    try {
      setError('');
      const res = await apiClient.get('/notifications.php');
      setRows(res.data.data || []);
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

  const markRead = async () => {
    await apiClient.post('/notifications.php', { action: 'mark_read' });
    await load();
  };

  if (loading) return <Loading />;

  return (
    <Screen
      title="Notifications"
      subtitle="Raised when attendance is recorded or leave is actioned."
      refreshing={refreshing}
      onRefresh={() => {
        setRefreshing(true);
        void load();
      }}
    >
      {error ? <ErrorText message={error} /> : null}
      {rows.length ? <Button label="Mark all as read" variant="secondary" onPress={markRead} /> : null}
      {rows.length === 0 ? <ErrorText message="Nothing yet. Notifications appear here as they are raised." /> : null}
      {rows.map((n) => {
        const c = statusColors(n.notif_type === 'SUCCESS' ? 'Present' : n.notif_type === 'ALERT' ? 'Absent' : 'Late');
        return (
          <RowCard
            key={n.notification_id}
            title={n.title}
            lines={[fmtDate(n.created_at), n.message]}
            right={<Badge label={n.notif_type} fg={c.fg} bg={c.bg} />}
          />
        );
      })}
    </Screen>
  );
}
