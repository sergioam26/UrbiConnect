import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:urbi_connect/services/notification_service.dart';

class SupportService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final NotificationService _notificationService = NotificationService();

  // Crear ticket de soporte
  Future<void> createSupportTicket(String description) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final docRef = await _db.collection('Soporte').add({
      'id_usuario': user.uid,
      'descripcion': description,
      'fecha': FieldValue.serverTimestamp(),
      'estado': 'Abierto',
    });

    // Notificar a los administradores
    try {
      final admins =
          await _db.collection('users').where('rol', isEqualTo: 'Admin').get();
      for (var doc in admins.docs) {
        await _notificationService.sendNotification(
          userId: doc.id,
          title: 'Nuevo ticket de soporte',
          body: 'Un usuario ha reportado un problema: $description',
          referenceId: docRef.id,
          type: 'soporte',
        );
      }
    } catch (e) {
      debugPrint('Error notificando soporte a admins: $e');
    }
  }

  // Stream de tickets para un usuario
  Stream<QuerySnapshot> getUserTickets(String uid) {
    return _db
        .collection('Soporte')
        .where('id_usuario', isEqualTo: uid)
        .orderBy('fecha', descending: true)
        .snapshots();
  }

  // Stream de todos los tickets para admin
  Stream<QuerySnapshot> getAllTickets() {
    return _db
        .collection('Soporte')
        .orderBy('fecha', descending: true)
        .snapshots();
  }

  // Actualizar estado de ticket
  Future<void> updateTicketStatus(String ticketId, String status) async {
    await _db.collection('Soporte').doc(ticketId).update({'estado': status});
  }

  // Enviar mensaje en el chat de soporte
  Future<void> sendSupportMessage(
      String ticketId, String senderId, String text) async {
    await _db.collection('Soporte').doc(ticketId).collection('Chat').add({
      'id_emisor': senderId,
      'mensaje': text,
      'fecha': FieldValue.serverTimestamp(),
    });

    // Notificar a la otra parte
    try {
      final ticket = await _db.collection('Soporte').doc(ticketId).get();
      final userId = ticket.get('id_usuario');
      final targetId = (senderId == userId) ? await _getAdminId() : userId;

      if (targetId != null) {
        await _notificationService.sendNotification(
          userId: targetId,
          title: 'Nuevo mensaje en soporte',
          body: text,
          referenceId: ticketId,
          type: 'chat_soporte',
        );
      }
    } catch (e) {
      debugPrint('Error notificando mensaje de soporte: $e');
    }
  }

  Future<String?> _getAdminId() async {
    final admins = await _db
        .collection('users')
        .where('rol', isEqualTo: 'Admin')
        .limit(1)
        .get();
    if (admins.docs.isNotEmpty) return admins.docs.first.id;
    return null;
  }
}
