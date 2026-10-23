/// Who gets called after a crash.
class EmergencyContact {
  const EmergencyContact({required this.name, required this.phone});

  factory EmergencyContact.fromJson(Map<String, dynamic> json) =>
      EmergencyContact(
        name: json['name'] as String,
        phone: json['phone'] as String,
      );

  final String name;

  /// Dialable form: digits with an optional leading '+'.
  final String phone;

  /// Strips spaces, dashes, dots and brackets. Returns null unless 3-20
  /// digits remain (with an optional leading '+').
  static String? normalizePhone(String input) {
    final compact = input.trim().replaceAll(RegExp(r'[\s\-.()]'), '');
    return RegExp(r'^\+?\d{3,20}$').hasMatch(compact) ? compact : null;
  }

  Map<String, dynamic> toJson() => {'name': name, 'phone': phone};
}
