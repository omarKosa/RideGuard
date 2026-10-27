/// The Google account the rider signed in with. Only the identity is kept;
/// the ID token is sent to the backend once and never stored.
class RiderAccount {
  const RiderAccount({required this.googleId, required this.email, this.name});

  factory RiderAccount.fromJson(Map<String, dynamic> json) => RiderAccount(
    googleId: json['google_id'] as String,
    email: json['email'] as String,
    name: json['name'] as String?,
  );

  final String googleId;
  final String email;
  final String? name;

  /// What to call the rider: their name, else their email.
  String get label {
    final n = name?.trim();
    return n == null || n.isEmpty ? email : n;
  }

  Map<String, dynamic> toJson() => {
    'google_id': googleId,
    'email': email,
    'name': name,
  };
}
