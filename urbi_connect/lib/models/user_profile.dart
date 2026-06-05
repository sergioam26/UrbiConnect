import 'package:flutter/foundation.dart';
import 'package:urbi_connect/config/app_config.dart';

class SuperuserSession {
  static final ValueNotifier<String> roleNotifier =
      ValueNotifier<String>('admin');

  static String get activeRole {
    return roleNotifier.value;
  }

  static set simulatedRole(String val) {
    roleNotifier.value = val;
  }
}

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

    final emailVal = (data['email'] ?? '').toString().toLowerCase();
    String activeRole = (data['rol'] ?? 'ciudadano').toString().toLowerCase();
    if (emailVal == AppConfig.superUserEmail.toLowerCase()) {
      activeRole = SuperuserSession.activeRole;
    }

    return UserProfile(
      uid: uid,
      name: data['nombre'] ?? '',
      surnames: data['apellidos'] ?? '',
      email: data['email'] ?? '',
      username: data['usuario'] ?? '',
      role: activeRole,
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
