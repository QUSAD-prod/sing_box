/// A notification emitted by the sing-box core.
///
/// The core sends notifications for events the user should know about, for
/// example when a remote rule-set fails to update. Listen with
/// `SingBox.watchNotifications()`.
class SingBoxNotification {
  /// Creates a notification.
  const SingBoxNotification({
    required this.identifier,
    required this.typeName,
    required this.typeId,
    required this.title,
    required this.subtitle,
    required this.body,
    this.openUrl,
  });

  /// Creates a notification from a map (from the platform channel).
  factory SingBoxNotification.fromMap(Map<dynamic, dynamic> map) {
    final url = map['openUrl'] as String?;
    return SingBoxNotification(
      identifier: map['identifier'] as String? ?? '',
      typeName: map['typeName'] as String? ?? '',
      typeId: (map['typeId'] as num?)?.toInt() ?? 0,
      title: map['title'] as String? ?? '',
      subtitle: map['subtitle'] as String? ?? '',
      body: map['body'] as String? ?? '',
      openUrl: url == null || url.isEmpty ? null : url,
    );
  }

  /// Notification identifier.
  final String identifier;

  /// Notification type name.
  final String typeName;

  /// Notification type id.
  final int typeId;

  /// Title.
  final String title;

  /// Subtitle.
  final String subtitle;

  /// Body text.
  final String body;

  /// URL to open when the notification is tapped.
  final String? openUrl;

  /// Converts the notification to a map (for the platform channel).
  Map<String, dynamic> toMap() => {
    'identifier': identifier,
    'typeName': typeName,
    'typeId': typeId,
    'title': title,
    'subtitle': subtitle,
    'body': body,
    'openUrl': openUrl,
  };

  @override
  String toString() =>
      'SingBoxNotification(identifier: $identifier, typeName: $typeName, '
      'typeId: $typeId, title: $title, subtitle: $subtitle, body: $body, '
      'openUrl: $openUrl)';
}
