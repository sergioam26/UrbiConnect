import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:urbi_connect/services/notification_service.dart';

enum OperationType {
  create,
  update,
  delete,
  list,
  get,
  write,
}

class SupportService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final NotificationService _notificationService = NotificationService();

  void _handleFirestoreError(Object error, OperationType type, String path) {
    final user = FirebaseAuth.instance.currentUser;
    final errInfo = {
      'error': error.toString(),
      'operationType': type.toString().split('.').last.toLowerCase(),
      'path': path,
      'authInfo': {
        'userId': user?.uid,
        'email': user?.email,
        'emailVerified': user?.emailVerified,
      }
    };
    final jsonErr = jsonEncode(errInfo);
    debugPrint('Firestore Error: $jsonErr');
    throw Exception(jsonErr);
  }

  // Helper para manejar timeouts y errores de red
  Future<T> _withTimeout<T>(Future<T> operation, {String? actionName}) async {
    try {
      return await operation.timeout(
        const Duration(seconds: 5),
        onTimeout: () =>
            throw Exception('Conexión lenta. Por favor, espera un momento.'),
      );
    } catch (e) {
      debugPrint('Error en ${actionName ?? 'soporte'}: $e');
      if (e.toString().contains('network-request-failed') ||
          e.toString().contains('unavailable')) {
        throw Exception(
            'Sin conexión. La operación se completará al recuperar la red.');
      }
      rethrow;
    }
  }

  // Crear ticket de soporte
  Future<String> createSupportTicket(String description,
      {String? imageUrl}) async {
    return _withTimeout(() async {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return '';

      try {
        final docRef = await _db.collection('Soporte').add({
          'id_usuario': user.uid,
          'descripcion': description,
          'url_imagen': imageUrl,
          'fecha': FieldValue.serverTimestamp(),
          'estado': 'Abierto',
          'iniciado_por_admin': false,
          'admin_leido': false,
          'not_admin_leido': true,
        });

        if (imageUrl != null || description.isNotEmpty) {
          await docRef.collection('Chat').add({
            'id_emisor': user.uid,
            'mensaje': description,
            'url_imagen': imageUrl,
            'fecha': FieldValue.serverTimestamp(),
          });
        }

        // Notificar a los administradores (Background)
        _notifyAdmins('Nuevo ticket de soporte',
            'Un usuario ha reportado un problema: $description', docRef.id);

        return docRef.id;
      } catch (e) {
        _handleFirestoreError(e, OperationType.write, 'Soporte');
        return '';
      }
    }(), actionName: 'Crear ticket');
  }

  void _notifyAdmins(String title, String body, String id) async {
    try {
      final admins = await _db
          .collection('users')
          .where('rol', whereIn: ['Admin', 'admin']).get();
      for (var doc in admins.docs) {
        await _notificationService.sendNotification(
          userId: doc.id,
          title: title,
          body: body,
          referenceId: id,
          type: 'soporte',
        );
      }
    } catch (e) {
      debugPrint('Error notificando soporte a admins: $e');
    }
  }

  // Iniciar chat desde Admin
  Future<String> startAdminChat(String targetUserId, String message,
      {String? imageUrl}) async {
    final admin = FirebaseAuth.instance.currentUser;
    if (admin == null) return '';

    try {
      final docRef = await _db.collection('Soporte').add({
        'id_usuario': targetUserId,
        'descripcion': message.isNotEmpty ? message : 'Envío de imagen',
        'url_imagen': imageUrl,
        'fecha': FieldValue.serverTimestamp(),
        'estado': 'Abierto',
        'iniciado_por_admin': true,
        'admin_leido': true,
        'not_admin_leido': false,
      });

      // Primer mensaje
      await docRef.collection('Chat').add({
        'id_emisor': admin.uid,
        'mensaje': message,
        'url_imagen': imageUrl,
        'fecha': FieldValue.serverTimestamp(),
      });

      // Notificar al ciudadano
      await _notificationService.sendNotification(
        userId: targetUserId,
        title: 'Mensaje de administración',
        body: message,
        referenceId: docRef.id,
        type: 'chat_soporte',
      );

      return docRef.id;
    } catch (e) {
      _handleFirestoreError(e, OperationType.write, 'Soporte');
      return '';
    }
  }

  // Crear ticket para usuario no autenticado (Invitado)
  Future<void> createGuestSupportTicket({
    required String name,
    required String surname,
    required String email,
    required String message,
    String? imageUrl,
  }) async {
    try {
      final docRef = await _db.collection('Soporte').add({
        'nombre_invitado': name,
        'apellidos_invitado': surname,
        'email_invitado': email,
        'descripcion': message,
        'url_imagen': imageUrl,
        'fecha': FieldValue.serverTimestamp(),
        'estado':
            'Cerrado', // Permanecerá cerrado hasta que el administrador responda
        'es_invitado': true,
        'iniciado_por_admin': false,
        'admin_leido': false,
        'not_admin_leido': true,
      });

      if (imageUrl != null || message.isNotEmpty) {
        await docRef.collection('Chat').add({
          'id_emisor': 'guest',
          'mensaje': message,
          'url_imagen': imageUrl,
          'fecha': FieldValue.serverTimestamp(),
        });
      }

      // Notificar a admins
      try {
        final admins = await _db
            .collection('users')
            .where('rol', whereIn: ['Admin', 'admin']).get();
        for (var admin in admins.docs) {
          await _notificationService.sendNotification(
            userId: admin.id,
            title: 'Nuevo ticket de invitado',
            body: 'Invitado $name $surname ha enviado un ticket: $message',
            referenceId: docRef.id,
            type: 'soporte',
          );
        }
      } catch (e) {
        debugPrint('Error notificando soporte de invitado a admins: $e');
      }
    } catch (e) {
      _handleFirestoreError(e, OperationType.write, 'Soporte');
    }
  }

  // Stream de tickets para un usuario
  Stream<QuerySnapshot> getUserTickets(String uid) {
    return _db
        .collection('Soporte')
        .where('id_usuario', isEqualTo: uid)
        .snapshots()
        .handleError(
            (e) => _handleFirestoreError(e, OperationType.list, 'Soporte'));
  }

  // Stream de todos los tickets para admin
  Stream<QuerySnapshot> getAllTickets() {
    return _db.collection('Soporte').snapshots().handleError(
        (e) => _handleFirestoreError(e, OperationType.list, 'Soporte'));
  }

  // Stream de tickets para admin sin filtros complejos para evitar errores de índice
  Stream<QuerySnapshot> getAdminTickets() {
    return _db
        .collection('Soporte')
        .orderBy('fecha', descending: true)
        .snapshots()
        .handleError((e) {
      debugPrint('Error en getAdminTickets: $e');
      return const Stream.empty();
    });
  }

  // Marcar como leído
  Future<void> markAsRead(String ticketId, bool isAdmin) async {
    try {
      await _db.collection('Soporte').doc(ticketId).update({
        isAdmin ? 'admin_leido' : 'not_admin_leido': true,
      });
    } catch (e) {
      debugPrint('Error al marcar soporte como leído: $e');
    }
  }

  // Actualizar estado de ticket
  Future<void> updateTicketStatus(String ticketId, String status) async {
    try {
      final Map<String, dynamic> updates = {'estado': status};
      if (status == 'Cerrado') {
        updates['fecha_cierre'] = FieldValue.serverTimestamp();
      }

      await _db.collection('Soporte').doc(ticketId).update(updates);

      // Notificar al usuario del cambio de estado
      try {
        final ticket = await _db.collection('Soporte').doc(ticketId).get();
        final userId = ticket.get('id_usuario');

        await _notificationService.sendNotification(
          userId: userId,
          title: 'Actualización de soporte',
          body:
              'El estado de tu ticket #${ticketId.substring(0, 5).toUpperCase()} ha cambiado a: $status',
          referenceId: ticketId,
          type: 'soporte',
        );
      } catch (e) {
        debugPrint('Error notificando cambio de estado: $e');
      }
    } catch (e) {
      _handleFirestoreError(e, OperationType.update, 'Soporte/$ticketId');
    }
  }

  // Lógica de limpieza automática según requerimientos
  Future<void> performAutoCleanup() async {
    final now = DateTime.now();

    // 1. Soporte cerrado hace más de 15 días
    final fifteenDaysAgo = now.subtract(const Duration(days: 15));
    final oldTickets = await _db
        .collection('Soporte')
        .where('estado', isEqualTo: 'Cerrado')
        .where('fecha_cierre', isLessThan: Timestamp.fromDate(fifteenDaysAgo))
        .get();

    for (var doc in oldTickets.docs) {
      // Eliminar mensajes del subcollection primero
      final messages = await doc.reference.collection('Chat').get();
      for (var msg in messages.docs) {
        await msg.reference.delete();
      }
      await doc.reference.delete();
    }

    // 2. Incidencias resueltas hace más de 60 días o marcadas como eliminadas
    final sixtyDaysAgo = now.subtract(const Duration(days: 60));

    // Buscar resueltas antiguas
    final oldIncidents = await _db
        .collection('Incidencia')
        .where('estado', isEqualTo: 'Resuelta')
        .where('fecha_resolucion', isLessThan: Timestamp.fromDate(sixtyDaysAgo))
        .get();

    // Buscar eliminadas (soft delete)
    final deletedIncidents = await _db
        .collection('Incidencia')
        .where('es_eliminada', isEqualTo: true)
        .get();

    final allToCleanup = [...oldIncidents.docs, ...deletedIncidents.docs];

    for (var doc in allToCleanup) {
      // Eliminar mensajes de la incidencia (subcolección Chat)
      final messages = await doc.reference.collection('Chat').get();
      for (var msg in messages.docs) {
        await msg.reference.delete();
      }

      // Si estaba resuelta hace 60 días, borramos el documento entero
      // Si está marcada como eliminada (soft delete), borramos el documento entero para limpieza física definitiva
      await doc.reference.delete();
    }

    // 3. Notificaciones enviadas por admin con más de 1 año (para admins)
    // Se gestionará mediante un flag 'oculto_para_admin' o similar si se quiere mantener para el usuario,
    // o borrado físico si es broadcast. El usuario dice "borrar las notificaciones enviadas por el admin de su pantalla de mensajes al año".
    final oneYearAgo = now.subtract(const Duration(days: 365));
    final oldNotifications = await _db
        .collection('Notificaciones')
        .where('tipo', isEqualTo: 'broadcast')
        .where('fecha_creacion', isLessThan: Timestamp.fromDate(oneYearAgo))
        .get();

    for (var doc in oldNotifications.docs) {
      await doc.reference.delete();
    }
  }

  // Enviar mensaje en el chat de soporte
  Future<void> sendSupportMessage(String ticketId, String senderId, String text,
      {String? imageUrl}) async {
    try {
      await _db.collection('Soporte').doc(ticketId).collection('Chat').add({
        'id_emisor': senderId,
        'mensaje': text,
        'url_imagen': imageUrl,
        'fecha': FieldValue.serverTimestamp(),
      });

      // Actualizar flags de lectura y estado si el admin responde
      final ticket = await _db.collection('Soporte').doc(ticketId).get();
      final data = ticket.data() as Map<String, dynamic>;
      final String userId = data['id_usuario'] ?? '';
      final String currentStatus = data['estado'] ?? 'Cerrado';

      bool isSenderAdmin = false;
      if (senderId != userId) {
        final senderDoc = await _db.collection('users').doc(senderId).get();
        if (senderDoc.exists) {
          final String role =
              (senderDoc.get('rol') ?? '').toString().toLowerCase();
          if (role == 'admin') {
            isSenderAdmin = true;
          }
        }
      }

      final Map<String, dynamic> updates = {
        isSenderAdmin ? 'not_admin_leido' : 'admin_leido': false,
        'fecha': FieldValue.serverTimestamp(),
      };

      // Si el admin responde a un ticket cerrado, abrirlo
      if (isSenderAdmin && currentStatus == 'Cerrado') {
        updates['estado'] = 'Abierto';
      }

      await _db.collection('Soporte').doc(ticketId).update(updates);

      // Notificar a la otra parte
      try {
        final targetId = isSenderAdmin ? userId : await _getAdminId();

        if (targetId != null) {
          await _notificationService.sendNotification(
            userId: targetId,
            title: 'Nuevo mensaje en soporte',
            body: imageUrl != null ? '📷 Foto enviada' : text,
            referenceId: ticketId,
            type: 'chat_soporte',
          );
        }
      } catch (e) {
        debugPrint('Error notificando mensaje de soporte: $e');
      }
    } catch (e) {
      _handleFirestoreError(e, OperationType.write, 'Soporte/$ticketId/Chat');
    }
  }

  Future<String?> _getAdminId() async {
    final admins = await _db
        .collection('users')
        .where('rol', whereIn: ['Admin', 'admin'])
        .limit(1)
        .get();
    if (admins.docs.isNotEmpty) return admins.docs.first.id;
    return null;
  }
}
