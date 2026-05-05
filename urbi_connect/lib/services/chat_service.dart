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
      // Ordenar por fecha descendente (más recientes primero) para usar reverse: true
      messages.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return messages;
    });
  }

  // Enviar mensaje
  Future<void> sendMessage(String incidentId, String senderId, String text,
      {String? imageUrl}) async {
    await _db.collection('Mensajes_Chat').add({
      'id_incidencia': incidentId,
      'emisor_id': senderId,
      'texto': text,
      'url_imagen': imageUrl,
      'fecha': FieldValue.serverTimestamp(),
    });

    // Actualizar fecha de la incidencia para que suba en el centro de mensajes
    await _db.collection('Incidencia').doc(incidentId).update({
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
          // Buscamos responsables que tengan esta categoría (probamos ambos campos por compatibilidad)
          var responsables = await _db
              .collection('users')
              .where('rol', whereIn: [
                'responsable',
                'responsable municipal',
                'Responsable',
                'Responsable Municipal'
              ])
              .where('id_categorias', arrayContains: categoryId)
              .get();

          if (responsables.docs.isEmpty) {
            // Intentar con el campo singular si el plural falla
            responsables = await _db
                .collection('users')
                .where('rol', whereIn: [
                  'responsable',
                  'responsable municipal',
                  'Responsable',
                  'Responsable Municipal'
                ])
                .where('id_categoria', isEqualTo: categoryId)
                .get();
          }

          if (responsables.docs.isNotEmpty) {
            targetUserId = responsables.docs.first.id;
          }
        } else {
          // El responsable envió el mensaje, notificar al ciudadano
          targetUserId = citizenId;
        }

        if (targetUserId.isNotEmpty) {
          await _notificationService.sendNotification(
            userId: targetUserId,
            title: 'Nuevo mensaje en chat',
            body: imageUrl != null
                ? '📷 Foto enviada'
                : (text.length > 50 ? '${text.substring(0, 47)}...' : text),
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
