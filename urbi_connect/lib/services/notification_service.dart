import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:urbi_connect/config/app_config.dart';
import 'package:urbi_connect/models/incident.dart';
import 'package:urbi_connect/models/notification.dart';
import 'package:urbi_connect/models/user_profile.dart';
import 'package:urbi_connect/screens/incidents/chat_screen.dart';
import 'package:urbi_connect/screens/incidents/incident_detail_screen.dart';
import 'package:urbi_connect/screens/incidents/responsible_incident_detail_screen.dart';
import 'package:urbi_connect/screens/support/support_chat_screen.dart';

class NotificationService {
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();
  static StreamSubscription<QuerySnapshot>? _notifSubscription;
  static DateTime _listenerStartTime = DateTime.now();
  static final Set<String> _notifiedDocIds = {};

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  // Inicializar notificaciones push
  Future<void> initNotifications() async {
    if (kIsWeb) {
      debugPrint(
          'Iniciando sistema de notificaciones en Web (Modo Listener real de Firestore)...');

      // Escuchar el cambio de estado de autenticación de las sesiones para sincronizar el token proactivamente
      FirebaseAuth.instance.authStateChanges().listen((User? user) async {
        if (user != null) {
          debugPrint(
              'Sesión activa detectada en Web. Sincronizando listener de Firestore para: ${user.uid}');
          _startListeningToFirestoreNotifications(user.uid);
        } else {
          _notifSubscription?.cancel();
          _notifSubscription = null;
        }
      });

      // Iniciar el listener inmediatamente si ya hay un usuario logueado en la inicialización
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        _startListeningToFirestoreNotifications(currentUser.uid);
      }
      return;
    }

    // Configuración para Android (Soportando ambos canales para máxima compatibilidad)
    const AndroidNotificationChannel channelNew = AndroidNotificationChannel(
      'urbi_connect_alerts_channel_v1', // id
      'UrbiConnect Notificaciones', // title
      description:
          'Este canal se usa para notificaciones importantes.', // description
      importance: Importance.max,
    );

    const AndroidNotificationChannel channelLegacy = AndroidNotificationChannel(
      'high_importance_channel', // id
      'UrbiConnect Alertas', // title
      description:
          'Canal heredado de notificaciones importantes.', // description
      importance: Importance.max,
    );

    final androidPlugin =
        _localNotifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(channelNew);
      await androidPlugin.createNotificationChannel(channelLegacy);
    }

    // Configuración para notificaciones locales (primer plano)
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);

    await _localNotifications.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        debugPrint('Notificación local clickeada: ${response.payload}');
        if (response.payload != null && response.payload!.isNotEmpty) {
          try {
            final Map<String, dynamic> payloadData =
                jsonDecode(response.payload!);
            final referenceId = payloadData['referenceId'];
            final type = payloadData['type'];

            final context = navigatorKey.currentContext;
            if (context != null) {
              _handleLocalNavigation(context, referenceId, type);
            } else {
              debugPrint('Navigator context no listo para navegación local.');
            }
          } catch (e) {
            debugPrint('Error procesando click de notificación local: $e');
          }
        }
      },
    );

    // Solicitar explícitamente permisos de notificación local en Android 13+
    try {
      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (e) {
      debugPrint(
          'Error solicitando permisos de local notifications en Android: $e');
    }

    NotificationSettings settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional) {
      await syncFcmTokenState();
    }

    // Escuchar el cambio de estado de autenticación de las sesiones para sincronizar el token proactivamente
    FirebaseAuth.instance.authStateChanges().listen((User? user) async {
      if (user != null) {
        debugPrint(
            'Sesión activa detectada (authStateChanges). Sincronizando token FCM para el usuario: ${user.uid}');
        await syncFcmTokenState();
        _startListeningToFirestoreNotifications(user.uid);
      } else {
        _notifSubscription?.cancel();
        _notifSubscription = null;
      }
    });

    // Iniciar el listener inmediatamente si ya hay un usuario logueado en la inicialización
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      _startListeningToFirestoreNotifications(currentUser.uid);
    }

    // Escuchar cambios de token de forma proactiva y guardarlos automáticamente en la BD
    _fcm.onTokenRefresh.listen((String token) async {
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          await _db.collection('users').doc(user.uid).set({
            'fcm_token': token,
            'token_push': token,
            'fcm_token_backup': token,
            'token_push_backup': token,
            'fcmToken': token,
            'pushToken': token,
            'deviceToken': token,
            'fcm_tokens': FieldValue.arrayUnion([token]),
            'last_token_update': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          debugPrint(
              'FCM Token refrescado por el sistema operativo y guardado en la BD: $token');
        }
      } catch (e) {
        debugPrint('Error en onTokenRefresh de FCM: $e');
      }
    });

    // Manejar mensajes en primer plano con filtrado por rol
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      RemoteNotification? notification = message.notification;

      if (notification != null && !kIsWeb) {
        final bool showPush =
            await _isPushNotificationEnabledForMessage(message);
        if (!showPush) {
          debugPrint(
              'Notificación de primer plano filtrada y oculta (botón desactivado para este rol).');
          return;
        }

        _localNotifications.show(
          notification.hashCode,
          notification.title,
          notification.body,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'urbi_connect_alerts_channel_v1',
              'UrbiConnect Notificaciones',
              importance: Importance.max,
              priority: Priority.high,
              playSound: true,
              enableVibration: true,
              icon: 'ic_launcher',
            ),
          ),
        );
      }
    });

    // Intentar actualizar el token si el usuario ya está logueado
    await updateTokenInFirestore();

    // Limpiar notificaciones antiguas
    _deleteOldNotifications();
  }

  // Comprobar si las notificaciones push están activadas para el rol destinatario de este mensaje
  Future<bool> _isPushNotificationEnabledForMessage(
      RemoteMessage message) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return true;

      final profileDoc = await _db.collection('users').doc(user.uid).get();
      if (!profileDoc.exists) return true;

      final data = profileDoc.data();
      if (data == null) return true;

      // Obtener roles activos de push habilitados para este usuario
      final List<dynamic> enabledPushRoles =
          data.containsKey('enabled_push_roles')
              ? List.from(data['enabled_push_roles'])
              : ['admin', 'responsable', 'ciudadano'];

      // Determinar a qué rol va dirigida esta notificación
      final type = message.data['type'] ?? message.data['tipo'] ?? '';
      final title = message.notification?.title ??
          message.data['titulo'] ??
          message.data['title'] ??
          '';
      final body = message.notification?.body ??
          message.data['mensaje'] ??
          message.data['body'] ??
          '';
      final titleLower = title.toString().toLowerCase();
      final bodyLower = body.toString().toLowerCase();

      // Buscar destinatarios explícitos en el mensaje
      List<dynamic>? dests;
      final destsVal = message.data['destinatarios'];
      if (destsVal != null) {
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

      String targetRole = 'ciudadano'; // por defecto

      if (dests != null && dests.isNotEmpty) {
        final destList = dests.map((e) => e.toString().toLowerCase()).toList();
        if (destList.any((d) => d.contains('admin'))) {
          targetRole = 'admin';
        } else if (destList.any((d) => d.contains('responsable'))) {
          targetRole = 'responsable';
        } else {
          targetRole = 'ciudadano';
        }
      } else {
        if (type == 'chat_soporte' ||
            type == 'soporte' ||
            (message.data['is_admin_notification'] ?? '').toString() ==
                'true') {
          targetRole = 'admin';
        } else if (type == 'recordatorio') {
          targetRole = 'responsable';
        } else if (type == 'chat') {
          if (bodyLower.contains('designado') ||
              titleLower.contains('asignada') ||
              titleLower.contains('responsable') ||
              bodyLower.contains('asignado') ||
              bodyLower.contains('el ciudadano') ||
              bodyLower.contains('ciudadano ha enviado')) {
            targetRole = 'responsable';
          } else if (bodyLower.contains('el responsable') ||
              bodyLower.contains('ayuntamiento') ||
              bodyLower.contains('municipal ha enviado')) {
            targetRole = 'ciudadano';
          } else {
            // Suponer el rol activo de pruebas si no se puede determinar inequívocamente
            targetRole = SuperuserSession.activeRole.toLowerCase();
          }
        } else if (type == 'incidencia' || type == 'incidencia_editada') {
          final isForResponsible = titleLower.contains('nueva') ||
              titleLower.contains('asignada') ||
              bodyLower.contains('asignado') ||
              bodyLower.contains('se ha reportado');
          if (isForResponsible) {
            targetRole = 'responsable';
          } else {
            targetRole = 'ciudadano';
          }
        }
      }

      // Comprobar intersección de targetRole con enabledPushRoles de forma centralizada y robusta
      return _isRoleEnabled(enabledPushRoles, targetRole);
    } catch (e) {
      debugPrint('Error filtrando notificación push en primer plano: $e');
      return true;
    }
  }

  // Manejar el clic en una notificación Push
  void setupInteractedMessages(BuildContext context) async {
    // Cuando la aplicación se abre desde el estado de terminada (cold start)
    RemoteMessage? initialMessage = await _fcm.getInitialMessage();
    if (initialMessage != null && context.mounted) {
      _handlePushMessage(context, initialMessage);
    }

    // Cuando la aplicación está en segundo plano y se abre mediante click en notificación
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      if (context.mounted) {
        _handlePushMessage(context, message);
      }
    });
  }

  Future<void> _handlePushMessage(
      BuildContext context, RemoteMessage message) async {
    final referenceId =
        message.data['referenceId'] ?? message.data['id_referencia'];
    final type = message.data['type'] ?? message.data['tipo'];

    // Marcar como leída la notificación en el buzón automáticamente al abrirla desde un push
    if (referenceId != null && referenceId.trim().isNotEmpty) {
      await markNotificationsAsReadForReference(referenceId, type);
    }

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final bool isSuper =
            user.email?.toLowerCase() == AppConfig.superUserEmail.toLowerCase();

        if (isSuper && referenceId != null && referenceId.isNotEmpty) {
          if (type == 'chat') {
            final incidentDoc =
                await _db.collection('Incidencia').doc(referenceId).get();
            if (incidentDoc.exists) {
              final String creatorId = incidentDoc.get('id_usuario') ?? '';
              if (creatorId == user.uid) {
                SuperuserSession.simulatedRole = 'ciudadano';
              } else {
                SuperuserSession.simulatedRole = 'responsable';
              }
            }
          } else if (type == 'soporte' || type == 'chat_soporte') {
            SuperuserSession.simulatedRole = 'admin';
          } else if (type == 'incidencia' ||
              type == 'incidencia_editada' ||
              type == 'recordatorio' ||
              type == 'incidencia_eliminada') {
            if (type == 'recordatorio') {
              SuperuserSession.simulatedRole = 'responsable';
            } else {
              final incidentDoc =
                  await _db.collection('Incidencia').doc(referenceId).get();
              if (incidentDoc.exists) {
                final String creatorId = incidentDoc.get('id_usuario') ?? '';
                if (creatorId == user.uid) {
                  SuperuserSession.simulatedRole = 'ciudadano';
                } else {
                  SuperuserSession.simulatedRole = 'responsable';
                }
              } else {
                if (type == 'incidencia') {
                  SuperuserSession.simulatedRole = 'responsable';
                } else {
                  SuperuserSession.simulatedRole = 'ciudadano';
                }
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error en la conmutación previa de rol: $e');
    }

    // Ejecutar lógica de respaldo
    SuperuserSession.acquireRoleFromNotification(message);

    if (referenceId == null || referenceId.isEmpty) return;

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final bool isSuper =
          user.email?.toLowerCase() == AppConfig.superUserEmail.toLowerCase();

      if (type == 'chat') {
        if (context.mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => ChatScreen(incidentId: referenceId)),
          );
        }
      } else if (type == 'soporte' || type == 'chat_soporte') {
        final profileDoc = await _db.collection('users').doc(user.uid).get();
        final bool isDbAdmin = profileDoc.exists &&
            (profileDoc.get('rol') ?? '').toString().toLowerCase() == 'admin';

        final activeRole = SuperuserSession.activeRole.toLowerCase();
        final bool resolvedIsAdmin =
            isSuper ? (activeRole == 'admin') : isDbAdmin;

        if (context.mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => SupportChatScreen(
                  ticketId: referenceId, isAdmin: resolvedIsAdmin),
            ),
          );
        }
      } else if (type == 'incidencia' ||
          type == 'incidencia_editada' ||
          type == 'recordatorio' ||
          type == 'incidencia_eliminada') {
        final incidentDoc =
            await _db.collection('Incidencia').doc(referenceId).get();
        if (!incidentDoc.exists) return;

        final incident = Incident.fromFirestore(incidentDoc);

        final profileDoc = await _db.collection('users').doc(user.uid).get();
        if (!profileDoc.exists) return;

        final profile = UserProfile.fromMap(profileDoc.data()!, user.uid);
        final activeRole = isSuper
            ? SuperuserSession.activeRole.toLowerCase()
            : profile.role.toLowerCase();

        if (context.mounted) {
          if (activeRole == 'responsable' ||
              activeRole == 'responsable municipal') {
            Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) =>
                      ResponsibleIncidentDetailScreen(incident: incident)),
            );
          } else {
            Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) =>
                      IncidentDetailScreen(incident: incident)),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Error al navegar desde push: $e');
    }
  }

  // Marcar automáticamente todas las notificaciones de Firestore asociadas a una referencia como leídas
  Future<void> markNotificationsAsReadForReference(
      String? referenceId, String? type) async {
    if (referenceId == null || referenceId.trim().isEmpty) return;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final List<String> targetUserIds = [user.uid, 'silenciado_${user.uid}'];

      final querySnapshot = await _db
          .collection('Notificaciones')
          .where('id_usuario', whereIn: targetUserIds)
          .where('id_referencia', isEqualTo: referenceId.trim())
          .where('leido', isEqualTo: false)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        final batch = _db.batch();
        for (var doc in querySnapshot.docs) {
          batch.update(doc.reference, {
            'leido': true,
            'isRead': true,
          });
        }
        await batch.commit();
        debugPrint(
            'Marcadas ${querySnapshot.docs.length} notificaciones como leídas para referencia: $referenceId');
      }
    } catch (e) {
      debugPrint(
          'Error marcando notificaciones asociadas como leídas de forma automática: $e');
    }
  }

  // Sincronizar el estado del token FCM en la base de datos de acuerdo con los permisos del dispositivo y escribir fcm_token y token_push para compatibilidad absoluta
  Future<void> syncFcmTokenState() async {
    if (kIsWeb) return;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      NotificationSettings settings = await _fcm.getNotificationSettings();
      if (settings.authorizationStatus == AuthorizationStatus.notDetermined) {
        settings = await _fcm.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
      }

      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        String? token = await _fcm.getToken();
        if (token != null) {
          await _db.collection('users').doc(user.uid).set({
            'fcm_token': token,
            'token_push': token,
            'fcm_token_backup': token,
            'token_push_backup': token,
            'fcmToken': token,
            'pushToken': token,
            'deviceToken': token,
            'fcm_tokens': FieldValue.arrayUnion([token]),
            'last_token_update': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          debugPrint(
              'FCM Token guardado en la BD (fcm_token, token_push, fcmToken, etc.) para el usuario ${user.uid}: $token');
        } else {
          debugPrint('FCM Token retornado como nulo por Firebase SDK.');
        }
      } else {
        debugPrint(
            'Permisos de notificaciones no autorizados en el dispositivo: ${settings.authorizationStatus}');
      }
    } catch (e) {
      debugPrint('Error en syncFcmTokenState: $e');
    }
  }

  // Actualizar el token del dispositivo en Firestore
  Future<void> updateTokenInFirestore() async {
    await syncFcmTokenState();
  }

  // Eliminar notificaciones de más de 2 semanas (desactivado borrado físico)
  Future<void> _deleteOldNotifications() async {
    debugPrint(
        'Exigencia del cliente: Borrado físico de notificaciones antiguas desactivado.');
  }

  bool _belongsToRole(AppNotification n, String role) {
    final roleLower = role.toLowerCase();

    // 1. Si está marcada explícitamente como notificación de administrador
    if (n.isAdminNotification) {
      return roleLower == 'admin';
    }

    // 2. Si tiene destinatarios explícitos (ahora se guardarán en las nuevas notificaciones)
    final dests = n.destinatarios?.map((e) => e.toLowerCase()).toList() ?? [];
    if (dests.isNotEmpty) {
      if (roleLower == 'admin') {
        return dests.contains('admin');
      } else if (roleLower == 'responsable' ||
          roleLower == 'responsable municipal') {
        return dests.contains('responsable') ||
            dests.contains('responsables') ||
            dests.contains('responsable municipal');
      } else {
        return dests.contains('ciudadano') || dests.contains('ciudadanos');
      }
    }

    // 3. Fallback / Retrocompatibilidad / Notificaciones sin destinatarios persistidos
    final titleLower = n.title.toLowerCase();
    final bodyLower = n.body.toLowerCase();

    if (n.type == 'broadcast') {
      if (titleLower.contains('responsable') ||
          titleLower.contains('operario') ||
          titleLower.contains('mantenimiento')) {
        return roleLower == 'responsable' ||
            roleLower == 'responsable municipal';
      } else if (titleLower.contains('admin') ||
          titleLower.contains('urgente municipal')) {
        return roleLower == 'admin';
      } else {
        return roleLower == 'ciudadano';
      }
    }

    // Soporte es solo para admin para el súper usuario (los ciudadanos normales no usan belongsToRole)
    if (n.type == 'chat_soporte' || n.type == 'soporte') {
      return roleLower == 'admin';
    }

    // Para incidencias, recordatorios y chats de incidencia
    // Si es recordatorio, va para el responsable municipal
    if (n.type == 'recordatorio') {
      return roleLower == 'responsable' || roleLower == 'responsable municipal';
    }

    // Si es chat (Nuevo mensaje en chat)
    if (n.type == 'chat') {
      if (bodyLower.contains('asignado') ||
          titleLower.contains('asignada') ||
          titleLower.contains('responsable')) {
        return roleLower == 'responsable' ||
            roleLower == 'responsable municipal';
      }
      if (bodyLower.contains('el ciudadano') ||
          bodyLower.contains('ciudadano ha enviado')) {
        return roleLower == 'responsable' ||
            roleLower == 'responsable municipal';
      }
      if (bodyLower.contains('el responsable') ||
          bodyLower.contains('ayuntamiento') ||
          bodyLower.contains('municipal ha enviado')) {
        return roleLower == 'ciudadano';
      }
      // Si no podemos determinarlo de forma inequívoca (por ejemplo, es un texto plano de chat nuevo),
      // lo asumimos visible tanto en ciudadano como en responsable municipal, de forma que el súper usuario
      // o el usuario de pruebas nunca reciba una vista vacía ni "pierda" notificaciones de hilos activos.
      return true;
    }

    if (n.type == 'incidencia' || n.type == 'incidencia_editada') {
      final isForResponsible = titleLower.contains('nueva') ||
          titleLower.contains('asignada') ||
          bodyLower.contains('asignado') ||
          bodyLower.contains('se ha reportado');
      if (isForResponsible) {
        return roleLower == 'responsable' ||
            roleLower == 'responsable municipal';
      } else {
        return roleLower == 'ciudadano';
      }
    }

    return roleLower == 'ciudadano';
  }

  // Stream de notificaciones del buzón
  Stream<List<AppNotification>> getNotifications(String userId) {
    return _db
        .collection('Notificaciones')
        .where('id_usuario', whereIn: [userId, 'silenciado_$userId'])
        .snapshots()
        .map((snapshot) {
          final twentyOneDaysAgo =
              DateTime.now().subtract(const Duration(days: 21));

          final currentUser = FirebaseAuth.instance.currentUser;
          final bool isCurrentUserSuper = currentUser != null &&
              currentUser.uid == userId &&
              currentUser.email?.toLowerCase() ==
                  AppConfig.superUserEmail.toLowerCase();

          var notifications = snapshot.docs
              .map((doc) {
                try {
                  return AppNotification.fromFirestore(doc);
                } catch (e) {
                  debugPrint('Error al parsear notificación ${doc.id}: $e');
                  return null;
                }
              })
              .whereType<AppNotification>()
              .where((n) => n.createdAt
                  .isAfter(twentyOneDaysAgo)) // Ocultar en la app tras 21 días
              .toList();

          if (isCurrentUserSuper) {
            final activeRole = SuperuserSession.activeRole.toLowerCase();
            notifications = notifications
                .where((n) => _belongsToRole(n, activeRole))
                .toList();
          }

          // Ordenar en memoria por fecha de creación descendente
          notifications.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return notifications;
        });
  }

  // Marcar como leída
  Future<void> markAsRead(String id) {
    return _db.collection('Notificaciones').doc(id).update({'leido': true});
  }

  // Obtener número de notificaciones no leídas
  Stream<int> getUnreadCount(String userId) {
    return _db
        .collection('Notificaciones')
        .where('id_usuario', whereIn: [userId, 'silenciado_$userId'])
        .where('leido', isEqualTo: false)
        .snapshots()
        .map((snapshot) {
          final twentyOneDaysAgo =
              DateTime.now().subtract(const Duration(days: 21));

          final currentUser = FirebaseAuth.instance.currentUser;
          final bool isCurrentUserSuper = currentUser != null &&
              currentUser.uid == userId &&
              currentUser.email?.toLowerCase() ==
                  AppConfig.superUserEmail.toLowerCase();

          return snapshot.docs.where((doc) {
            try {
              final timestamp = doc.get('fecha_creacion') as Timestamp?;
              if (timestamp == null) return false;
              if (!timestamp.toDate().isAfter(twentyOneDaysAgo)) return false;

              if (isCurrentUserSuper) {
                final activeRole = SuperuserSession.activeRole.toLowerCase();
                final AppNotification n = AppNotification.fromFirestore(doc);
                return _belongsToRole(n, activeRole);
              }
              return true;
            } catch (_) {
              return false;
            }
          }).length;
        });
  }

  String _determineTargetRole({
    String? type,
    String? title,
    String? body,
    List<String>? destinatarios,
    bool isAdminNotification = false,
  }) {
    final titleLower = (title ?? '').toLowerCase();
    final bodyLower = (body ?? '').toLowerCase();
    final typeLower = (type ?? '').toLowerCase();

    if (destinatarios != null && destinatarios.isNotEmpty) {
      final destList = destinatarios.map((e) => e.toLowerCase()).toList();
      if (destList.any((d) => d.contains('admin'))) {
        return 'admin';
      } else if (destList.any((d) => d.contains('responsable'))) {
        return 'responsable';
      } else {
        return 'ciudadano';
      }
    }

    if (isAdminNotification ||
        typeLower == 'chat_soporte' ||
        typeLower == 'soporte' ||
        typeLower == 'soporte_chat') {
      return 'admin';
    } else if (typeLower == 'recordatorio') {
      return 'responsable';
    } else if (typeLower == 'chat') {
      if (bodyLower.contains('designado') ||
          titleLower.contains('asignada') ||
          titleLower.contains('responsable') ||
          bodyLower.contains('asignado') ||
          bodyLower.contains('el ciudadano') ||
          bodyLower.contains('ciudadano ha enviado')) {
        return 'responsable';
      } else if (bodyLower.contains('el responsable') ||
          bodyLower.contains('ayuntamiento') ||
          bodyLower.contains('municipal ha enviado')) {
        return 'ciudadano';
      } else {
        return SuperuserSession.activeRole.toLowerCase();
      }
    } else if (typeLower == 'incidencia' || typeLower == 'incidencia_editada') {
      final isForResponsible = titleLower.contains('nueva') ||
          titleLower.contains('asignada') ||
          bodyLower.contains('asignado') ||
          bodyLower.contains('se ha reportado');
      if (isForResponsible) {
        return 'responsable';
      } else {
        return 'ciudadano';
      }
    }

    return 'ciudadano';
  }

  // Método auxiliar centralizado para determinar si el rol destino está en el listado de roles push configurados por el usuario
  bool _isRoleEnabled(List<dynamic> enabledPushRoles, String targetRole) {
    if (enabledPushRoles.isEmpty) return false;
    final trl = targetRole.toLowerCase().trim();
    return enabledPushRoles.any((er) {
      final erl = er.toString().toLowerCase().trim();
      return erl == trl ||
          trl.contains(erl) ||
          erl.contains(trl) ||
          (trl.contains('responsable') && erl.contains('responsable')) ||
          (trl.contains('admin') && erl.contains('admin')) ||
          (trl.contains('ciudadano') && erl.contains('ciudadano'));
    });
  }

  // Enviar notificación individual
  Future<void> sendNotification({
    required String userId,
    required String title,
    required String body,
    String? referenceId,
    String? type,
    bool esOficial = false,
    String? imageUrl,
    bool isAdminNotification = false,
    List<String>? destinatarios,
  }) async {
    String? targetUserFcmToken;
    String? targetUserTokenPush;
    String? targetUserFcmTokenBackup;
    String? targetUserTokenPushBackup;
    String? targetUserFcmTokenCamel;
    String? targetUserPushTokenCamel;
    String? targetUserDeviceTokenCamel;
    List<dynamic>? targetUserFcmTokensList;

    bool shouldSendPush = true;
    try {
      final userDoc = await _db.collection('users').doc(userId).get();
      if (userDoc.exists) {
        final data = userDoc.data();
        if (data != null) {
          targetUserFcmToken = data['fcm_token']?.toString();
          targetUserTokenPush = data['token_push']?.toString();
          targetUserFcmTokenBackup = data['fcm_token_backup']?.toString();
          targetUserTokenPushBackup = data['token_push_backup']?.toString();
          targetUserFcmTokenCamel = data['fcmToken']?.toString();
          targetUserPushTokenCamel = data['pushToken']?.toString();
          targetUserDeviceTokenCamel = data['deviceToken']?.toString();
          if (data['fcm_tokens'] is List) {
            targetUserFcmTokensList = List.from(data['fcm_tokens']);
          }

          final List<dynamic> enabledPushRoles =
              data.containsKey('enabled_push_roles')
                  ? List.from(data['enabled_push_roles'])
                  : ['admin', 'responsable', 'ciudadano'];

          final String targetRole = _determineTargetRole(
            type: type,
            title: title,
            body: body,
            destinatarios: destinatarios,
            isAdminNotification: isAdminNotification,
          );

          shouldSendPush = _isRoleEnabled(enabledPushRoles, targetRole);
        }
      }
    } catch (e) {
      debugPrint('Error comprobando roles habilitados para el envío: $e');
    }

    final String storedUserId = shouldSendPush ? userId : 'silenciado_$userId';

    final Map<String, dynamic> notificationDoc = {
      // Spanish fields (for frontend & full compatibility)
      'id_usuario': storedUserId,
      'titulo': title,
      'mensaje': body,
      'fecha_creacion': FieldValue.serverTimestamp(),
      'leido': false,
      'id_referencia': referenceId,
      'tipo': type,
      'es_oficial': esOficial,
      'url_imagen': imageUrl,
      'is_admin_notification': isAdminNotification,
      if (destinatarios != null) 'destinatarios': destinatarios,

      // English fields (for original Firebase Blueprint compatibility & generic Cloud Functions)
      'userId': storedUserId,
      'title': title,
      'body': body,
      'createdAt': FieldValue.serverTimestamp(),
      'isRead': false,
      'referenceId': referenceId,
      'type': type,
      'isOfficial': esOficial,
      'imageUrl': imageUrl,
      'isAdminNotification': isAdminNotification,
      if (destinatarios != null) 'destinatariosList': destinatarios,

      // Universal triggers for any background push listener
      'send_push': shouldSendPush,
      'push_enabled': shouldSendPush,
      'push': shouldSendPush,
      'es_push': shouldSendPush,
      'trigger_push': shouldSendPush,
      'sendPush': shouldSendPush,
      'pushEnabled': shouldSendPush,
    };

    if (shouldSendPush) {
      // Legacy FCM target specifier (extremely important if they call legacy FCM relay)
      if (targetUserFcmToken != null) {
        notificationDoc['to'] = targetUserFcmToken;
      }

      // Embedded FCM destination tokens for simple/direct Cloud Functions or Extensions triggers
      if (targetUserFcmToken != null) {
        notificationDoc['fcm_token'] = targetUserFcmToken;
      }
      if (targetUserTokenPush != null) {
        notificationDoc['token_push'] = targetUserTokenPush;
      }
      if (targetUserFcmTokenBackup != null) {
        notificationDoc['fcm_token_backup'] = targetUserFcmTokenBackup;
      }
      if (targetUserTokenPushBackup != null) {
        notificationDoc['token_push_backup'] = targetUserTokenPushBackup;
      }
      if (targetUserFcmTokenCamel != null) {
        notificationDoc['fcmToken'] = targetUserFcmTokenCamel;
      }
      if (targetUserPushTokenCamel != null) {
        notificationDoc['pushToken'] = targetUserPushTokenCamel;
      }
      if (targetUserDeviceTokenCamel != null) {
        notificationDoc['deviceToken'] = targetUserDeviceTokenCamel;
      }
      if (targetUserFcmTokensList != null) {
        notificationDoc['fcm_tokens'] = targetUserFcmTokensList;
      }
      if (targetUserFcmToken != null) {
        notificationDoc['token'] = targetUserFcmToken;
      }
      if (targetUserFcmTokensList != null) {
        notificationDoc['tokens'] = targetUserFcmTokensList;
      }

      // Nested structures for direct/transparent FCM pass-through relays (super tolerant redundancy)
      notificationDoc['notification'] = {
        'title': title,
        'body': body,
        'titulo': title,
        'mensaje': body,
        'sound': 'default',
        'click_action': 'FLUTTER_NOTIFICATION_CLICK',
        'android_channel_id': 'high_importance_channel',
        'channel_id': 'high_importance_channel',
        'android_channel_id_v1': 'urbi_connect_alerts_channel_v1',
        'channel_id_v1': 'urbi_connect_alerts_channel_v1',
      };

      notificationDoc['data'] = {
        'click_action': 'FLUTTER_NOTIFICATION_CLICK',
        'clickAction': 'FLUTTER_NOTIFICATION_CLICK',
        'referenceId': referenceId ?? '',
        'id_referencia': referenceId ?? '',
        'type': type ?? '',
        'tipo': type ?? '',
        'title': title,
        'body': body,
        'titulo': title,
        'mensaje': body,
        'is_admin_notification': isAdminNotification.toString(),
        'sound': 'default',
        'android_channel_id': 'high_importance_channel',
        'channel_id': 'high_importance_channel',
        'android_channel_id_v1': 'urbi_connect_alerts_channel_v1',
        'channel_id_v1': 'urbi_connect_alerts_channel_v1',
      };

      // Complete FCM V1 compliant specification in case the Cloud Function relays the payload directly
      notificationDoc['message'] = {
        'token': targetUserFcmToken ??
            targetUserTokenPush ??
            targetUserFcmTokenCamel,
        'notification': {
          'title': title,
          'body': body,
        },
        'data': {
          'click_action': 'FLUTTER_NOTIFICATION_CLICK',
          'clickAction': 'FLUTTER_NOTIFICATION_CLICK',
          'referenceId': referenceId ?? '',
          'id_referencia': referenceId ?? '',
          'type': type ?? '',
          'tipo': type ?? '',
          'title': title,
          'body': body,
          'titulo': title,
          'mensaje': body,
          'is_admin_notification': isAdminNotification.toString(),
        },
        'android': {
          'priority': 'high',
          'priority_legacy': 'HIGH',
          'notification': {
            'sound': 'default',
            'channel_id': 'high_importance_channel',
            'android_channel_id': 'high_importance_channel',
            'channel_id_v1': 'urbi_connect_alerts_channel_v1',
            'android_channel_id_v1': 'urbi_connect_alerts_channel_v1',
            'click_action': 'FLUTTER_NOTIFICATION_CLICK',
            'icon': 'ic_launcher',
            'notification_priority': 'PRIORITY_HIGH',
            'default_sound': true,
            'default_vibrate_timings': true,
          },
        },
        'apns': {
          'headers': {
            'apns-priority': '10',
          },
          'payload': {
            'aps': {
              'alert': {
                'title': title,
                'body': body,
              },
              'sound': 'default',
              'content-available': 1,
              'badge': 1,
            },
          },
        },
      };

      notificationDoc['click_action'] = 'FLUTTER_NOTIFICATION_CLICK';
      notificationDoc['clickAction'] = 'FLUTTER_NOTIFICATION_CLICK';
      notificationDoc['sound'] = 'default';
      notificationDoc['priority'] = 'high';
      notificationDoc['android_channel_id'] = 'high_importance_channel';
      notificationDoc['notification_channel_id'] = 'high_importance_channel';
      notificationDoc['channelId'] = 'high_importance_channel';
      notificationDoc['channel_id'] = 'high_importance_channel';
      notificationDoc['android_channel_id_v1'] =
          'urbi_connect_alerts_channel_v1';
      notificationDoc['notification_channel_id_v1'] =
          'urbi_connect_alerts_channel_v1';
      notificationDoc['channelId_v1'] = 'urbi_connect_alerts_channel_v1';
      notificationDoc['channel_id_v1'] = 'urbi_connect_alerts_channel_v1';
      notificationDoc['importance'] = 'max';
      notificationDoc['high_importance'] = true;
      notificationDoc['badge'] = 1;
      notificationDoc['badge_count'] = 1;
      notificationDoc['icon'] = 'ic_launcher';
    }

    await _db.collection('Notificaciones').add(notificationDoc);
  }

  // Enviar notificación a múltiples grupos
  Future<void> broadcastNotification({
    required List<String> roles,
    required String title,
    required String body,
    String? imageUrl,
  }) async {
    try {
      final String? currentUserId = FirebaseAuth.instance.currentUser?.uid;

      // Expandir los roles para incluir variaciones de mayúsculas/minúsculas para compatibilidad absoluta
      final Set<String> expandedRoles = {};
      for (var r in roles) {
        expandedRoles.add(r);
        expandedRoles.add(r.toLowerCase());
        expandedRoles.add(r.toUpperCase());
        if (r.isNotEmpty) {
          expandedRoles.add(r[0].toUpperCase() + r.substring(1).toLowerCase());
        }
      }
      final List<String> queryRoles = expandedRoles.toList();

      final usersSnapshot =
          await _db.collection('users').where('rol', whereIn: queryRoles).get();

      final List<DocumentSnapshot> targetUsers = List.from(usersSnapshot.docs);

      // Integrar al súper usuario incondicionalmente en la base de datos para pruebas
      try {
        final superUserQuery =
            await _db.collection('users').where('email', whereIn: [
          AppConfig.superUserEmail.toLowerCase(),
          AppConfig.superUserEmail.toUpperCase(),
          AppConfig.superUserEmail,
          'Sergioalgmir@gmail.com',
          'SergioAlgmir@gmail.com',
          'SERGIOALGMIR@GMAIL.COM',
        ]).get();
        if (superUserQuery.docs.isNotEmpty) {
          final superUserDoc = superUserQuery.docs.first;
          final alreadyIncluded =
              targetUsers.any((d) => d.id == superUserDoc.id);
          if (!alreadyIncluded) {
            targetUsers.add(superUserDoc);
          }
        }
      } catch (e) {
        debugPrint('Error al integrar súper usuario en broadcast: $e');
      }

      final batch = _db.batch();

      for (var doc in targetUsers) {
        // No enviar notificación al admin que la envía, a menos que sea el súper usuario
        if (doc.id == currentUserId) {
          final isSuper = doc.data() is Map &&
              (doc.get('email') ?? '').toString().toLowerCase() ==
                  AppConfig.superUserEmail.toLowerCase();
          if (!isSuper) continue;
        }

        String? targetUserFcmToken;
        String? targetUserTokenPush;
        String? targetUserFcmTokenBackup;
        String? targetUserTokenPushBackup;
        String? targetUserFcmTokenCamel;
        String? targetUserPushTokenCamel;
        String? targetUserDeviceTokenCamel;
        List<dynamic>? targetUserFcmTokensList;

        bool userShouldSendPush = true;
        try {
          final data = doc.data() as Map<String, dynamic>?;
          if (data != null) {
            targetUserFcmToken = data['fcm_token']?.toString();
            targetUserTokenPush = data['token_push']?.toString();
            targetUserFcmTokenBackup = data['fcm_token_backup']?.toString();
            targetUserTokenPushBackup = data['token_push_backup']?.toString();
            targetUserFcmTokenCamel = data['fcmToken']?.toString();
            targetUserPushTokenCamel = data['pushToken']?.toString();
            targetUserDeviceTokenCamel = data['deviceToken']?.toString();
            if (data['fcm_tokens'] is List) {
              targetUserFcmTokensList = List.from(data['fcm_tokens']);
            }

            final List<dynamic> enabledPushRoles =
                data.containsKey('enabled_push_roles')
                    ? List.from(data['enabled_push_roles'])
                    : ['admin', 'responsable', 'ciudadano'];

            userShouldSendPush =
                roles.any((r) => _isRoleEnabled(enabledPushRoles, r));
          }
        } catch (e) {
          debugPrint('Error comprobando roles del broadcast: $e');
        }

        final notifRef = _db.collection('Notificaciones').doc();
        final String storedUserId =
            userShouldSendPush ? doc.id : 'silenciado_${doc.id}';

        final Map<String, dynamic> notificationDoc = {
          // Spanish fields (for frontend & full compatibility)
          'id_usuario': storedUserId,
          'titulo': title,
          'mensaje': body,
          'fecha_creacion': FieldValue.serverTimestamp(),
          'leido': false,
          'tipo': 'broadcast',
          'es_oficial': true,
          'destinatarios': roles,
          'url_imagen': imageUrl,

          // English fields (for original Firebase Blueprint compatibility & generic Cloud Functions)
          'userId': storedUserId,
          'title': title,
          'body': body,
          'createdAt': FieldValue.serverTimestamp(),
          'isRead': false,
          'type': 'broadcast',
          'isOfficial': true,
          'destinatariosList': roles,
          'imageUrl': imageUrl,

          // Universal triggers for any background push listener
          'send_push': userShouldSendPush,
          'push_enabled': userShouldSendPush,
          'push': userShouldSendPush,
          'es_push': userShouldSendPush,
          'trigger_push': userShouldSendPush,
          'sendPush': userShouldSendPush,
          'pushEnabled': userShouldSendPush,
        };

        if (userShouldSendPush) {
          // Embedded FCM destination tokens for simple/direct Cloud Functions or Extensions triggers
          if (targetUserFcmToken != null) {
            notificationDoc['fcm_token'] = targetUserFcmToken;
          }
          if (targetUserTokenPush != null) {
            notificationDoc['token_push'] = targetUserTokenPush;
          }
          if (targetUserFcmTokenBackup != null) {
            notificationDoc['fcm_token_backup'] = targetUserFcmTokenBackup;
          }
          if (targetUserTokenPushBackup != null) {
            notificationDoc['token_push_backup'] = targetUserTokenPushBackup;
          }
          if (targetUserFcmTokenCamel != null) {
            notificationDoc['fcmToken'] = targetUserFcmTokenCamel;
          }
          if (targetUserPushTokenCamel != null) {
            notificationDoc['pushToken'] = targetUserPushTokenCamel;
          }
          if (targetUserDeviceTokenCamel != null) {
            notificationDoc['deviceToken'] = targetUserDeviceTokenCamel;
          }
          if (targetUserFcmTokensList != null) {
            notificationDoc['fcm_tokens'] = targetUserFcmTokensList;
          }
          if (targetUserFcmToken != null) {
            notificationDoc['token'] = targetUserFcmToken;
          }
          if (targetUserFcmTokensList != null) {
            notificationDoc['tokens'] = targetUserFcmTokensList;
          }
          if (targetUserFcmToken != null) {
            notificationDoc['to'] = targetUserFcmToken;
          }

          // Nested structures for direct/transparent FCM pass-through relays (super tolerant redundancy)
          notificationDoc['notification'] = {
            'title': title,
            'body': body,
            'titulo': title,
            'mensaje': body,
            'sound': 'default',
            'click_action': 'FLUTTER_NOTIFICATION_CLICK',
            'android_channel_id': 'high_importance_channel',
            'channel_id': 'high_importance_channel',
            'android_channel_id_v1': 'urbi_connect_alerts_channel_v1',
            'channel_id_v1': 'urbi_connect_alerts_channel_v1',
          };
          notificationDoc['data'] = {
            'click_action': 'FLUTTER_NOTIFICATION_CLICK',
            'clickAction': 'FLUTTER_NOTIFICATION_CLICK',
            'referenceId': '',
            'id_referencia': '',
            'type': 'broadcast',
            'tipo': 'broadcast',
            'title': title,
            'body': body,
            'titulo': title,
            'mensaje': body,
            'sound': 'default',
            'android_channel_id': 'high_importance_channel',
            'channel_id': 'high_importance_channel',
            'android_channel_id_v1': 'urbi_connect_alerts_channel_v1',
            'channel_id_v1': 'urbi_connect_alerts_channel_v1',
          };

          // Complete FCM V1 compliant specification in case the Cloud Function relays the payload directly
          notificationDoc['message'] = {
            'token': targetUserFcmToken ??
                targetUserTokenPush ??
                targetUserFcmTokenCamel,
            'notification': {
              'title': title,
              'body': body,
            },
            'data': {
              'click_action': 'FLUTTER_NOTIFICATION_CLICK',
              'clickAction': 'FLUTTER_NOTIFICATION_CLICK',
              'referenceId': '',
              'id_referencia': '',
              'type': 'broadcast',
              'tipo': 'broadcast',
              'title': title,
              'body': body,
              'titulo': title,
              'mensaje': body,
            },
            'android': {
              'priority': 'high',
              'priority_legacy': 'HIGH',
              'notification': {
                'sound': 'default',
                'channel_id': 'high_importance_channel',
                'android_channel_id': 'high_importance_channel',
                'channel_id_v1': 'urbi_connect_alerts_channel_v1',
                'android_channel_id_v1': 'urbi_connect_alerts_channel_v1',
                'click_action': 'FLUTTER_NOTIFICATION_CLICK',
                'icon': 'ic_launcher',
                'notification_priority': 'PRIORITY_HIGH',
                'default_sound': true,
                'default_vibrate_timings': true,
              },
            },
            'apns': {
              'headers': {
                'apns-priority': '10',
              },
              'payload': {
                'aps': {
                  'alert': {
                    'title': title,
                    'body': body,
                  },
                  'sound': 'default',
                  'content-available': 1,
                  'badge': 1,
                },
              },
            },
          };

          notificationDoc['click_action'] = 'FLUTTER_NOTIFICATION_CLICK';
          notificationDoc['clickAction'] = 'FLUTTER_NOTIFICATION_CLICK';
          notificationDoc['sound'] = 'default';
          notificationDoc['priority'] = 'high';
          notificationDoc['android_channel_id'] = 'high_importance_channel';
          notificationDoc['notification_channel_id'] =
              'high_importance_channel';
          notificationDoc['channelId'] = 'high_importance_channel';
          notificationDoc['channel_id'] = 'high_importance_channel';
          notificationDoc['android_channel_id_v1'] =
              'urbi_connect_alerts_channel_v1';
          notificationDoc['notification_channel_id_v1'] =
              'urbi_connect_alerts_channel_v1';
          notificationDoc['channelId_v1'] = 'urbi_connect_alerts_channel_v1';
          notificationDoc['channel_id_v1'] = 'urbi_connect_alerts_channel_v1';
          notificationDoc['importance'] = 'max';
          notificationDoc['high_importance'] = true;
          notificationDoc['badge'] = 1;
          notificationDoc['badge_count'] = 1;
          notificationDoc['icon'] = 'ic_launcher';
        }

        batch.set(notifRef, notificationDoc);
      }

      await batch.commit();
      debugPrint('Broadcast enviado a ${targetUsers.length} usuarios.');
    } catch (e) {
      debugPrint('Error en broadcast: $e');
      rethrow;
    }
  }

  // Iniciar la escucha en tiempo real de notificaciones en Firestore
  void _startListeningToFirestoreNotifications(String userId) {
    _notifSubscription?.cancel();
    _listenerStartTime = DateTime.now();
    debugPrint(
        'Iniciando listener en tiempo real de Firestore para Notificaciones del usuario: $userId a partir de $_listenerStartTime');

    bool isFirstSnapshot = true;

    _notifSubscription = _db
        .collection('Notificaciones')
        .where('id_usuario', whereIn: [userId, 'silenciado_$userId'])
        .snapshots()
        .listen((QuerySnapshot snapshot) async {
          if (isFirstSnapshot) {
            // En el primer snapshot, registramos los documentos existentes para evitar
            // alertas de histórico (antiguas de sesiones previas).
            for (var doc in snapshot.docs) {
              _notifiedDocIds.add(doc.id);
            }
            isFirstSnapshot = false;
            debugPrint(
                'Primer snapshot de notificaciones cargado. Ignorados ${snapshot.docs.length} registros del histórico.');
            return;
          }

          for (var change in snapshot.docChanges) {
            if (change.type == DocumentChangeType.added) {
              final doc = change.doc;

              // Si ya la notificamos o estaba en el snapshot inicial, la saltamos
              if (_notifiedDocIds.contains(doc.id)) {
                continue;
              }

              final docData = doc.data() as Map<String, dynamic>?;
              if (docData != null) {
                // Evitar mostrar notificaciones que se crearon en el pasado (históricas)
                final dynamic rawStamp =
                    docData['fecha_creacion'] ?? docData['createdAt'];
                if (rawStamp is Timestamp) {
                  final DateTime createTime = rawStamp.toDate();
                  final DateTime threshold =
                      _listenerStartTime.subtract(const Duration(seconds: 30));
                  if (createTime.isBefore(threshold)) {
                    debugPrint(
                        'Ignorando notificación antigua (fecha $createTime anterior a la sesión de escucha)');
                    _notifiedDocIds.add(doc.id);
                    continue;
                  }
                }

                final bool isUnread =
                    docData['leido'] == false || docData['isRead'] == false;

                if (isUnread) {
                  _notifiedDocIds.add(doc.id);
                  final bool enabled =
                      await _isPushNotificationEnabledForDoc(docData);
                  if (enabled) {
                    _showLocalNotificationForDoc(doc.id, docData);
                  } else {
                    debugPrint(
                        'Notificación filtrada por ajustes de rol del usuario.');
                  }
                }
              }
            }
          }
        }, onError: (e) {
          debugPrint(
              'Error en el listener de notificaciones en tiempo real: $e');
        });
  }

  // Filtrar si el rol destinatario está activado por el usuario
  Future<bool> _isPushNotificationEnabledForDoc(
      Map<String, dynamic> docData) async {
    try {
      final String idUsuario =
          (docData['id_usuario'] ?? docData['userId'] ?? '').toString();
      if (idUsuario.startsWith('silenciado_')) {
        return false; // Silenciado de inmediato y sin excepciones
      }

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return true;

      final profileDoc = await _db.collection('users').doc(user.uid).get();
      if (!profileDoc.exists) return true;

      final data = profileDoc.data();
      if (data == null) return true;

      final List<dynamic> enabledPushRoles =
          data.containsKey('enabled_push_roles')
              ? List.from(data['enabled_push_roles'])
              : ['admin', 'responsable', 'ciudadano'];

      final type = docData['tipo'] ?? docData['type'] ?? '';
      final title = docData['titulo'] ?? docData['title'] ?? '';
      final body = docData['mensaje'] ?? docData['body'] ?? '';

      List<String>? destList;
      if (docData['destinatarios'] != null) {
        if (docData['destinatarios'] is List) {
          destList = List<String>.from(
              docData['destinatarios'].map((e) => e.toString()));
        } else if (docData['destinatarios'] is String) {
          final str = docData['destinatarios'].toString().trim();
          if (str.startsWith('[') && str.endsWith(']')) {
            final content = str.substring(1, str.length - 1);
            destList = content
                .split(',')
                .map((s) => s.replaceAll('"', '').replaceAll('\'', '').trim())
                .toList();
          } else {
            destList = str.split(',').map((s) => s.trim()).toList();
          }
        }
      }

      String targetRole = _determineTargetRole(
        type: type,
        title: title,
        body: body,
        destinatarios: destList,
        isAdminNotification: docData['is_admin_notification'] == true,
      );

      return _isRoleEnabled(enabledPushRoles, targetRole);
    } catch (e) {
      debugPrint('Error filtrando notificación Firestore en primer plano: $e');
      return true;
    }
  }

  // Mostrar notificación local en la bandeja del dispositivo o como banner en Web
  void _showLocalNotificationForDoc(
      String docId, Map<String, dynamic> docData) {
    try {
      final String title =
          docData['titulo'] ?? docData['title'] ?? 'UrbiConnect';
      final String body = docData['mensaje'] ?? docData['body'] ?? '';
      final String refId =
          docData['id_referencia'] ?? docData['referenceId'] ?? '';
      final String type = docData['tipo'] ?? docData['type'] ?? '';

      if (kIsWeb) {
        _showInAppWebNotification(title, body, refId, type);
        return;
      }

      final payload = {
        'referenceId': refId,
        'type': type,
      };

      _localNotifications.show(
        docId.hashCode,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'urbi_connect_alerts_channel_v1',
            'UrbiConnect Notificaciones',
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
          ),
        ),
        payload: jsonEncode(payload),
      );
      debugPrint(
          'Notificación local mostrada con éxito para el documento: $docId');
    } catch (e) {
      debugPrint('Error al mostrar notificación local: $e');
    }
  }

  // Mostrar una hermosa notificación tipo Toast/SnackBar flotante interactiva en Web
  void _showInAppWebNotification(
      String title, String body, String? refId, String? type) {
    final context = navigatorKey.currentContext;
    if (context == null) {
      debugPrint(
          'No se pudo mostrar la notificación en la web porque el context es nulo.');
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: InkWell(
          onTap: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            _handleLocalNavigation(context, refId, type);
          },
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Colors.white24,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  type == 'chat'
                      ? Icons.chat_bubble
                      : Icons.notifications_active,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Colors.white),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios,
                color: Colors.white30,
                size: 14,
              ),
            ],
          ),
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 10),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        backgroundColor: Colors.blueGrey[900],
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  // Manejar navegación cuando se hace click en la notificación local
  Future<void> _handleLocalNavigation(
      BuildContext context, String? referenceId, String? type) async {
    if (referenceId == null || referenceId.isEmpty) return;

    // Marcar como leída la notificación en el buzón automáticamente al abrirla desde una notificación local
    await markNotificationsAsReadForReference(referenceId, type);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final bool isSuper =
            user.email?.toLowerCase() == AppConfig.superUserEmail.toLowerCase();

        if (isSuper && referenceId.isNotEmpty) {
          if (type == 'chat') {
            final incidentDoc =
                await _db.collection('Incidencia').doc(referenceId).get();
            if (incidentDoc.exists) {
              final String creatorId = incidentDoc.get('id_usuario') ?? '';
              if (creatorId == user.uid) {
                SuperuserSession.simulatedRole = 'ciudadano';
              } else {
                SuperuserSession.simulatedRole = 'responsable';
              }
            }
          } else if (type == 'soporte' || type == 'chat_soporte') {
            SuperuserSession.simulatedRole = 'admin';
          } else if (type == 'incidencia' ||
              type == 'incidencia_editada' ||
              type == 'recordatorio' ||
              type == 'incidencia_eliminada') {
            if (type == 'recordatorio') {
              SuperuserSession.simulatedRole = 'responsable';
            } else {
              final incidentDoc =
                  await _db.collection('Incidencia').doc(referenceId).get();
              if (incidentDoc.exists) {
                final String creatorId = incidentDoc.get('id_usuario') ?? '';
                if (creatorId == user.uid) {
                  SuperuserSession.simulatedRole = 'ciudadano';
                } else {
                  SuperuserSession.simulatedRole = 'responsable';
                }
              } else {
                if (type == 'incidencia') {
                  SuperuserSession.simulatedRole = 'responsable';
                } else {
                  SuperuserSession.simulatedRole = 'ciudadano';
                }
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error en la conmutación previa de rol: $e');
    }

    if (type == 'chat') {
      Navigator.push(
        context,
        MaterialPageRoute(
            builder: (context) => ChatScreen(incidentId: referenceId)),
      );
    } else if (type == 'soporte' || type == 'chat_soporte') {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final profileDoc = await _db.collection('users').doc(user.uid).get();
      final bool isDbAdmin = profileDoc.exists &&
          (profileDoc.get('rol') ?? '').toString().toLowerCase() == 'admin';

      final activeRole = SuperuserSession.activeRole.toLowerCase();
      final bool isSuper =
          user.email?.toLowerCase() == AppConfig.superUserEmail.toLowerCase();
      final bool resolvedIsAdmin =
          isSuper ? (activeRole == 'admin') : isDbAdmin;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => SupportChatScreen(
              ticketId: referenceId, isAdmin: resolvedIsAdmin),
        ),
      );
    } else if (type == 'incidencia' ||
        type == 'incidencia_editada' ||
        type == 'recordatorio' ||
        type == 'incidencia_eliminada') {
      final incidentDoc =
          await _db.collection('Incidencia').doc(referenceId).get();
      if (!incidentDoc.exists) return;

      final incident = Incident.fromFirestore(incidentDoc);

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final profileDoc = await _db.collection('users').doc(user.uid).get();
      if (!profileDoc.exists) return;

      final profile = UserProfile.fromMap(profileDoc.data()!, user.uid);
      final bool isSuper =
          user.email?.toLowerCase() == AppConfig.superUserEmail.toLowerCase();
      final activeRole = isSuper
          ? SuperuserSession.activeRole.toLowerCase()
          : profile.role.toLowerCase();

      if (activeRole == 'responsable' ||
          activeRole == 'responsable municipal') {
        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (context) =>
                  ResponsibleIncidentDetailScreen(incident: incident)),
        );
      } else {
        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (context) => IncidentDetailScreen(incident: incident)),
        );
      }
    }
  }
}
