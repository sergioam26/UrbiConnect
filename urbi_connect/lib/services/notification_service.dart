import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:urbi_connect/models/incident.dart';
import 'package:urbi_connect/models/notification.dart';
import 'package:urbi_connect/models/user_profile.dart';
import 'package:urbi_connect/screens/incidents/chat_screen.dart';
import 'package:urbi_connect/screens/incidents/incident_detail_screen.dart';
import 'package:urbi_connect/screens/incidents/responsible_incident_detail_screen.dart';
import 'package:urbi_connect/screens/support/support_chat_screen.dart';

class NotificationService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  // Inicializar notificaciones push
  Future<void> initNotifications() async {
    if (kIsWeb) {
      debugPrint('Notificaciones Push desactivadas en Web.');
      return;
    }

    // Configuración para Android
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'high_importance_channel', // id
      'UrbiConnect Notificaciones', // title
      description:
          'Este canal se usa para notificaciones importantes.', // description
      importance: Importance.max,
    );

    // Crear el canal en el dispositivo
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // Configuración para notificaciones locales (primer plano)
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);

    await _localNotifications.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        // Aquí podrías manejar el clic en la notificación local
        debugPrint('Notificación local clickeada: ${response.payload}');
      },
    );

    NotificationSettings settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      String? token = await _fcm.getToken();
      debugPrint('FCM Token: $token');

      final user = FirebaseAuth.instance.currentUser;
      if (user != null && token != null) {
        await _db.collection('users').doc(user.uid).update({
          'fcm_token': token,
          'last_token_update': FieldValue.serverTimestamp(),
        });
      }
    }

    // Manejar mensajes en primer plano
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      RemoteNotification? notification = message.notification;
      AndroidNotification? android = message.notification?.android;

      if (notification != null && android != null && !kIsWeb) {
        _localNotifications.show(
          notification.hashCode,
          notification.title,
          notification.body,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'high_importance_channel',
              'UrbiConnect Notificaciones',
              importance: Importance.max,
              priority: Priority.high,
              icon: '@mipmap/ic_launcher',
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

    if (referenceId == null || referenceId.isEmpty) return;

    try {
      if (type == 'chat') {
        if (context.mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => ChatScreen(incidentId: referenceId)),
          );
        }
      } else if (type == 'soporte' || type == 'chat_soporte') {
        final profileDoc = await _db
            .collection('users')
            .doc(FirebaseAuth.instance.currentUser?.uid ?? '')
            .get();
        final isAdmin = profileDoc.exists &&
            (profileDoc.get('rol') ?? '').toString().toLowerCase() == 'admin';

        if (context.mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  SupportChatScreen(ticketId: referenceId, isAdmin: isAdmin),
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
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) return;

        final profileDoc = await _db.collection('users').doc(user.uid).get();
        if (!profileDoc.exists) return;

        final profile = UserProfile.fromMap(profileDoc.data()!, user.uid);

        if (context.mounted) {
          final String role = profile.role.toLowerCase();
          if (role == 'responsable' || role == 'responsable municipal') {
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

  // Actualizar el token del dispositivo en Firestore
  Future<void> updateTokenInFirestore() async {
    if (kIsWeb) return;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        NotificationSettings settings = await _fcm.getNotificationSettings();
        if (settings.authorizationStatus == AuthorizationStatus.notDetermined) {
          settings = await _fcm.requestPermission();
        }

        if (settings.authorizationStatus == AuthorizationStatus.authorized ||
            settings.authorizationStatus == AuthorizationStatus.provisional) {
          // FORZAMOS LA REGENERACIÓN DEL TOKEN
          // Borramos el token actual para obligar a Firebase a darnos uno nuevo y válido
          await _fcm.deleteToken();

          String? token = await _fcm.getToken();
          if (token != null) {
            await _db.collection('users').doc(user.uid).set({
              'fcm_token': token,
              'last_token_update': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
            debugPrint('NUEVO FCM Token generado y guardado para ${user.uid}');
          }
        }
      }
    } catch (e) {
      debugPrint('Error al actualizar fcm_token: $e');
    }
  }

  // Eliminar notificaciones de más de 2 semanas (desactivado borrado físico)
  Future<void> _deleteOldNotifications() async {
    debugPrint(
        'Exigencia del cliente: Borrado físico de notificaciones antiguas desactivado.');
  }

  // Stream de notificaciones del buzón
  Stream<List<AppNotification>> getNotifications(String userId) {
    return _db
        .collection('Notificaciones')
        .where('id_usuario', isEqualTo: userId)
        .snapshots()
        .map((snapshot) {
      final twentyOneDaysAgo =
          DateTime.now().subtract(const Duration(days: 21));
      final notifications = snapshot.docs
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
        .where('id_usuario', isEqualTo: userId)
        .where('leido', isEqualTo: false)
        .snapshots()
        .map((snapshot) {
      final twentyOneDaysAgo =
          DateTime.now().subtract(const Duration(days: 21));
      return snapshot.docs.where((doc) {
        try {
          final timestamp = doc.get('fecha_creacion') as Timestamp?;
          if (timestamp == null) return false;
          return timestamp.toDate().isAfter(twentyOneDaysAgo);
        } catch (_) {
          return false;
        }
      }).length;
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
  }) {
    return _db.collection('Notificaciones').add({
      'id_usuario': userId,
      'titulo': title,
      'mensaje': body,
      'fecha_creacion': FieldValue.serverTimestamp(),
      'leido': false,
      'id_referencia': referenceId,
      'tipo': type,
      'es_oficial': esOficial,
      'url_imagen': imageUrl,
    });
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
      final usersSnapshot =
          await _db.collection('users').where('rol', whereIn: roles).get();

      final batch = _db.batch();

      for (var doc in usersSnapshot.docs) {
        // No enviar notificación al admin que la envía
        if (doc.id == currentUserId) continue;

        final notifRef = _db.collection('Notificaciones').doc();
        batch.set(notifRef, {
          'id_usuario': doc.id,
          'titulo': title,
          'mensaje': body,
          'fecha_creacion': FieldValue.serverTimestamp(),
          'leido': false,
          'tipo': 'broadcast',
          'es_oficial': true,
          'destinatarios': roles,
          'url_imagen': imageUrl,
        });
      }

      await batch.commit();
      debugPrint('Broadcast enviado a ${usersSnapshot.docs.length} usuarios.');
    } catch (e) {
      debugPrint('Error en broadcast: $e');
      rethrow;
    }
  }
}
