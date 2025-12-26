/// Notification model from sing-box
class SingBoxNotification {
  /// Notification identifier
  final String identifier;

  /// Notification type (name)
  final String typeName;

  /// Notification type ID
  final int typeId;

  /// Notification title
  final String title;

  /// Notification subtitle
  final String subtitle;

  /// Notification body
  final String body;

  /// URL to open when notification is tapped
  final String? openUrl;

  const SingBoxNotification({
    required this.identifier,
    required this.typeName,
    required this.typeId,
    required this.title,
    required this.subtitle,
    required this.body,
    this.openUrl,
  });

  /// Create from Map (from Method Channel)
  factory SingBoxNotification.fromMap(Map<dynamic, dynamic> map) {
    return SingBoxNotification(
      identifier: map['identifier'] as String? ?? '',
      typeName: map['typeName'] as String? ?? '',
      typeId: map['typeId'] as int? ?? 0,
      title: map['title'] as String? ?? '',
      subtitle: map['subtitle'] as String? ?? '',
      body: map['body'] as String? ?? '',
      openUrl: map['openUrl'] as String?,
    );
  }

  /// Convert to Map (for Method Channel)
  Map<String, dynamic> toMap() {
    return {
      'identifier': identifier,
      'typeName': typeName,
      'typeId': typeId,
      'title': title,
      'subtitle': subtitle,
      'body': body,
      'openUrl': openUrl,
    };
  }

  @override
  String toString() {
    return 'SingBoxNotification(identifier: $identifier, typeName: $typeName, typeId: $typeId, title: $title, subtitle: $subtitle, body: $body, openUrl: $openUrl)';
  }
}
