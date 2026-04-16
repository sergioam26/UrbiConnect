import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:urbi_connect/models/chat_message.dart';
import 'package:urbi_connect/services/notification_service.dart';

class ChatService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final NotificationService _notificationService = NotificationService();

  // Obtener mensajes de una incidencia
  Stream<List<ChatMessage>> getMessages(String incidentId) {
    return _db
        .collection('Mensajes_Chat')
        .where('id_incidencia', isEqualTo: incidentId)
        .snapshots()
        .map((snapshot) {
      final messages =
          snapshot.docs.map((doc) => ChatMessage.fromFirestore(doc)).toList();
      // Ordenar por fecha ascendente para el chat
      messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return messages;
    });
  }

  // Enviar mensaje
  Future<void> sendMessage(
      String incidentId, String senderId, String text) async {
    await _db.collection('Mensajes_Chat').add({
      'id_incidencia': incidentId,
      'emisor_id': senderId,
      'texto': text,
      'fecha': FieldValue.serverTimestamp(),
    });

    // Notificar a la otra parte
    try {
      final incidentDoc =
          await _db.collection('Incidencia').doc(incidentId).get();
      if (incidentDoc.exists) {
        final citizenId = incidentDoc.get('id_usuario');
        final categoryId = incidentDoc.get('id_categoria');

        String targetUserId = '';

        if (senderId == citizenId) {
          // El ciudadano envió el mensaje, notificar al responsable
          final responsables = await _db
              .collection('users')
              .where('rol', whereIn: ['Responsable', 'Responsable Municipal'])
              .where('id_categorias', arrayContains: categoryId)
              .get();

          if (responsables.docs.isNotEmpty) {
            targetUserId = responsables
                .docs.first.id; // Notificamos al primero por simplicidad
          }
        } else {
          // El responsable envió el mensaje, notificar al ciudadano
          targetUserId = citizenId;
        }

        if (targetUserId.isNotEmpty) {
          await _notificationService.sendNotification(
            userId: targetUserId,
            title: 'Nuevo mensaje en chat',
            body: text.length > 50 ? '${text.substring(0, 47)}...' : text,
            referenceId: incidentId,
            type: 'chat',
          );
        }
      }
    } catch (e) {
      debugPrint('Error enviando notificación de chat: $e');
    }
  }
}
