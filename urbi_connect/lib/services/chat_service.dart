import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:urbi_connect/config/app_config.dart';
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

        final Set<String> targetUserIds = {};
        List<String> destinatariosList = ['ciudadano'];

        if (senderId == citizenId) {
          // El ciudadano envió el mensaje, notificar al responsable
          destinatariosList = ['responsable'];

          // Buscamos responsables que tengan esta categoría (probamos ambos campos por compatibilidad)
          final responsablesPlural = await _db
              .collection('users')
              .where('rol', whereIn: [
                'responsable',
                'responsable municipal',
                'Responsable',
                'Responsable Municipal'
              ])
              .where('id_categorias', arrayContains: categoryId)
              .get();

          for (var doc in responsablesPlural.docs) {
            targetUserIds.add(doc.id);
          }

          final responsablesSingular = await _db
              .collection('users')
              .where('rol', whereIn: [
                'responsable',
                'responsable municipal',
                'Responsable',
                'Responsable Municipal'
              ])
              .where('id_categoria', isEqualTo: categoryId)
              .get();

          for (var doc in responsablesSingular.docs) {
            targetUserIds.add(doc.id);
          }

          // Integrar al súper usuario si tiene activo el rol/notificaciones de responsable
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
              if (!targetUserIds.contains(superUserDoc.id)) {
                // Se agrega al súper usuario incondicionalmente en base de datos para que reciba las notificaciones en su buzón durante las pruebas.
                targetUserIds.add(superUserDoc.id);
              }
            }
          } catch (e) {
            debugPrint(
                'Error integrando súper usuario responsable en chat: $e');
          }

          // Fallback final por si no se encontrara a nadie
          if (targetUserIds.isEmpty) {
            final superuserSnap = await _db
                .collection('users')
                .where('email', whereIn: [
                  AppConfig.superUserEmail.toLowerCase(),
                  AppConfig.superUserEmail.toUpperCase(),
                  AppConfig.superUserEmail,
                  'Sergioalgmir@gmail.com',
                  'SergioAlgmir@gmail.com',
                  'SERGIOALGMIR@GMAIL.COM',
                ])
                .limit(1)
                .get();
            if (superuserSnap.docs.isNotEmpty) {
              targetUserIds.add(superuserSnap.docs.first.id);
            }
          }
        } else {
          // El responsable envió el mensaje, notificar al ciudadano
          if (citizenId.isNotEmpty) {
            targetUserIds.add(citizenId);
          }
          destinatariosList = ['ciudadano'];
        }

        for (var targetUserId in targetUserIds) {
          await _notificationService.sendNotification(
            userId: targetUserId,
            title: 'Nuevo mensaje en chat',
            body: imageUrl != null
                ? '📷 Foto enviada'
                : (text.length > 50 ? '${text.substring(0, 47)}...' : text),
            referenceId: incidentId,
            type: 'chat',
            destinatarios: destinatariosList,
          );
        }
      }
    } catch (e) {
      debugPrint('Error enviando notificación de chat: $e');
    }
  }
}
