import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:urbi_connect/models/incident.dart';
import 'package:urbi_connect/models/user_profile.dart';

class DatabaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

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
    Query query = _db.collection('Incidencia');

    if (profile.role == 'Ciudadano') {
      // Ciudadano solo ve sus propias incidencias
      query = query.where('id_usuario', isEqualTo: profile.uid);
    } else if (profile.role == 'Responsable Municipal' ||
        profile.role == 'Responsable') {
      // Responsable ve todas las de su categoría
      if (profile.category != null) {
        query = query.where('id_categoria', isEqualTo: profile.category);
      }
    }
    // Admin ve todas (no filtramos)

    return query.snapshots().map((snapshot) {
      try {
        final incidents = snapshot.docs
            .map((doc) {
              try {
                return Incident.fromFirestore(doc);
              } catch (e) {
                debugPrint('Error al parsear incidencia ${doc.id}: $e');
                return null;
              }
            })
            .whereType<Incident>()
            .toList();

        // Ordenar en memoria por fecha de creación descendente
        incidents.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return incidents;
      } catch (e) {
        debugPrint('Error general en el stream de incidencias: $e');
        rethrow;
      }
    });
  }

  // Obtener perfil de usuario
  Stream<UserProfile?> getUserProfile(String uid) {
    return _db.collection('users').doc(uid).snapshots().map((doc) {
      if (doc.exists && doc.data() != null) {
        return UserProfile.fromMap(doc.data()!, doc.id);
      }
      return null;
    });
  }

  // Crear incidencia
  Future<void> createIncident(Incident incident) {
    return _db.collection('Incidencia').add(incident.toMap());
  }

  // Actualizar estado
  Future<void> updateIncidentStatus(String id, String newStatus) {
    return _db.collection('Incidencia').doc(id).update({'estado': newStatus});
  }
}
