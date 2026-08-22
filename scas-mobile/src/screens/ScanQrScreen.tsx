import React, { useState } from 'react';
import {
  StyleSheet,
  Text,
  View,
  TouchableOpacity,
  TextInput,
  ActivityIndicator,
  Modal,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useIsFocused } from '@react-navigation/native';
import { CameraView, useCameraPermissions } from 'expo-camera';
import * as Haptics from 'expo-haptics';
import { Ionicons } from '@expo/vector-icons';
import { apiClient } from '../api/client';

export const ScanQrScreen = () => {
  const isFocused = useIsFocused();
  const [permission, requestPermission] = useCameraPermissions();
  const [scanned, setScanned] = useState(false);
  const [manualCode, setManualCode] = useState('');
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [useManualMode, setUseManualMode] = useState(false);

  // Result modal state
  const [resultModalVisible, setResultModalVisible] = useState(false);
  const [checkInResult, setCheckInResult] = useState<{
    ok: boolean;
    status?: string;
    message?: string;
  } | null>(null);

  const processCode = async (rawCode: string) => {
    if (isSubmitting || scanned) return;

    setScanned(true);
    setIsSubmitting(true);

    // Trigger haptic feedback on scan
    try {
      await Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
    } catch (e) {
      // Haptics fallback on web or unsupported devices
    }

    try {
      const response = await apiClient.post('/checkin.php', { code: rawCode });

      if (response.data?.status === 'success') {
        const data = response.data.data;
        setCheckInResult({
          ok: true,
          status: data.attendance_status ?? data.status,
          message: data.message,
        });
      } else {
        setCheckInResult({
          ok: false,
          message: response.data?.message || 'Check-in failed.',
        });
      }
    } catch (error: any) {
      const errMsg =
        error.response?.data?.message || error.message || 'Failed to communicate with SCAS server.';
      setCheckInResult({
        ok: false,
        message: errMsg,
      });
    } finally {
      setIsSubmitting(false);
      setResultModalVisible(true);
    }
  };

  const handleBarCodeScanned = ({ data }: { data: string }) => {
    processCode(data);
  };

  const handleManualSubmit = () => {
    if (!manualCode.trim()) return;
    processCode(manualCode.trim());
  };

  const resetScan = () => {
    setResultModalVisible(false);
    setCheckInResult(null);
    setManualCode('');
    setScanned(false);
  };

  if (!permission) {
    // Camera permissions are still loading
    return (
      <View style={styles.centerContainer}>
        <ActivityIndicator size="large" color="#2563EB" />
      </View>
    );
  }

  if (!permission.granted && !useManualMode) {
    // Camera permissions are not granted yet
    return (
      <SafeAreaView style={styles.container}>
        <View style={styles.permissionBox}>
          <Ionicons name="camera-outline" size={64} color="#60A5FA" />
          <Text style={styles.permissionTitle}>Camera Permission Required</Text>
          <Text style={styles.permissionText}>
            SCAS requires camera access to scan classroom QR session codes.
          </Text>
          
          <TouchableOpacity style={styles.primaryBtn} onPress={requestPermission}>
            <Text style={styles.btnText}>Grant Camera Permission</Text>
          </TouchableOpacity>

          <TouchableOpacity style={styles.secondaryBtn} onPress={() => setUseManualMode(true)}>
            <Text style={styles.secondaryBtnText}>Enter 32-Character Code Manually</Text>
          </TouchableOpacity>
        </View>
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView style={styles.container}>
      {useManualMode ? (
        // Manual Code Entry View
        <View style={styles.manualContainer}>
          <View style={styles.headerRow}>
            <Text style={styles.headerTitle}>Manual Code Entry</Text>
            <TouchableOpacity onPress={() => setUseManualMode(false)}>
              <Ionicons name="camera" size={24} color="#60A5FA" />
            </TouchableOpacity>
          </View>

          <Text style={styles.manualHint}>
            Type or paste the 32-character session code shown below the classroom QR code.
          </Text>

          <TextInput
            style={styles.codeInput}
            placeholder="e.g. a1b2c3d4e5f67890..."
            placeholderTextColor="#64748B"
            value={manualCode}
            onChangeText={setManualCode}
            autoCapitalize="none"
            autoCorrect={false}
          />

          <TouchableOpacity
            style={[styles.primaryBtn, isSubmitting && styles.btnDisabled]}
            onPress={handleManualSubmit}
            disabled={isSubmitting || !manualCode.trim()}
          >
            {isSubmitting ? (
              <ActivityIndicator color="#FFFFFF" />
            ) : (
              <Text style={styles.btnText}>Submit Check-In</Text>
            )}
          </TouchableOpacity>
        </View>
      ) : (
        // Camera Viewfinder View
        <View style={styles.cameraContainer}>
          {isFocused ? (
            <CameraView
              style={StyleSheet.absoluteFillObject}
              facing="back"
              barcodeScannerSettings={{ barcodeTypes: ['qr'] }}
              onBarcodeScanned={scanned ? undefined : handleBarCodeScanned}
            />
          ) : null}

          {/* Overlay Target Frame */}
          <View style={styles.overlayContainer}>
            <Text style={styles.scanInstruction}>
              Align classroom QR code within the frame
            </Text>

            <View style={styles.targetFrame}>
              <View style={[styles.corner, styles.topLeft]} />
              <View style={[styles.corner, styles.topRight]} />
              <View style={[styles.corner, styles.bottomLeft]} />
              <View style={[styles.corner, styles.bottomRight]} />
            </View>

            <TouchableOpacity
              style={styles.toggleManualBtn}
              onPress={() => setUseManualMode(true)}
            >
              <Ionicons name="keypad-outline" size={20} color="#FFFFFF" />
              <Text style={styles.toggleManualText}>Type code manually</Text>
            </TouchableOpacity>
          </View>
        </View>
      )}

      {/* Result Modal */}
      <Modal
        visible={resultModalVisible}
        transparent
        animationType="slide"
        onRequestClose={resetScan}
      >
        <View style={styles.modalBackdrop}>
          <View style={styles.modalContent}>
            {checkInResult?.ok ? (
              <>
                <View style={[styles.iconCircle, styles.successCircle]}>
                  <Ionicons name="checkmark-sharp" size={48} color="#FFFFFF" />
                </View>
                <Text style={styles.modalTitle}>
                  Marked {checkInResult.status}
                </Text>
                <Text style={styles.modalMessage}>{checkInResult.message}</Text>
              </>
            ) : (
              <>
                <View style={[styles.iconCircle, styles.errorCircle]}>
                  <Ionicons name="close-sharp" size={48} color="#FFFFFF" />
                </View>
                <Text style={styles.modalTitle}>Check-In Failed</Text>
                <Text style={styles.modalMessage}>{checkInResult?.message}</Text>
              </>
            )}

            <TouchableOpacity style={styles.modalBtn} onPress={resetScan}>
              <Text style={styles.modalBtnText}>Scan Next Code</Text>
            </TouchableOpacity>
          </View>
        </View>
      </Modal>
    </SafeAreaView>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#0F172A',
  },
  centerContainer: {
    flex: 1,
    backgroundColor: '#0F172A',
    justifyContent: 'center',
    alignItems: 'center',
  },
  permissionBox: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    padding: 32,
  },
  permissionTitle: {
    fontSize: 22,
    fontWeight: '700',
    color: '#FFFFFF',
    marginTop: 20,
    marginBottom: 10,
    textAlign: 'center',
  },
  permissionText: {
    fontSize: 15,
    color: '#94A3B8',
    textAlign: 'center',
    marginBottom: 30,
    lineHeight: 22,
  },
  primaryBtn: {
    backgroundColor: '#2563EB',
    width: '100%',
    height: 52,
    borderRadius: 12,
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: 14,
  },
  btnText: {
    color: '#FFFFFF',
    fontSize: 16,
    fontWeight: '700',
  },
  btnDisabled: {
    opacity: 0.6,
  },
  secondaryBtn: {
    padding: 14,
  },
  secondaryBtnText: {
    color: '#60A5FA',
    fontSize: 15,
    fontWeight: '600',
  },
  cameraContainer: {
    flex: 1,
  },
  overlayContainer: {
    flex: 1,
    backgroundColor: 'rgba(15, 23, 42, 0.6)',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingVertical: 50,
  },
  scanInstruction: {
    color: '#FFFFFF',
    fontSize: 16,
    fontWeight: '600',
    backgroundColor: 'rgba(0, 0, 0, 0.6)',
    paddingHorizontal: 20,
    paddingVertical: 10,
    borderRadius: 20,
    overflow: 'hidden',
  },
  targetFrame: {
    width: 250,
    height: 250,
    position: 'relative',
  },
  corner: {
    position: 'absolute',
    width: 32,
    height: 32,
    borderColor: '#60A5FA',
  },
  topLeft: {
    top: 0,
    left: 0,
    borderTopWidth: 4,
    borderLeftWidth: 4,
  },
  topRight: {
    top: 0,
    right: 0,
    borderTopWidth: 4,
    borderRightWidth: 4,
  },
  bottomLeft: {
    bottom: 0,
    left: 0,
    borderBottomWidth: 4,
    borderLeftWidth: 4,
  },
  bottomRight: {
    bottom: 0,
    right: 0,
    borderBottomWidth: 4,
    borderRightWidth: 4,
  },
  toggleManualBtn: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#1E293B',
    paddingHorizontal: 20,
    paddingVertical: 12,
    borderRadius: 25,
    borderWidth: 1,
    borderColor: '#334155',
  },
  toggleManualText: {
    color: '#FFFFFF',
    fontWeight: '600',
    marginLeft: 8,
  },
  manualContainer: {
    flex: 1,
    padding: 24,
  },
  headerRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 16,
  },
  headerTitle: {
    fontSize: 22,
    fontWeight: '700',
    color: '#FFFFFF',
  },
  manualHint: {
    fontSize: 14,
    color: '#94A3B8',
    marginBottom: 24,
    lineHeight: 20,
  },
  codeInput: {
    backgroundColor: '#1E293B',
    borderRadius: 12,
    borderWidth: 1,
    borderColor: '#334155',
    color: '#FFFFFF',
    fontSize: 16,
    paddingHorizontal: 16,
    paddingVertical: 14,
    marginBottom: 20,
  },
  modalBackdrop: {
    flex: 1,
    backgroundColor: 'rgba(0, 0, 0, 0.75)',
    justifyContent: 'center',
    alignItems: 'center',
    padding: 24,
  },
  modalContent: {
    backgroundColor: '#1E293B',
    borderRadius: 24,
    padding: 28,
    width: '100%',
    alignItems: 'center',
    borderWidth: 1,
    borderColor: '#334155',
  },
  iconCircle: {
    width: 80,
    height: 80,
    borderRadius: 40,
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: 20,
  },
  successCircle: {
    backgroundColor: '#16A34A',
  },
  errorCircle: {
    backgroundColor: '#DC2626',
  },
  modalTitle: {
    fontSize: 22,
    fontWeight: '700',
    color: '#FFFFFF',
    marginBottom: 10,
    textAlign: 'center',
  },
  modalMessage: {
    fontSize: 15,
    color: '#CBD5E1',
    textAlign: 'center',
    marginBottom: 24,
    lineHeight: 22,
  },
  modalBtn: {
    backgroundColor: '#2563EB',
    borderRadius: 12,
    paddingVertical: 14,
    paddingHorizontal: 40,
    width: '100%',
    alignItems: 'center',
  },
  modalBtnText: {
    color: '#FFFFFF',
    fontSize: 16,
    fontWeight: '700',
  },
});
