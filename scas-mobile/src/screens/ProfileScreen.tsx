import React, { useContext } from 'react';
import {
  StyleSheet,
  Text,
  View,
  TouchableOpacity,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import { AuthContext } from '../context/AuthContext';

export const ProfileScreen = () => {
  const { user, logout } = useContext(AuthContext);

  return (
    <SafeAreaView style={styles.container}>
      <View style={styles.header}>
        <Text style={styles.title}>Account Profile</Text>
      </View>

      <View style={styles.content}>
        {/* User Card */}
        <View style={styles.profileCard}>
          <View style={styles.avatar}>
            <Ionicons name="person" size={40} color="#2563EB" />
          </View>

          <Text style={styles.userName}>{user?.full_name || 'Teacher'}</Text>
          <Text style={styles.userRole}>{user?.role_name} • {user?.department || 'Staff'}</Text>
          <Text style={styles.schoolName}>{user?.school_name || 'Winneba Senior High School'}</Text>
        </View>

        {/* Info Rows */}
        <View style={styles.infoSection}>
          <View style={styles.infoRow}>
            <Ionicons name="at-outline" size={20} color="#64748B" />
            <Text style={styles.infoLabel}>Username</Text>
            <Text style={styles.infoValue}>{user?.username}</Text>
          </View>

          <View style={styles.infoRow}>
            <Ionicons name="shield-checkmark-outline" size={20} color="#64748B" />
            <Text style={styles.infoLabel}>Privilege Level</Text>
            <Text style={styles.infoValue}>{user?.privilege_level}</Text>
          </View>

          <View style={styles.infoRow}>
            <Ionicons name="school-outline" size={20} color="#64748B" />
            <Text style={styles.infoLabel}>School ID</Text>
            <Text style={styles.infoValue}>{user?.school_id ?? 'N/A'}</Text>
          </View>
        </View>

        {/* Sign Out Button */}
        <TouchableOpacity style={styles.logoutBtn} onPress={logout}>
          <Ionicons name="log-out-outline" size={20} color="#EF4444" />
          <Text style={styles.logoutText}>Sign Out</Text>
        </TouchableOpacity>
      </View>
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
  content: {
    padding: 20,
  },
  profileCard: {
    backgroundColor: '#1E293B',
    borderRadius: 20,
    padding: 24,
    alignItems: 'center',
    marginBottom: 20,
    borderWidth: 1,
    borderColor: '#334155',
  },
  avatar: {
    width: 80,
    height: 80,
    borderRadius: 40,
    backgroundColor: 'rgba(37, 99, 235, 0.15)',
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: 16,
    borderWidth: 2,
    borderColor: '#2563EB',
  },
  userName: {
    fontSize: 20,
    fontWeight: '700',
    color: '#FFFFFF',
    marginBottom: 4,
  },
  userRole: {
    fontSize: 14,
    color: '#60A5FA',
    fontWeight: '600',
    marginBottom: 6,
  },
  schoolName: {
    fontSize: 13,
    color: '#94A3B8',
  },
  infoSection: {
    backgroundColor: '#1E293B',
    borderRadius: 16,
    paddingVertical: 6,
    paddingHorizontal: 16,
    marginBottom: 24,
    borderWidth: 1,
    borderColor: '#334155',
  },
  infoRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 14,
    borderBottomWidth: 1,
    borderBottomColor: '#334155',
  },
  infoLabel: {
    color: '#94A3B8',
    fontSize: 14,
    marginLeft: 12,
    flex: 1,
  },
  infoValue: {
    color: '#FFFFFF',
    fontSize: 14,
    fontWeight: '600',
  },
  logoutBtn: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: 'rgba(239, 68, 68, 0.15)',
    borderWidth: 1,
    borderColor: '#EF4444',
    borderRadius: 12,
    height: 50,
  },
  logoutText: {
    color: '#EF4444',
    fontSize: 16,
    fontWeight: '700',
    marginLeft: 8,
  },
});
