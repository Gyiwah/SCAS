import React from 'react';
import { StyleSheet, Text, TouchableOpacity, View } from 'react-native';
import { useNavigation } from '@react-navigation/native';
import { Ionicons } from '@expo/vector-icons';
import { Screen } from '../components/Screen';
import { useAuth } from '../context/AuthContext';
import { visibleMenu } from '../roles';
import { colors } from '../theme';

export function MoreScreen() {
  const { user, logout } = useAuth();
  const nav = useNavigation<any>();
  const items = visibleMenu(user?.privilege_level ?? 0, Boolean(user?.teacher_id)).filter(
    (i) => i.key !== 'dashboard'
  );
  const groups = [...new Set(items.map((i) => i.group))];

  return (
    <Screen title="More" subtitle={`${user?.school_name || 'SCAS'} · ${user?.role_name || ''}`}>
      {groups.map((group) => (
        <View key={group} style={styles.group}>
          <Text style={styles.groupLabel}>{group}</Text>
          {items
            .filter((i) => i.group === group)
            .map((item) => (
              <TouchableOpacity
                key={item.key}
                style={styles.row}
                onPress={() => (nav.getParent() ?? nav).navigate(item.route)}
              >
                <Text style={styles.rowLabel}>{item.label}</Text>
                <Ionicons name="chevron-forward" size={18} color={colors.textFaint} />
              </TouchableOpacity>
            ))}
        </View>
      ))}
      <TouchableOpacity style={styles.signout} onPress={() => logout()}>
        <Text style={styles.signoutText}>Sign out</Text>
      </TouchableOpacity>
    </Screen>
  );
}

const styles = StyleSheet.create({
  group: {
    backgroundColor: colors.surface,
    borderColor: colors.border,
    borderWidth: 1,
    borderRadius: 16,
    marginBottom: 16,
    overflow: 'hidden',
  },
  groupLabel: {
    color: colors.textFaint,
    fontSize: 11,
    fontWeight: '700',
    letterSpacing: 0.8,
    textTransform: 'uppercase',
    paddingHorizontal: 16,
    paddingTop: 12,
    paddingBottom: 6,
  },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 16,
    paddingVertical: 14,
    borderTopWidth: 1,
    borderTopColor: colors.border,
  },
  rowLabel: { color: colors.text, fontSize: 15, fontWeight: '600' },
  signout: {
    marginTop: 8,
    borderWidth: 1,
    borderColor: colors.danger,
    backgroundColor: colors.dangerBg,
    borderRadius: 12,
    height: 50,
    alignItems: 'center',
    justifyContent: 'center',
  },
  signoutText: { color: colors.danger, fontWeight: '700', fontSize: 16 },
});
