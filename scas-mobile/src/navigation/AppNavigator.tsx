import React, { useContext } from 'react';
import { View, ActivityIndicator, StyleSheet } from 'react-native';
import { NavigationContainer } from '@react-navigation/native';
import { createBottomTabNavigator } from '@react-navigation/bottom-tabs';
import { Ionicons } from '@expo/vector-icons';

import { AuthContext } from '../context/AuthContext';
import { LoginScreen } from '../screens/LoginScreen';
import { TimetableScreen } from '../screens/TimetableScreen';
import { ScanQrScreen } from '../screens/ScanQrScreen';
import { HistoryScreen } from '../screens/HistoryScreen';
import { ProfileScreen } from '../screens/ProfileScreen';

const Tab = createBottomTabNavigator();

export const AppNavigator = () => {
  const { token, isLoading } = useContext(AuthContext);

  if (isLoading) {
    return (
      <View style={styles.loadingContainer}>
        <ActivityIndicator size="large" color="#2563EB" />
      </View>
    );
  }

  if (!token) {
    return <LoginScreen />;
  }

  return (
    <NavigationContainer>
      <Tab.Navigator
        screenOptions={{
          headerShown: false,
          tabBarActiveTintColor: '#60A5FA',
          tabBarInactiveTintColor: '#64748B',
          tabBarStyle: {
            backgroundColor: '#1E293B',
            borderTopColor: '#334155',
            height: 60,
            paddingBottom: 8,
            paddingTop: 6,
          },
        }}
      >
        <Tab.Screen
          name="Timetable"
          component={TimetableScreen}
          options={{
            tabBarLabel: 'Timetable',
            tabBarIcon: ({ color, size }) => (
              <Ionicons name="calendar-outline" size={size} color={color} />
            ),
          }}
        />

        <Tab.Screen
          name="ScanQR"
          component={ScanQrScreen}
          options={{
            tabBarLabel: 'Scan QR',
            tabBarIcon: ({ color, size }) => (
              <View style={styles.scanTabIcon}>
                <Ionicons name="qr-code-sharp" size={24} color="#FFFFFF" />
              </View>
            ),
          }}
        />

        <Tab.Screen
          name="History"
          component={HistoryScreen}
          options={{
            tabBarLabel: 'History',
            tabBarIcon: ({ color, size }) => (
              <Ionicons name="time-outline" size={size} color={color} />
            ),
          }}
        />

        <Tab.Screen
          name="Profile"
          component={ProfileScreen}
          options={{
            tabBarLabel: 'Profile',
            tabBarIcon: ({ color, size }) => (
              <Ionicons name="person-outline" size={size} color={color} />
            ),
          }}
        />
      </Tab.Navigator>
    </NavigationContainer>
  );
};

const styles = StyleSheet.create({
  loadingContainer: {
    flex: 1,
    backgroundColor: '#0F172A',
    justifyContent: 'center',
    alignItems: 'center',
  },
  scanTabIcon: {
    width: 44,
    height: 44,
    borderRadius: 22,
    backgroundColor: '#2563EB',
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: 8,
    elevation: 4,
    shadowColor: '#2563EB',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.3,
    shadowRadius: 8,
  },
});
