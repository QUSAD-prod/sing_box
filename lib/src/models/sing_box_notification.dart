/// Модель уведомления от sing-box
class SingBoxNotification {
  /// Идентификатор уведомления
  final String identifier;

  /// Тип уведомления (название)
  final String typeName;

  /// ID типа уведомления
  final int typeId;

  /// Заголовок уведомления
  final String title;

  /// Подзаголовок уведомления
  final String subtitle;

  /// Текст уведомления
  final String body;

  /// URL для открытия при нажатии на уведомление
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

  /// Создать из Map (из Method Channel)
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

  /// Преобразовать в Map (для Method Channel)
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

