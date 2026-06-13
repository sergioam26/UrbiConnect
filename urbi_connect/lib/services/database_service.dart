import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:urbi_connect/config/app_config.dart';
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
      if (profile.email.toLowerCase() ==
          AppConfig.superUserEmail.toLowerCase()) {
        // El súper usuario en rol de responsable ve todas las incidencias para probar fácilmente (o las asignadas si tiene)
        if (profile.categories != null && profile.categories!.isNotEmpty) {
          query = query.where('id_categoria', whereIn: profile.categories);
        }
      } else {
        if (profile.categories != null && profile.categories!.isNotEmpty) {
          query = query.where('id_categoria', whereIn: profile.categories);
        } else {
          return Stream.value([]);
        }
      }
    }

    return query.snapshots().map((snapshot) {
      final now = DateTime.now();
      final fortyFiveDaysAgo = now.subtract(const Duration(days: 45));

      final incidents = snapshot.docs
          .map((doc) {
            try {
              final data = doc.data() as Map<String, dynamic>;
              final bool esEliminada =
                  data['es_eliminada'] == true || data['estado'] == 'eliminada';
              final String state = data['estado'] ?? 'pendiente';

              if (esEliminada) {
                final eliminadoEn =
                    (data['eliminado_en'] as Timestamp?)?.toDate();
                final fechaRef = eliminadoEn ??
                    (data['fecha_creacion'] as Timestamp?)?.toDate();
                if (fechaRef != null && fechaRef.isBefore(fortyFiveDaysAgo)) {
                  return null; // Ocultar si está eliminada hace más de 45 días
                }
              } else if (state == 'Resuelta') {
                final fechaResolucion =
                    (data['fecha_resolucion'] as Timestamp?)?.toDate();
                final fechaRef = fechaResolucion ??
                    (data['fecha_creacion'] as Timestamp?)?.toDate();
                if (fechaRef != null && fechaRef.isBefore(fortyFiveDaysAgo)) {
                  return null; // Ocultar si está resuelta hace más de 45 días
                }
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
        final data = doc.data() as Map<String, dynamic>;

        // Auto-upgrade en segundo plano si es administrador real de Firestore
        final email = (data['email'] ?? '').toString().toLowerCase();
        if (email == AppConfig.superUserEmail.toLowerCase()) {
          final currentDbRole = (data['rol'] ?? '').toString().toLowerCase();
          if (currentDbRole != 'admin') {
            _db
                .collection('users')
                .doc(uid)
                .update({'rol': 'admin'}).catchError((e) {
              debugPrint(
                  'Aviso: No se pudo auto-reparar el rol real en Firestore (esperado si no tiene permisos): $e');
            });
          }
        }

        // Guardar preferencias locales para el filtro en segundo plano (cuando la app está totalmente cerrada)
        try {
          final List<dynamic> localRoles =
              data.containsKey('enabled_push_roles')
                  ? List.from(data['enabled_push_roles'])
                  : ['admin', 'responsable', 'ciudadano'];
          final String localRole =
              (data['rol'] ?? 'ciudadano').toString().toLowerCase();

          SharedPreferences.getInstance().then((prefs) {
            prefs.setStringList('enabled_push_roles',
                localRoles.map((e) => e.toString()).toList());
            prefs.setString('user_profile_role', localRole);
            prefs.setString('user_profile_email', email);
          });
        } catch (e) {
          debugPrint('Error actualizando caché local para notificaciones: $e');
        }

        return UserProfile.fromMap(data, doc.id);
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
      // Intentar primero con el campo plural (array)
      var responsables = await _db
          .collection('users')
          .where('rol', whereIn: [
            'Responsable',
            'Responsable Municipal',
            'responsable',
            'responsable municipal'
          ])
          .where('id_categorias', arrayContains: categoryId)
          .get();

      if (responsables.docs.isEmpty) {
        // Intentar con el campo singular si el plural falla
        responsables = await _db
            .collection('users')
            .where('rol', whereIn: [
              'Responsable',
              'Responsable Municipal',
              'responsable',
              'responsable municipal'
            ])
            .where('id_categoria', isEqualTo: categoryId)
            .get();
      }

      final List<DocumentSnapshot> targetUsersList =
          List.from(responsables.docs);

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
          final alreadyAdded =
              targetUsersList.any((doc) => doc.id == superUserDoc.id);
          if (!alreadyAdded) {
            // Se agrega al súper usuario incondicionalmente en base de datos para que reciba las notificaciones en su buzón durante las pruebas.
            targetUsersList.add(superUserDoc);
          }
        }
      } catch (e) {
        debugPrint(
            'Error integrando súper usuario responsable en incidencias: $e');
      }

      for (var doc in targetUsersList) {
        await _notificationService.sendNotification(
          userId: doc.id,
          title: title,
          body: body,
          referenceId: referenceId,
          type: type,
          destinatarios: ['responsable'],
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
    // Validaciones de datos (Checkpoint 3)
    if (incident.title.trim().isEmpty) {
      throw Exception('El título no puede estar vacío.');
    }
    if (incident.description.trim().isEmpty) {
      throw Exception('La descripción no puede estar vacía.');
    }
    if (incident.categoryId.isEmpty) {
      throw Exception('Debes seleccionar una categoría.');
    }
    if (incident.latitude == 0 || incident.longitude == 0) {
      throw Exception('La ubicación no es válida.');
    }

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
            destinatarios: ['ciudadano'],
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
    // Validaciones de datos (Checkpoint 3)
    if (incident.title.trim().isEmpty) {
      throw Exception('El título no puede estar vacío.');
    }
    if (incident.description.trim().isEmpty) {
      throw Exception('La descripción no puede estar vacía.');
    }

    return _withTimeout(() async {
      final updatedIncident = Incident(
        id: incident.id,
        title: incident.title,
        description: incident.description,
        imageUrl: incident.imageUrl,
        imageUrls: incident.imageUrls,
        latitude: incident.latitude,
        longitude: incident.longitude,
        address: incident.address,
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

  Future<void> deleteUserFully(String uid, String email) async {
    return _withTimeout(() async {
      final batch = _db.batch();
      final userDocRef = _db.collection('users').doc(uid);

      // 0. Eliminar foto de perfil de Firebase Storage
      final userDoc = await userDocRef.get();
      if (userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>;
        final String? fotoUrl = userData['foto_perfil'];

        if (fotoUrl != null && fotoUrl.isNotEmpty) {
          try {
            await FirebaseStorage.instance.refFromURL(fotoUrl).delete();
          } catch (e) {
            debugPrint('Error al eliminar la foto de perfil de Storage: $e');
          }
        }
      }

      // 1. Eliminar documento de usuario
      batch.delete(userDocRef);

      // 2. Eliminar notificaciones del usuario
      final notifications = await _db
          .collection('Notificaciones')
          .where('id_usuario', whereIn: [uid, 'silenciado_$uid']).get();
      for (var doc in notifications.docs) {
        batch.delete(doc.reference);
      }

      // --- MODIFICADO: 3. Eliminar incidencias del usuario y sus fotografías asociadas ---
      final incidences = await _db
          .collection('Incidencia')
          .where('id_usuario', isEqualTo: uid)
          .get();

      for (var doc in incidences.docs) {
        final incidentData = doc.data() as Map<String, dynamic>;

        // 3.1 Eliminar foto principal de la incidencia
        final String? mainFotoUrl = incidentData['foto_url'];
        if (mainFotoUrl != null && mainFotoUrl.isNotEmpty) {
          try {
            await FirebaseStorage.instance.refFromURL(mainFotoUrl).delete();
          } catch (e) {
            debugPrint('Error al eliminar foto principal de incidencia: $e');
          }
        }

        // 3.2 Eliminar galería de fotos de la incidencia (si existe)
        final List<dynamic>? fotosUrls = incidentData['fotos_urls'];
        if (fotosUrls != null && fotosUrls.isNotEmpty) {
          for (var url in fotosUrls) {
            if (url.toString().isNotEmpty) {
              try {
                await FirebaseStorage.instance
                    .refFromURL(url.toString())
                    .delete();
              } catch (e) {
                debugPrint('Error al eliminar foto de galería: $e');
              }
            }
          }
        }

        // Finalmente, borrar el documento de la incidencia en Firestore
        batch.delete(doc.reference);
      }

      // 4. Eliminar tickets de soporte
      final tickets = await _db
          .collection('Soporte')
          .where('id_usuario', isEqualTo: uid)
          .get();
      for (var doc in tickets.docs) {
        batch.delete(doc.reference);
      }

      // 5. Añadir a la lista de bloqueados/eliminados
      batch.set(
          _db.collection('deleted_users').doc(email.trim().toLowerCase()), {
        'email': email.trim().toLowerCase(),
        'fecha_eliminacion': FieldValue.serverTimestamp(),
        'uid_original': uid,
      });

      await batch.commit();
    }(), actionName: 'Eliminar usuario permanentemente');
  }
}
