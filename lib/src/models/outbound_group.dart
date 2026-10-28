/// An outbound (proxy server or built-in outbound) with its latest URL test
/// result.
class SingBoxOutboundItem {
  /// Creates an outbound item.
  const SingBoxOutboundItem({
    required this.tag,
    required this.type,
    this.urlTestTime,
    this.urlTestDelay,
  });

  /// Parses an item of the `sing_box/groups` or `sing_box/outbounds` channel.
  factory SingBoxOutboundItem.fromMap(Map<dynamic, dynamic> map) {
    final time = (map['urlTestTime'] as num?)?.toInt() ?? 0;
    final delay = (map['urlTestDelay'] as num?)?.toInt() ?? 0;
    return SingBoxOutboundItem(
      tag: map['tag'] as String? ?? '',
      type: map['type'] as String? ?? '',
      urlTestTime: time > 0 ? DateTime.fromMillisecondsSinceEpoch(time) : null,
      urlTestDelay: delay > 0 ? delay : null,
    );
  }

  /// Outbound tag from the configuration.
  final String tag;

  /// Outbound type, e.g. `vless`, `shadowsocks`, `direct`, `selector`.
  final String type;

  /// When the outbound was last URL-tested, `null` if never.
  final DateTime? urlTestTime;

  /// Latency of the last URL test in milliseconds, `null` if it was never
  /// tested or the test failed.
  final int? urlTestDelay;

  /// Whether the outbound was tested and the test failed.
  bool get urlTestFailed => urlTestTime != null && urlTestDelay == null;

  /// Serializes the item using the wire format.
  Map<String, dynamic> toMap() => {
    'tag': tag,
    'type': type,
    'urlTestTime': urlTestTime?.millisecondsSinceEpoch ?? 0,
    'urlTestDelay': urlTestDelay ?? 0,
  };

  @override
  bool operator ==(Object other) =>
      other is SingBoxOutboundItem &&
      other.tag == tag &&
      other.type == type &&
      other.urlTestTime == urlTestTime &&
      other.urlTestDelay == urlTestDelay;

  @override
  int get hashCode => Object.hash(tag, type, urlTestTime, urlTestDelay);

  @override
  String toString() =>
      'SingBoxOutboundItem($tag, $type, delay: ${urlTestDelay ?? '-'} ms)';
}

/// A `selector` or `urltest` outbound group of the running configuration.
class SingBoxOutboundGroup {
  /// Creates a group.
  const SingBoxOutboundGroup({
    required this.tag,
    required this.type,
    required this.selectable,
    required this.selected,
    required this.items,
    this.isExpand = false,
  });

  /// Parses a group of the `sing_box/groups` channel.
  factory SingBoxOutboundGroup.fromMap(Map<dynamic, dynamic> map) {
    return SingBoxOutboundGroup(
      tag: map['tag'] as String? ?? '',
      type: map['type'] as String? ?? '',
      selectable: map['selectable'] as bool? ?? false,
      selected: map['selected'] as String? ?? '',
      isExpand: map['isExpand'] as bool? ?? false,
      items: (map['items'] as List<dynamic>? ?? const [])
          .whereType<Map<dynamic, dynamic>>()
          .map(SingBoxOutboundItem.fromMap)
          .toList(growable: false),
    );
  }

  /// Group tag, e.g. `proxy`.
  final String tag;

  /// Group type: `selector` or `urltest`.
  final String type;

  /// Whether the selected member can be changed with
  /// `SingBox.selectOutbound()` (only `selector` groups).
  final bool selectable;

  /// Tag of the currently selected member.
  final String selected;

  /// UI hint persisted by sing-box (`SingBox.setGroupExpand()`).
  final bool isExpand;

  /// Group members.
  final List<SingBoxOutboundItem> items;

  /// The currently selected member, if it is part of [items].
  SingBoxOutboundItem? get selectedItem {
    for (final item in items) {
      if (item.tag == selected) return item;
    }
    return null;
  }

  /// Serializes the group using the wire format.
  Map<String, dynamic> toMap() => {
    'tag': tag,
    'type': type,
    'selectable': selectable,
    'selected': selected,
    'isExpand': isExpand,
    'items': items.map((e) => e.toMap()).toList(),
  };

  @override
  String toString() =>
      'SingBoxOutboundGroup($tag, $type, selected: $selected, '
      '${items.length} items)';
}
