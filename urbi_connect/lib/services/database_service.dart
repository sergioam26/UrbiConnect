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
    if (profile.role == 'Ciudadano') {
      query = query.where('id_usuario', isEqualTo: profile.uid);
    } else if (profile.role == 'Responsable Municipal' ||
        profile.role == 'Responsable') {
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
              if (data['es_eliminada'] == true) return null;
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
    return _db.collection('users').doc(uid).snapshots().map((doc) {
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final profile = UserProfile.fromMap(data, doc.id);

        // Auto-upgrade project owner to Admin if they are not already
        if (profile.email == 'sergioalgmir@gmail.com' &&
            profile.role != 'Admin') {
          _db.collection('users').doc(uid).update({'rol': 'Admin'});
        }

        return profile;
      }
      return null;
    });
  }

  // Crear incidencia
  Future<void> createIncident(Incident incident) async {
    final data = incident.toMap();
    data['es_eliminada'] = false;
    final docRef = await _db.collection('Incidencia').add(data);

    // Notificar a los responsables de la categoría
    try {
      final categorySnapshot =
          await _db.collection('Categoria').doc(incident.categoryId).get();
      final categoryName =
          categorySnapshot.exists ? categorySnapshot.get('nombre') : 'Nueva';

      final responsables = await _db
          .collection('users')
          .where('rol', whereIn: ['Responsable', 'Responsable Municipal'])
          .where('id_categorias', arrayContains: incident.categoryId)
          .get();

      for (var doc in responsables.docs) {
        await _notificationService.sendNotification(
          userId: doc.id,
          title: 'Nueva incidencia: $categoryName',
          body:
              'Se ha reportado una nueva incidencia en tu categoría: ${incident.description}',
          referenceId: docRef.id,
          type: 'incidencia',
        );
      }
    } catch (e) {
      debugPrint('Error enviando notificaciones a responsables: $e');
    }
  }

  // Actualizar estado
  Future<void> updateIncidentStatus(String id, String newStatus) async {
    await _db.collection('Incidencia').doc(id).update({'estado': newStatus});

    // Notificar al ciudadano
    try {
      final doc = await _db.collection('Incidencia').doc(id).get();
      if (doc.exists) {
        final userId = doc.get('id_usuario');
        final description = doc.get('description');

        await _notificationService.sendNotification(
          userId: userId,
          title: 'Actualización de incidencia',
          body:
              'Tu incidencia "$description" ha cambiado su estado a: $newStatus',
          referenceId: id,
          type: 'incidencia',
        );
      }
    } catch (e) {
      debugPrint('Error enviando notificación de estado: $e');
    }
  }

  // Eliminar incidencia con motivo (Soft Delete)
  Future<void> deleteIncident(String id, String reason) async {
    final incidentDoc = await _db.collection('Incidencia').doc(id).get();
    if (!incidentDoc.exists) return;

    final incidentData = incidentDoc.data() as Map<String, dynamic>;
    final categoryId = incidentData['id_categoria'];
    final description = incidentData['description'];

    await _db.collection('Incidencia').doc(id).update({
      'estado': 'eliminada',
      'motivo_eliminacion': reason,
      'eliminado_en': FieldValue.serverTimestamp(),
      'es_eliminada': true,
    });

    // Notificar a los responsables
    try {
      final responsables = await _db
          .collection('users')
          .where('rol', whereIn: ['Responsable', 'Responsable Municipal'])
          .where('id_categorias', arrayContains: categoryId)
          .get();

      for (var doc in responsables.docs) {
        await _notificationService.sendNotification(
          userId: doc.id,
          title: 'Incidencia eliminada por ciudadano',
          body:
              'La incidencia "$description" ha sido eliminada. Motivo: $reason',
          referenceId: id,
          type: 'incidencia_eliminada',
        );
      }
    } catch (e) {
      debugPrint('Error enviando notificación de eliminación: $e');
    }
  }

  // Actualizar rol y categorías de un usuario
  Future<void> updateUserRoleAndCategories(
      String uid, String role, List<String>? categories) {
    return _db.collection('users').doc(uid).update({
      'rol': role,
      'id_categorias': categories,
    });
  }

  // Enviar recordatorio
  Future<bool> sendReminder(Incident incident) async {
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

      // Notificar a los responsables
      final responsables = await _db
          .collection('users')
          .where('rol', whereIn: ['Responsable', 'Responsable Municipal'])
          .where('id_categorias', arrayContains: incident.categoryId)
          .get();

      for (var doc in responsables.docs) {
        await _notificationService.sendNotification(
          userId: doc.id,
          title: 'Recordatorio de incidencia',
          body:
              'Un ciudadano solicita revisión de la incidencia: ${incident.description}',
          referenceId: incident.id,
          type: 'recordatorio',
        );
      }
      return true;
    } catch (e) {
      debugPrint('Error enviando recordatorio: $e');
      return false;
    }
  }
}
