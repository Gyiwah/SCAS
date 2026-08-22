import React from 'react';
import { View, ActivityIndicator, StyleSheet } from 'react-native';
import { NavigationContainer, DarkTheme } from '@react-navigation/native';
import { createBottomTabNavigator } from '@react-navigation/bottom-tabs';
import { createNativeStackNavigator } from '@react-navigation/native-stack';
import { Ionicons } from '@expo/vector-icons';

import { useAuth } from '../context/AuthContext';
import { PRIV } from '../roles';
import { colors } from '../theme';

import { LoginScreen } from '../screens/LoginScreen';
import { DashboardScreen } from '../screens/DashboardScreen';
import { ScanQrScreen } from '../screens/ScanQrScreen';
import { MyTimetableScreen } from '../screens/MyTimetableScreen';
import { AttendanceScreen } from '../screens/AttendanceScreen';
import { LeaveScreen } from '../screens/LeaveScreen';
import { NotificationsScreen } from '../screens/NotificationsScreen';
import { AccountScreen } from '../screens/AccountScreen';
import { MoreScreen } from '../screens/MoreScreen';
import { BoardScreen } from '../screens/BoardScreen';
import { QrCodesScreen } from '../screens/QrCodesScreen';
import { ApprovalsScreen } from '../screens/ApprovalsScreen';
import { TeachersScreen } from '../screens/TeachersScreen';
import { ReportsScreen } from '../screens/ReportsScreen';
import { AdminTimetableScreen } from '../screens/AdminTimetableScreen';
import { UsersScreen } from '../screens/UsersScreen';
import { AuditScreen } from '../screens/AuditScreen';
import { SecurityScreen } from '../screens/SecurityScreen';
import { DbaScreen } from '../screens/DbaScreen';

const Tab = createBottomTabNavigator();
const Stack = createNativeStackNavigator();

const navTheme = {
  ...DarkTheme,
  colors: {
    ...DarkTheme.colors,
    primary: colors.primary,
    background: colors.background,
    card: colors.surface,
    text: colors.text,
    border: colors.border,
  },
};

function Tabs() {
  const { user } = useAuth();
  const isTeacher = Boolean(user?.teacher_id);
  const priv = user?.privilege_level ?? 0;

  return (
    <Tab.Navigator
      screenOptions={{
        headerShown: false,
        tabBarActiveTintColor: colors.primaryLight,
        tabBarInactiveTintColor: colors.textFaint,
        tabBarStyle: {
          backgroundColor: colors.surface,
          borderTopColor: colors.border,
        },
        tabBarLabelStyle: { fontSize: 12, fontWeight: '600' },
      }}
    >
      <Tab.Screen
        name="Home"
        component={DashboardScreen}
        options={{
          tabBarIcon: ({ color, size }) => <Ionicons name="grid-outline" size={size} color={color} />,
        }}
      />
      {isTeacher ? (
        <Tab.Screen
          name="Check in"
          component={ScanQrScreen}
          options={{
            tabBarIcon: ({ color, size }) => <Ionicons name="qr-code-outline" size={size} color={color} />,
          }}
        />
      ) : null}
      {priv >= PRIV.HEADTEACHER ? (
        <Tab.Screen
          name="Live board"
          component={BoardScreen}
          options={{
            tabBarIcon: ({ color, size }) => <Ionicons name="pulse-outline" size={size} color={color} />,
          }}
        />
      ) : null}
      <Tab.Screen
        name="More"
        component={MoreScreen}
        options={{
          tabBarIcon: ({ color, size }) => <Ionicons name="menu-outline" size={size} color={color} />,
        }}
      />
    </Tab.Navigator>
  );
}

function SignedIn() {
  return (
    <Stack.Navigator
      screenOptions={{
        headerStyle: { backgroundColor: colors.surface },
        headerTintColor: colors.text,
        headerTitle: '',
        headerShadowVisible: false,
        contentStyle: { backgroundColor: colors.background },
      }}
    >
      <Stack.Screen name="Tabs" component={Tabs} options={{ headerShown: false }} />
      <Stack.Screen name="Checkin" component={ScanQrScreen} options={{ title: 'Check in' }} />
      <Stack.Screen name="MyTimetable" component={MyTimetableScreen} options={{ title: 'My timetable' }} />
      <Stack.Screen name="Attendance" component={AttendanceScreen} options={{ title: 'My attendance' }} />
      <Stack.Screen name="Leave" component={LeaveScreen} options={{ title: 'My leave' }} />
      <Stack.Screen name="Notifications" component={NotificationsScreen} options={{ title: 'Notifications' }} />
      <Stack.Screen name="Account" component={AccountScreen} options={{ title: 'My account' }} />
      <Stack.Screen name="Board" component={BoardScreen} options={{ title: 'Live board' }} />
      <Stack.Screen name="QrCodes" component={QrCodesScreen} options={{ title: 'Session codes' }} />
      <Stack.Screen name="Approvals" component={ApprovalsScreen} options={{ title: 'Leave approvals' }} />
      <Stack.Screen name="Teachers" component={TeachersScreen} options={{ title: 'Staff directory' }} />
      <Stack.Screen name="Reports" component={ReportsScreen} options={{ title: 'Reports' }} />
      <Stack.Screen name="AdminTimetable" component={AdminTimetableScreen} options={{ title: 'Timetable' }} />
      <Stack.Screen name="Users" component={UsersScreen} options={{ title: 'User accounts' }} />
      <Stack.Screen name="Audit" component={AuditScreen} options={{ title: 'Audit trail' }} />
      <Stack.Screen name="Security" component={SecurityScreen} options={{ title: 'Security' }} />
      <Stack.Screen name="Dba" component={DbaScreen} options={{ title: 'DBA console' }} />
    </Stack.Navigator>
  );
}

export default function RootNavigator() {
  const { token, isLoading } = useAuth();

  if (isLoading) {
    return (
      <View style={styles.splash}>
        <ActivityIndicator size="large" color={colors.primary} />
      </View>
    );
  }

  return (
    <NavigationContainer theme={navTheme}>
      {token ? <SignedIn /> : <LoginScreen />}
    </NavigationContainer>
  );
}

const styles = StyleSheet.create({
  splash: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.background,
  },
});
