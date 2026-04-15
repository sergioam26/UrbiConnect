import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:urbi_connect/models/notification.dart';

class NotificationService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;

  // Inicializar notificaciones push
  Future<void> initNotifications() async {
    NotificationSettings settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      String? token = await _fcm.getToken();
      debugPrint('FCM Token: $token');
      // Aquí se guardaría el token en Firestore asociado al usuario
    }
  }

  // Stream de notificaciones del buzón
  Stream<List<AppNotification>> getNotifications(String userId) {
    return _db
        .collection('Notificaciones')
        .where('id_usuario', isEqualTo: userId)
        .orderBy('fecha_creacion', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => AppNotification.fromFirestore(doc))
            .toList());
  }

  // Marcar como leída
  Future<void> markAsRead(String id) {
    return _db.collection('Notificaciones').doc(id).update({'leido': true});
  }
}
