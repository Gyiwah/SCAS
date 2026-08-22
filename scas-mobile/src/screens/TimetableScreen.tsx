import React, { useState, useEffect, useCallback } from 'react';
import {
  StyleSheet,
  Text,
  View,
  FlatList,
  RefreshControl,
  ActivityIndicator,
  TouchableOpacity,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import { apiClient } from '../api/client';
import { useAuth } from '../context/AuthContext';

interface SessionItem {
  timetable_id: number;
  subject: string;
  class_group: string;
  room_name: string;
  start_time: string;
  end_time: string;
  status: string | null;
  minutes_late: number | null;
  session_state: 'Upcoming' | 'In Progress' | 'Ended';
}

export const TimetableScreen = () => {
  const { user, logout } = useAuth();
  const [sessions, setSessions] = useState<SessionItem[]>([]);
  const [todayDate, setTodayDate] = useState('');
  const [isLoading, setIsLoading] = useState(true);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [errorMsg, setErrorMsg] = useState('');

  const fetchTimetable = async () => {
    try {
      setErrorMsg('');
      const response = await apiClient.get('/timetable.php');
      if (response.data?.status === 'success') {
        setSessions(response.data.data || []);
        setTodayDate(response.data.date || '');
      } else {
        setErrorMsg(response.data?.message || 'Failed to load timetable.');
      }
    } catch (error: any) {
      setErrorMsg(error.response?.data?.message || error.message || 'Error connecting to SCAS server.');
    } finally {
      setIsLoading(false);
      setIsRefreshing(false);
    }
  };

  useEffect(() => {
    fetchTimetable();
  }, []);

  const onRefresh = useCallback(() => {
    setIsRefreshing(true);
    fetchTimetable();
  }, []);

  const renderStateBadge = (state: string) => {
    switch (state) {
      case 'In Progress':
        return (
          <View style={[styles.badge, styles.inProgressBadge]}>
            <View style={styles.liveDot} />
            <Text style={styles.inProgressBadgeText}>In Progress</Text>
          </View>
        );
      case 'Upcoming':
        return (
          <View style={[styles.badge, styles.upcomingBadge]}>
            <Text style={styles.upcomingBadgeText}>Upcoming</Text>
          </View>
        );
      default:
        return (
          <View style={[styles.badge, styles.endedBadge]}>
            <Text style={styles.endedBadgeText}>Ended</Text>
          </View>
        );
    }
  };

  const renderAttendanceBadge = (status: string | null, minutesLate: number | null) => {
    if (!status) return null;
    const isPresent = status === 'Present';
    return (
      <View style={[styles.attBadge, isPresent ? styles.presentAtt : styles.lateAtt]}>
        <Ionicons
          name={isPresent ? 'checkmark-circle' : 'time'}
          size={14}
          color={isPresent ? '#4ADE80' : '#FBBF24'}
        />
        <Text style={isPresent ? styles.presentAttText : styles.lateAttText}>
          {status} {minutesLate ? `(${minutesLate}m late)` : ''}
        </Text>
      </View>
    );
  };

  const renderSessionCard = ({ item }: { item: SessionItem }) => (
    <View style={styles.card}>
      <View style={styles.cardHeader}>
        <View style={styles.timeWrapper}>
          <Ionicons name="time-outline" size={16} color="#94A3B8" />
          <Text style={styles.timeText}>
            {(item.start_time || '').substring(0, 5)} - {(item.end_time || '').substring(0, 5)}
          </Text>
        </View>
        {renderStateBadge(item.session_state)}
      </View>

      <Text style={styles.subjectText}>{item.subject}</Text>
      
      <View style={styles.detailsRow}>
        <View style={styles.detailItem}>
          <Ionicons name="people-outline" size={16} color="#64748B" />
          <Text style={styles.detailText}>{item.class_group}</Text>
        </View>

        <View style={styles.detailItem}>
          <Ionicons name="location-outline" size={16} color="#64748B" />
          <Text style={styles.detailText}>{item.room_name}</Text>
        </View>
      </View>

      {item.status ? (
        <View style={styles.cardFooter}>
          <Text style={styles.footerLabel}>Status:</Text>
          {renderAttendanceBadge(item.status, item.minutes_late)}
        </View>
      ) : null}
    </View>
  );

  return (
    <SafeAreaView style={styles.container}>
      <View style={styles.header}>
        <View style={styles.headerText}>
          <Text style={styles.title}>Today's Schedule</Text>
          <Text style={styles.subtitle}>
            {user?.full_name ? `${user.full_name} · ` : ''}
            {todayDate || 'My Timetable'}
          </Text>
        </View>
        <TouchableOpacity onPress={logout} accessibilityRole="button" accessibilityLabel="Sign out">
          <Ionicons name="log-out-outline" size={24} color="#94A3B8" />
        </TouchableOpacity>
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
          data={sessions}
          keyExtractor={(item) => item.timetable_id.toString()}
          renderItem={renderSessionCard}
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
              <Ionicons name="calendar-outline" size={56} color="#475569" />
              <Text style={styles.emptyTitle}>No Sessions Today</Text>
              <Text style={styles.emptyText}>You have no scheduled teaching periods for today.</Text>
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
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  headerText: {
    flex: 1,
    paddingRight: 12,
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
  card: {
    backgroundColor: '#1E293B',
    borderRadius: 16,
    padding: 18,
    marginBottom: 14,
    borderWidth: 1,
    borderColor: '#334155',
  },
  cardHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 10,
  },
  timeWrapper: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  timeText: {
    color: '#CBD5E1',
    fontSize: 13,
    fontWeight: '600',
    marginLeft: 6,
  },
  badge: {
    paddingHorizontal: 10,
    paddingVertical: 4,
    borderRadius: 12,
    flexDirection: 'row',
    alignItems: 'center',
  },
  inProgressBadge: {
    backgroundColor: 'rgba(22, 163, 74, 0.2)',
    borderWidth: 1,
    borderColor: '#16A34A',
  },
  inProgressBadgeText: {
    color: '#4ADE80',
    fontSize: 12,
    fontWeight: '700',
  },
  liveDot: {
    width: 6,
    height: 6,
    borderRadius: 3,
    backgroundColor: '#4ADE80',
    marginRight: 6,
  },
  upcomingBadge: {
    backgroundColor: 'rgba(37, 99, 235, 0.2)',
    borderWidth: 1,
    borderColor: '#2563EB',
  },
  upcomingBadgeText: {
    color: '#60A5FA',
    fontSize: 12,
    fontWeight: '700',
  },
  endedBadge: {
    backgroundColor: 'rgba(71, 85, 105, 0.3)',
  },
  endedBadgeText: {
    color: '#94A3B8',
    fontSize: 12,
    fontWeight: '600',
  },
  subjectText: {
    fontSize: 18,
    fontWeight: '700',
    color: '#FFFFFF',
    marginBottom: 10,
  },
  detailsRow: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 10,
  },
  detailItem: {
    flexDirection: 'row',
    alignItems: 'center',
    marginRight: 20,
  },
  detailText: {
    color: '#94A3B8',
    fontSize: 14,
    marginLeft: 6,
  },
  cardFooter: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingTop: 10,
    borderTopWidth: 1,
    borderTopColor: '#334155',
    marginTop: 4,
  },
  footerLabel: {
    color: '#64748B',
    fontSize: 13,
    marginRight: 8,
  },
  attBadge: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 8,
    paddingVertical: 3,
    borderRadius: 6,
  },
  presentAtt: {
    backgroundColor: 'rgba(34, 197, 94, 0.15)',
  },
  presentAttText: {
    color: '#4ADE80',
    fontSize: 13,
    fontWeight: '600',
    marginLeft: 4,
  },
  lateAtt: {
    backgroundColor: 'rgba(245, 158, 11, 0.15)',
  },
  lateAttText: {
    color: '#FBBF24',
    fontSize: 13,
    fontWeight: '600',
    marginLeft: 4,
  },
  emptyContainer: {
    alignItems: 'center',
    justifyContent: 'center',
    padding: 40,
    marginTop: 40,
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
