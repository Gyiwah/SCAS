import React, { useState, useEffect, useCallback } from 'react';
import {
  StyleSheet,
  Text,
  View,
  FlatList,
  RefreshControl,
  ActivityIndicator,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import { apiClient } from '../api/client';

interface AttendanceRecord {
  attendance_id: number;
  session_date: string;
  status: 'Present' | 'Late' | 'Excused' | 'Absent';
  minutes_late: number | null;
  scan_datetime: string;
  subject: string;
  class_group: string;
  room_name: string;
  start_time: string;
  end_time: string;
}

interface SummaryData {
  total_records: number;
  present_count: number;
  late_count: number;
  excused_count: number;
  absent_count: number;
}

export const HistoryScreen = () => {
  const [history, setHistory] = useState<AttendanceRecord[]>([]);
  const [summary, setSummary] = useState<SummaryData | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [errorMsg, setErrorMsg] = useState('');

  const fetchHistory = async () => {
    try {
      setErrorMsg('');
      const response = await apiClient.get('/attendance.php');
      if (response.data?.status === 'success') {
        setHistory(response.data.data || []);
        setSummary(response.data.summary || null);
      } else {
        setErrorMsg(response.data?.message || 'Failed to load attendance history.');
      }
    } catch (error: any) {
      setErrorMsg(error.response?.data?.message || error.message || 'Error connecting to SCAS server.');
    } finally {
      setIsLoading(false);
      setIsRefreshing(false);
    }
  };

  useEffect(() => {
    fetchHistory();
  }, []);

  const onRefresh = useCallback(() => {
    setIsRefreshing(true);
    fetchHistory();
  }, []);

  const getStatusStyle = (status: string) => {
    switch (status) {
      case 'Present':
        return { bg: 'rgba(34, 197, 94, 0.15)', text: '#4ADE80', icon: 'checkmark-circle' };
      case 'Late':
        return { bg: 'rgba(245, 158, 11, 0.15)', text: '#FBBF24', icon: 'warning' };
      case 'Excused':
        return { bg: 'rgba(59, 130, 246, 0.15)', text: '#60A5FA', icon: 'document-text' };
      default:
        return { bg: 'rgba(239, 68, 68, 0.15)', text: '#FCA5A5', icon: 'alert-circle' };
    }
  };

  const renderHeaderSummary = () => {
    if (!summary) return null;
    return (
      <View style={styles.statsCard}>
        <Text style={styles.statsTitle}>Attendance Summary</Text>

        <View style={styles.statsGrid}>
          <View style={styles.statBox}>
            <Text style={[styles.statValue, { color: '#4ADE80' }]}>{summary.present_count || 0}</Text>
            <Text style={styles.statLabel}>Present</Text>
          </View>

          <View style={styles.statBox}>
            <Text style={[styles.statValue, { color: '#FBBF24' }]}>{summary.late_count || 0}</Text>
            <Text style={styles.statLabel}>Late</Text>
          </View>

          <View style={styles.statBox}>
            <Text style={[styles.statValue, { color: '#60A5FA' }]}>{summary.excused_count || 0}</Text>
            <Text style={styles.statLabel}>Excused</Text>
          </View>

          <View style={styles.statBox}>
            <Text style={[styles.statValue, { color: '#FCA5A5' }]}>{summary.absent_count || 0}</Text>
            <Text style={styles.statLabel}>Absent</Text>
          </View>
        </View>
      </View>
    );
  };

  const renderHistoryItem = ({ item }: { item: AttendanceRecord }) => {
    const styleInfo = getStatusStyle(item.status);
    return (
      <View style={styles.card}>
        <View style={styles.cardTop}>
          <View>
            <Text style={styles.subjectText}>{item.subject}</Text>
            <Text style={styles.dateText}>{item.session_date} • {item.class_group}</Text>
          </View>

          <View style={[styles.statusBadge, { backgroundColor: styleInfo.bg }]}>
            <Ionicons name={styleInfo.icon as any} size={14} color={styleInfo.text} />
            <Text style={[styles.statusText, { color: styleInfo.text }]}>
              {item.status}
            </Text>
          </View>
        </View>

        <View style={styles.cardBottom}>
          <View style={styles.bottomDetail}>
            <Ionicons name="location-outline" size={14} color="#64748B" />
            <Text style={styles.bottomDetailText}>{item.room_name}</Text>
          </View>

          {item.minutes_late ? (
            <Text style={styles.lateDetailText}>{item.minutes_late} min late</Text>
          ) : null}
        </View>
      </View>
    );
  };

  return (
    <SafeAreaView style={styles.container}>
      <View style={styles.header}>
        <Text style={styles.title}>Attendance History</Text>
        <Text style={styles.subtitle}>Recent Check-Ins & Records</Text>
      </View>

      {isLoading ? (
        <View style={styles.centerContainer}>
          <ActivityIndicator size="large" color="#2563EB" />
        </View>
      ) : errorMsg ? (
        <View style={styles.centerContainer}>
          <Ionicons name="alert-circle-outline" size={48} color="#EF4444" />
          <Text style={styles.errorText}>{errorMsg}</Text>
        </View>
      ) : (
        <FlatList
          data={history}
          keyExtractor={(item) => item.attendance_id.toString()}
          renderItem={renderHistoryItem}
          ListHeaderComponent={renderHeaderSummary}
          contentContainerStyle={styles.listContent}
          refreshControl={
            <RefreshControl
              refreshing={isRefreshing}
              onRefresh={onRefresh}
              tintColor="#60A5FA"
              colors={['#2563EB']}
            />
          }
          ListEmptyComponent={
            <View style={styles.emptyContainer}>
              <Ionicons name="documents-outline" size={56} color="#475569" />
              <Text style={styles.emptyTitle}>No Attendance Records</Text>
              <Text style={styles.emptyText}>You have no recorded attendance entries yet.</Text>
            </View>
          }
        />
      )}
    </SafeAreaView>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#0F172A',
  },
  header: {
    paddingHorizontal: 20,
    paddingTop: 16,
    paddingBottom: 12,
  },
  title: {
    fontSize: 24,
    fontWeight: '800',
    color: '#FFFFFF',
  },
  subtitle: {
    fontSize: 14,
    color: '#94A3B8',
    marginTop: 2,
  },
  centerContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    padding: 24,
  },
  errorText: {
    color: '#FCA5A5',
    fontSize: 15,
    marginTop: 12,
    textAlign: 'center',
  },
  listContent: {
    padding: 20,
    paddingTop: 8,
  },
  statsCard: {
    backgroundColor: '#1E293B',
    borderRadius: 16,
    padding: 18,
    marginBottom: 20,
    borderWidth: 1,
    borderColor: '#334155',
  },
  statsTitle: {
    fontSize: 16,
    fontWeight: '700',
    color: '#FFFFFF',
    marginBottom: 14,
  },
  statsGrid: {
    flexDirection: 'row',
    justifyContent: 'space-between',
  },
  statBox: {
    alignItems: 'center',
    flex: 1,
  },
  statValue: {
    fontSize: 22,
    fontWeight: '800',
  },
  statLabel: {
    color: '#94A3B8',
    fontSize: 12,
    marginTop: 4,
  },
  card: {
    backgroundColor: '#1E293B',
    borderRadius: 14,
    padding: 16,
    marginBottom: 12,
    borderWidth: 1,
    borderColor: '#334155',
  },
  cardTop: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'flex-start',
    marginBottom: 10,
  },
  subjectText: {
    fontSize: 16,
    fontWeight: '700',
    color: '#FFFFFF',
  },
  dateText: {
    fontSize: 13,
    color: '#94A3B8',
    marginTop: 3,
  },
  statusBadge: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 10,
    paddingVertical: 5,
    borderRadius: 10,
  },
  statusText: {
    fontSize: 13,
    fontWeight: '700',
    marginLeft: 5,
  },
  cardBottom: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingTop: 10,
    borderTopWidth: 1,
    borderTopColor: '#334155',
  },
  bottomDetail: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  bottomDetailText: {
    color: '#64748B',
    fontSize: 13,
    marginLeft: 6,
  },
  lateDetailText: {
    color: '#FBBF24',
    fontSize: 13,
    fontWeight: '600',
  },
  emptyContainer: {
    alignItems: 'center',
    justifyContent: 'center',
    padding: 40,
    marginTop: 20,
  },
  emptyTitle: {
    color: '#FFFFFF',
    fontSize: 18,
    fontWeight: '700',
    marginTop: 16,
  },
  emptyText: {
    color: '#64748B',
    fontSize: 14,
    textAlign: 'center',
    marginTop: 6,
  },
});
