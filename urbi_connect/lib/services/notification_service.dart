import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:urbi_connect/models/notification.dart';

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

  // Eliminar notificaciones de más de 2 semanas
  Future<void> _deleteOldNotifications() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final twoWeeksAgo = DateTime.now().subtract(const Duration(days: 14));
      final oldNotifications = await _db
          .collection('Notificaciones')
          .where('id_usuario', isEqualTo: user.uid)
          .where('fecha_creacion', isLessThan: Timestamp.fromDate(twoWeeksAgo))
          .get();

      if (oldNotifications.docs.isNotEmpty) {
        final batch = _db.batch();
        for (var doc in oldNotifications.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
        debugPrint(
            'Se han eliminado ${oldNotifications.docs.length} notificaciones antiguas.');
      }
    } catch (e) {
      debugPrint('Error al limpiar notificaciones antiguas: $e');
    }
  }

  // Stream de notificaciones del buzón
  Stream<List<AppNotification>> getNotifications(String userId) {
    return _db
        .collection('Notificaciones')
        .where('id_usuario', isEqualTo: userId)
        .snapshots()
        .map((snapshot) {
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
        .map((snapshot) => snapshot.docs.length);
  }

  // Enviar notificación manual
  Future<void> sendNotification({
    required String userId,
    required String title,
    required String body,
    String? referenceId,
    String? type,
  }) {
    return _db.collection('Notificaciones').add({
      'id_usuario': userId,
      'titulo': title,
      'mensaje': body,
      'fecha_creacion': FieldValue.serverTimestamp(),
      'leido': false,
      'id_referencia': referenceId,
      'tipo': type,
    });
  }
}
