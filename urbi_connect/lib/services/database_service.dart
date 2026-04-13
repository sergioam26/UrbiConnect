import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:urbi_connect/models/incident.dart';

class DatabaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Stream de incidencias
  Stream<List<Incident>> getIncidents() {
    return _db
        .collection('Incidencia')
        .orderBy('fecha_creacion', descending: true)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => Incident.fromFirestore(doc)).toList());
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
