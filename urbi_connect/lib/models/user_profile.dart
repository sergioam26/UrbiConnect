class UserProfile {
  final String uid;
  final String name;
  final String surnames;
  final String email;
  final String username;
  final String role; // 'Ciudadano', 'Responsable', 'Admin'
  final String? profilePhoto;
  final List<String>? categories; // Para responsables
  final String? pushToken;

  UserProfile({
    required this.uid,
    required this.name,
    required this.surnames,
    required this.email,
    required this.username,
    required this.role,
    this.profilePhoto,
    this.categories,
    this.pushToken,
  });

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
      username: data['usuario'] ?? '',
      role: (data['rol'] ?? 'ciudadano').toString().toLowerCase(),
      profilePhoto: data['foto_perfil'],
      categories: categories,
      pushToken: data['token_push'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'nombre': name,
      'apellidos': surnames,
      'email': email,
      'usuario': username,
      'rol': role,
      'foto_perfil': profilePhoto,
      'id_categorias': categories,
      'token_push': pushToken,
    };
  }
}
