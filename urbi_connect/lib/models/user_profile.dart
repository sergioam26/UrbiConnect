class UserProfile {
  final String uid;
  final String name;
  final String email;
  final String role; // 'Ciudadano', 'Responsable', 'Admin'
  final String? category; // Para Responsables
  final String? pushToken;

  UserProfile({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    this.category,
    this.pushToken,
  });

  factory UserProfile.fromMap(Map<String, dynamic> data, String uid) {
    return UserProfile(
      uid: uid,
      name: data['nombre'] ?? '',
      email: data['email'] ?? '',
      role: data['rol'] ?? 'Ciudadano',
      category: data['categoria'],
      pushToken: data['token_push'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'nombre': name,
      'email': email,
      'rol': role,
      'categoria': category,
      'token_push': pushToken,
    };
  }
}
