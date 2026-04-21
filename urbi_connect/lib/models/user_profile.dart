class UserProfile {
  final String uid;
  final String name;
  final String surnames;
  final String email;
  final String role; // 'Ciudadano', 'Responsable', 'Admin'
  final List<String>? categories; // Para responsables
  final String? pushToken;

  UserProfile({
    required this.uid,
    required this.name,
    required this.surnames,
    required this.email,
    required this.role,
    this.categories,
    this.pushToken,
  });

  String get username =>
      name; // Getter for username as requested by diagnostics

  factory UserProfile.fromMap(Map<String, dynamic> data, String uid) {
    List<String>? categories;
    if (data['id_categorias'] != null) {
      categories = List<String>.from(data['id_categorias']);
    } else if (data['id_categoria'] != null) {
      categories = [data['id_categoria'].toString()];
    }

    return UserProfile(
      uid: uid,
      name: data['nombre'] ?? '',
      surnames: data['apellidos'] ?? '',
      email: data['email'] ?? '',
      role: data['rol'] ?? 'Ciudadano',
      categories: categories,
      pushToken: data['token_push'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'nombre': name,
      'apellidos': surnames,
      'email': email,
      'rol': role,
      'id_categorias': categories,
      'token_push': pushToken,
    };
  }
}
