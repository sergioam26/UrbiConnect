import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:urbi_connect/models/incident.dart';
import 'package:urbi_connect/models/user_profile.dart';
import 'package:urbi_connect/services/notification_service.dart';

class DatabaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final NotificationService _notificationService = NotificationService();

  // Subir imagen a Firebase Storage
  Future<String?> uploadImage(File imageFile) async {
    try {
      String fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
      Reference ref = _storage.ref().child('incidents').child(fileName);
      UploadTask uploadTask = ref.putFile(
        imageFile,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      TaskSnapshot snapshot = await uploadTask;
      return await snapshot.ref.getDownloadURL();
    } catch (e) {
      debugPrint('Error al subir imagen: $e');
      return null;
    }
  }

  // Subir imagen a Firebase Storage (Web)
  Future<String?> uploadImageWeb(Uint8List bytes) async {
    try {
      debugPrint(
          'Iniciando subida de imagen en Web... (${bytes.length} bytes)');
      String fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
      Reference ref = _storage.ref().child('incidents').child(fileName);

      UploadTask uploadTask = ref.putData(
        bytes,
        SettableMetadata(contentType: 'image/jpeg'),
      );

      // Escuchar el progreso para debug
      uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
        double progress =
            100.0 * (snapshot.bytesTransferred / snapshot.totalBytes);
        debugPrint('Progreso de subida: ${progress.toStringAsFixed(2)}%');
      });

      // Añadimos un timeout de 30 segundos para que no se quede colgado para siempre
      TaskSnapshot snapshot = await uploadTask.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          debugPrint('Error: Tiempo de espera agotado al subir la imagen.');
          throw Exception('Timeout');
        },
      );

      String downloadUrl = await snapshot.ref.getDownloadURL();
      debugPrint('Subida completada con éxito. URL: $downloadUrl');
      return downloadUrl;
    } catch (e) {
      debugPrint('Error crítico al subir imagen (Web): $e');
      if (e.toString().contains('CORS')) {
        debugPrint(
            'Detectado posible error de CORS. Revisa la configuración del bucket.');
      }
      return null;
    }
  }

  // Stream de incidencias filtrado por rol
  Stream<List<Incident>> getIncidents(UserProfile profile) {
    // Empezamos con la colección base
    Query query = _db.collection('Incidencia');

    // Filtramos por rol
    final String role = profile.role.toLowerCase();
    if (role == 'ciudadano') {
      query = query.where('id_usuario', isEqualTo: profile.uid);
    } else if (role == 'responsable' || role == 'responsable municipal') {
      if (profile.categories != null && profile.categories!.isNotEmpty) {
        query = query.where('id_categoria', whereIn: profile.categories);
      } else {
        return Stream.value([]);
      }
    }

    return query.snapshots().map((snapshot) {
      final incidents = snapshot.docs
          .map((doc) {
            try {
              final data = doc.data() as Map<String, dynamic>;
              // Filtro manual de eliminadas para soportar documentos antiguos sin el campo
              if (data['es_eliminada'] == true) {
                return null;
              }
              return Incident.fromFirestore(doc);
            } catch (e) {
              debugPrint('Error al parsear incidencia ${doc.id}: $e');
              return null;
            }
          })
          .whereType<Incident>()
          .toList();

      incidents.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return incidents;
    });
  }

  // Obtener perfil de usuario
  Stream<UserProfile?> getUserProfile(String uid) {
    if (uid.isEmpty) return Stream.value(null);
    return _db.collection('users').doc(uid).snapshots().map((doc) {
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final profile = UserProfile.fromMap(data, doc.id);

        // Auto-upgrade project owner to Admin
        if (profile.email == 'sergioalgmir@gmail.com' &&
            profile.role.toLowerCase() != 'admin') {
          _db.collection('users').doc(uid).update({'rol': 'admin'});
        }

        return profile;
      }
      return null;
    }).handleError((error) {
      debugPrint('Error en getUserProfile: $error');
    });
  }

  // Notificar a los responsables (Helper interno)
  Future<void> _notifyResponsibles({
    required String categoryId,
    required String title,
    required String body,
    required String referenceId,
    required String type,
  }) async {
    try {
      final responsables = await _db
          .collection('users')
          .where('rol', whereIn: [
            'Responsable',
            'Responsable Municipal',
            'responsable',
            'responsable municipal'
          ])
          .where('id_categorias', arrayContains: categoryId)
          .get();

      for (var doc in responsables.docs) {
        await _notificationService.sendNotification(
          userId: doc.id,
          title: title,
          body: body,
          referenceId: referenceId,
          type: type,
        );
      }
    } catch (e) {
      debugPrint('Error enviando notificaciones a responsables: $e');
    }
  }

  // Helper para manejar errores de red y timeout
  Future<T> _withTimeout<T>(Future<T> operation, {String? actionName}) async {
    try {
      // 5 segundos para cumplir con RNF-01 (3s ideal, 5s límite técnico razonable)
      return await operation.timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw Exception(
            'La conexión es lenta o inestable. Pulsa para reintentar.'),
      );
    } catch (e) {
      debugPrint('Error en ${actionName ?? 'operación'}: $e');
      if (e.toString().contains('network-request-failed')) {
        throw Exception(
            'Sin conexión. La operación se completará automáticamente al recuperar la red.');
      }
      if (e.toString().contains('permission-denied')) {
        throw Exception(
            'Acceso denegado. No tienes permisos para realizar esta acción.');
      }
      rethrow;
    }
  }

  // Crear incidencia
  Future<void> createIncident(Incident incident) async {
    return _withTimeout(() async {
      final data = incident.toMap();
      data['es_eliminada'] = false;
      final docRef = await _db.collection('Incidencia').add(data);

      try {
        final categorySnapshot =
            await _db.collection('Categoria').doc(incident.categoryId).get();
        final categoryName =
            categorySnapshot.exists ? categorySnapshot.get('nombre') : 'Nueva';

        await _notifyResponsibles(
          categoryId: incident.categoryId,
          title: 'Nueva incidencia: $categoryName',
          body: 'Se ha reportado: ${incident.title}',
          referenceId: docRef.id,
          type: 'incidencia',
        );
      } catch (e) {
        debugPrint('Error en notificaciones post-creación: $e');
      }
    }(), actionName: 'Crear incidencia');
  }

  // Actualizar estado
  Future<void> updateIncidentStatus(String id, String newStatus) async {
    return _withTimeout(() async {
      final Map<String, dynamic> updates = {'estado': newStatus};
      if (newStatus == 'Resuelta') {
        updates['fecha_resolucion'] = FieldValue.serverTimestamp();
      }

      await _db.collection('Incidencia').doc(id).update(updates);

      // Notificar al ciudadano
      try {
        final doc = await _db.collection('Incidencia').doc(id).get();
        if (doc.exists) {
          final userId = doc.get('id_usuario');

          await _notificationService.sendNotification(
            userId: userId,
            title: 'Actualización de incidencia',
            body:
                'Tu incidencia "${doc.get('titulo')}" ha cambiado su estado a: $newStatus',
            referenceId: id,
            type: 'incidencia',
          );
        }
      } catch (e) {
        debugPrint('Error enviando notificación de estado: $e');
      }
    }(), actionName: 'Actualizar estado');
  }

  // Eliminar incidencia con motivo (Soft Delete)
  Future<void> deleteIncident(String id, String reason) async {
    return _withTimeout(() async {
      final incidentDoc = await _db.collection('Incidencia').doc(id).get();
      if (!incidentDoc.exists) return;

      final incidentData = incidentDoc.data() as Map<String, dynamic>;
      final categoryId = incidentData['id_categoria'];

      await _db.collection('Incidencia').doc(id).update({
        'estado': 'eliminada',
        'motivo_eliminacion': reason,
        'eliminado_en': FieldValue.serverTimestamp(),
        'es_eliminada': true,
      });

      await _notifyResponsibles(
        categoryId: categoryId,
        title: 'Incidencia eliminada por ciudadano',
        body:
            'La incidencia "${incidentData['titulo'] ?? ''}" ha sido eliminada. Motivo: $reason',
        referenceId: id,
        type: 'incidencia_eliminada',
      );
    }(), actionName: 'Eliminar incidencia');
  }

  // Actualizar incidencia
  Future<void> updateIncident(Incident incident) async {
    return _withTimeout(() async {
      final updatedIncident = Incident(
        id: incident.id,
        title: incident.title,
        description: incident.description,
        imageUrl: incident.imageUrl,
        imageUrls: incident.imageUrls,
        latitude: incident.latitude,
        longitude: incident.longitude,
        createdAt: incident.createdAt,
        updatedAt: DateTime.now(),
        status: incident.status,
        userId: incident.userId,
        categoryId: incident.categoryId,
        lastReminderAt: incident.lastReminderAt,
      );

      final data = updatedIncident.toMap();
      await _db.collection('Incidencia').doc(incident.id).update(data);

      await _notifyResponsibles(
        categoryId: incident.categoryId,
        title: 'Incidencia editada por ciudadano',
        body:
            'La incidencia "${incident.title}" ha sido modificada por el autor.',
        referenceId: incident.id,
        type: 'incidencia_editada',
      );
    }(), actionName: 'Actualizar incidencia');
  }

  // Actualizar rol y categorías de un usuario
  Future<void> updateUserRoleAndCategories(
      String uid, String role, List<String>? categories) {
    return _withTimeout(() async {
      await _db.collection('users').doc(uid).update({
        'rol': role,
        'id_categorias': categories,
      });
    }(), actionName: 'Actualizar rol');
  }

  // Enviar recordatorio
  Future<bool> sendReminder(Incident incident) async {
    return _withTimeout(() async {
      try {
        final doc = await _db.collection('Incidencia').doc(incident.id).get();
        if (!doc.exists) return false;

        final data = doc.data() as Map<String, dynamic>;
        final lastReminder = data['ultimo_recordatorio'] != null
            ? (data['ultimo_recordatorio'] as Timestamp).toDate()
            : null;

        if (lastReminder != null) {
          final difference = DateTime.now().difference(lastReminder);
          if (difference.inDays < 3) {
            return false; // No han pasado 3 días
          }
        }

        // Actualizar fecha de último recordatorio
        await _db.collection('Incidencia').doc(incident.id).update({
          'ultimo_recordatorio': FieldValue.serverTimestamp(),
        });

        await _notifyResponsibles(
          categoryId: incident.categoryId,
          title: 'Recordatorio de incidencia',
          body: 'Un ciudadano solicita revisión de: ${incident.title}',
          referenceId: incident.id,
          type: 'recordatorio',
        );
        return true;
      } catch (e) {
        debugPrint('Error enviando recordatorio: $e');
        return false;
      }
    }(), actionName: 'Enviar recordatorio');
  }
}
