import 'package:cloud_firestore/cloud_firestore.dart';

class Incident {
  final String id;
  final String description;
  final String? imageUrl;
  final double latitude;
  final double longitude;
  final DateTime createdAt;
  final String status; // 'pendiente', 'en proceso', 'resuelta'
  final String userId;
  final String categoryId;

  Incident({
    required this.id,
    required this.description,
    this.imageUrl,
    required this.latitude,
    required this.longitude,
    required this.createdAt,
    required this.status,
    required this.userId,
    required this.categoryId,
  });

  factory Incident.fromFirestore(DocumentSnapshot doc) {
    Map data = doc.data() as Map;
    return Incident(
      id: doc.id,
      description: data['description'] ?? '',
      imageUrl: data['foto_url'],
      latitude: (data['latitud'] ?? 0.0).toDouble(),
      longitude: (data['longitud'] ?? 0.0).toDouble(),
      createdAt: data['fecha_creacion'] != null
          ? (data['fecha_creacion'] as Timestamp).toDate()
          : DateTime.now(),
      status: data['estado'] ?? 'pendiente',
      userId: data['id_usuario'] ?? '',
      categoryId: data['id_categoria'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'description': description,
      'foto_url': imageUrl,
      'latitud': latitude,
      'longitud': longitude,
      'fecha_creacion': createdAt,
      'estado': status,
      'id_usuario': userId,
      'id_categoria': categoryId,
    };
  }
}
