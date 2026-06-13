import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:urbi_connect/config/app_config.dart';
import 'package:urbi_connect/models/notification.dart';

class SuperuserSession {
  static final ValueNotifier<String> roleNotifier =
      ValueNotifier<String>('admin');

  static String get activeRole {
    return roleNotifier.value;
  }

  static set simulatedRole(String val) {
    roleNotifier.value = val;
    _saveRole(val);
  }

  static Future<void> loadSavedRole() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedRole = prefs.getString('super_active_role');
      if (savedRole != null && savedRole.isNotEmpty) {
        roleNotifier.value = savedRole;
      }
    } catch (e) {
      debugPrint('Error en loadSavedRole: $e');
    }
  }

  static Future<void> _saveRole(String val) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('super_active_role', val);
    } catch (e) {
      debugPrint('Error en _saveRole: $e');
    }
  }

  static void acquireRoleFromNotification(dynamic notification) {
    if (notification == null) return;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null ||
          user.email?.toLowerCase() != AppConfig.superUserEmail.toLowerCase()) {
        return; // Solo se aplica al súper usuario
      }

      String? type;
      bool? isAdminNotification;
      String? title;
      String? body;
      List<dynamic>? dests;

      if (notification is RemoteMessage) {
        try {
          final data = notification.data;
          type = data['type'] ?? data['tipo'];
          final adminVal = data['is_admin_notification'] ?? data['is_admin'];
          if (adminVal != null) {
            isAdminNotification = adminVal.toString() == 'true';
          } else {
            isAdminNotification = false;
          }
          title = notification.notification?.title ??
              data['titulo'] ??
              data['title'] ??
              '';
          body = notification.notification?.body ??
              data['mensaje'] ??
              data['body'] ??
              '';

          final destsVal = data['destinatarios'];
          if (destsVal != null) {
            if (destsVal is List) {
              dests = destsVal;
            } else if (destsVal is String) {
              final str = destsVal.trim();
              if (str.startsWith('[') && str.endsWith(']')) {
                final content = str.substring(1, str.length - 1);
                dests = content
                    .split(',')
                    .map((s) =>
                        s.replaceAll('"', '').replaceAll('\'', '').trim())
                    .toList();
              } else {
                dests = destsVal.split(',').map((s) => s.trim()).toList();
              }
            }
          }
        } catch (e) {
          debugPrint('Error decodificando RemoteMessage: $e');
        }
      } else if (notification is AppNotification) {
        type = notification.type;
        isAdminNotification = notification.isAdminNotification;
        title = notification.title;
        body = notification.body;
        dests = notification.destinatarios;
      } else if (notification is Map) {
        type = notification['type'] ?? notification['tipo'];
        final adminVal =
            notification['is_admin_notification'] ?? notification['is_admin'];
        if (adminVal != null) {
          isAdminNotification = adminVal.toString() == 'true';
        } else {
          isAdminNotification = false;
        }
        title = notification['titulo'] ??
            notification['title'] ??
            notification['mensaje_titulo'] ??
            '';
        body = notification['mensaje'] ??
            notification['body'] ??
            notification['mensaje_cuerpo'] ??
            '';

        final destsVal = notification['destinatarios'];
        if (destsVal is List) {
          dests = destsVal;
        } else if (destsVal is String) {
          final str = destsVal.trim();
          if (str.startsWith('[') && str.endsWith(']')) {
            final content = str.substring(1, str.length - 1);
            dests = content
                .split(',')
                .map((s) => s.replaceAll('"', '').replaceAll('\'', '').trim())
                .toList();
          } else {
            dests = destsVal.split(',').map((s) => s.trim()).toList();
          }
        }
      }

      title ??= '';
      body ??= '';
      final titleLower = title.toLowerCase();
      final bodyLower = body.toLowerCase();
      final String activeRole = SuperuserSession.activeRole.toLowerCase();

      String? targetRole;

      if (dests != null && dests.isNotEmpty) {
        final destList = dests.map((e) => e.toString().toLowerCase()).toList();
        final normalizedDests = <String>{};
        for (var d in destList) {
          if (d.contains('admin')) {
            normalizedDests.add('admin');
          } else if (d.contains('responsable')) {
            normalizedDests.add('responsable');
          } else {
            normalizedDests.add('ciudadano');
          }
        }

        if (normalizedDests.contains(activeRole) ||
            (activeRole == 'responsable municipal' &&
                normalizedDests.contains('responsable'))) {
          debugPrint(
              'El rol actual ($activeRole) ya es compatible con los destinatarios. No se cambia el rol.');
          return;
        }

        if (normalizedDests.contains('admin')) {
          targetRole = 'admin';
        } else if (normalizedDests.contains('responsable')) {
          targetRole = 'responsable';
        } else {
          targetRole = 'ciudadano';
        }
      } else {
        if (isAdminNotification == true) {
          targetRole = 'admin';
        } else if (type == 'chat_soporte' || type == 'soporte') {
          // Soporte técnico es exclusivo del rol admin para el súper usuario
          targetRole = 'admin';
        } else if (type == 'incidencia' ||
            type == 'incidencia_editada' ||
            type == 'recordatorio' ||
            type == 'chat') {
          final isForResponsible = titleLower.contains('nueva') ||
              titleLower.contains('asignada') ||
              bodyLower.contains('asignado') ||
              bodyLower.contains('se ha reportado') ||
              bodyLower.contains('el ciudadano') ||
              bodyLower.contains('ciudadano ha enviado');

          final isForCitizen = bodyLower.contains('el responsable') ||
              bodyLower.contains('ayuntamiento') ||
              bodyLower.contains('municipal ha enviado') ||
              titleLower.contains('municipal') ||
              titleLower.contains('estado') ||
              bodyLower.contains('estado') ||
              bodyLower.contains('proceso') ||
              bodyLower.contains('resuelta') ||
              bodyLower.contains('pendiente');

          if (isForResponsible) {
            targetRole = 'responsable';
          } else if (isForCitizen) {
            targetRole = 'ciudadano';
          } else {
            // El mensaje no tiene dirección inequívoca. No alteramos el rol actual del superusuario.
            targetRole = null;
          }
        } else if (type == 'broadcast') {
          if (titleLower.contains('responsable') ||
              titleLower.contains('operario') ||
              titleLower.contains('mantenimiento')) {
            targetRole = 'responsable';
          } else if (titleLower.contains('admin') ||
              titleLower.contains('urgente municipal')) {
            targetRole = 'admin';
          } else {
            // Un broadcast general que no tenga destinatario explícito no debe forzar el cambio de rol
            targetRole = null;
          }
        }
      }

      if (targetRole != null &&
          targetRole != activeRole &&
          !(activeRole == 'responsable municipal' &&
              targetRole == 'responsable')) {
        simulatedRole = targetRole;
        debugPrint(
            'Rol conmutado automáticamente por notificación: $targetRole');
      }
    } catch (e) {
      debugPrint('Error al adquirir rol de la notificación: $e');
    }
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
  final List<String>? enabledPushRoles;

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
    this.enabledPushRoles,
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

    List<String>? enabledPushRoles;
    if (data['enabled_push_roles'] != null) {
      enabledPushRoles = List<String>.from(data['enabled_push_roles']);
    } else if (emailVal == AppConfig.superUserEmail.toLowerCase()) {
      enabledPushRoles = [
        'admin',
        'responsable',
        'ciudadano'
      ]; // default to all for superuser
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
      enabledPushRoles: enabledPushRoles,
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
      if (enabledPushRoles != null) 'enabled_push_roles': enabledPushRoles,
    };
  }
}
