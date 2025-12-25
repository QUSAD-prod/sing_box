/// VPN connection status
enum SingBoxConnectionStatus {
  /// Not connected
  disconnected,
  /// Connecting in progress
  connecting,
  /// Connected
  connected,
  /// Disconnecting in progress
  disconnecting,
  /// Disconnected by user
  disconnectedByUser,
  /// Connection lost with server
  connectionLost,
  /// Connection error
  error,
}

/// Extension for converting status to string
extension SingBoxConnectionStatusExtension on SingBoxConnectionStatus {
  String get name {
    switch (this) {
      case SingBoxConnectionStatus.disconnected:
        return 'disconnected';
      case SingBoxConnectionStatus.connecting:
        return 'connecting';
      case SingBoxConnectionStatus.connected:
        return 'connected';
      case SingBoxConnectionStatus.disconnecting:
        return 'disconnecting';
      case SingBoxConnectionStatus.disconnectedByUser:
        return 'disconnectedByUser';
      case SingBoxConnectionStatus.connectionLost:
        return 'connectionLost';
      case SingBoxConnectionStatus.error:
        return 'error';
    }
  }

  static SingBoxConnectionStatus fromString(String value) {
    switch (value) {
      case 'disconnected':
        return SingBoxConnectionStatus.disconnected;
      case 'connecting':
        return SingBoxConnectionStatus.connecting;
      case 'connected':
        return SingBoxConnectionStatus.connected;
      case 'disconnecting':
        return SingBoxConnectionStatus.disconnecting;
      case 'disconnectedByUser':
        return SingBoxConnectionStatus.disconnectedByUser;
      case 'connectionLost':
        return SingBoxConnectionStatus.connectionLost;
      case 'error':
        return SingBoxConnectionStatus.error;
      default:
        return SingBoxConnectionStatus.disconnected;
    }
  }
}
