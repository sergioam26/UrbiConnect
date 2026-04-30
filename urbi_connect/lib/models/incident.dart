import 'package:cloud_firestore/cloud_firestore.dart';

class Incident {
  final String id;
  final String title;
  final String description;
  final String? imageUrl; // Mantenemos por compatibilidad con datos antiguos
  final List<String>? imageUrls;
  final double latitude;
  final double longitude;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String status; // 'pendiente', 'en proceso', 'resuelta'
  final String userId;
  final String categoryId;
  final DateTime? lastReminderAt;

  Incident({
    required this.id,
    required this.title,
    required this.description,
    this.imageUrl,
    this.imageUrls,
    required this.latitude,
    required this.longitude,
    required this.createdAt,
    this.updatedAt,
    required this.status,
    required this.userId,
    required this.categoryId,
    this.lastReminderAt,
  });

  factory Incident.fromFirestore(DocumentSnapshot doc) {
    Map data = doc.data() as Map;
    final List<dynamic>? urlsData = data['fotos_urls'];
    return Incident(
      id: doc.id,
      title: data['titulo'] ?? '',
      description: data['description'] ?? '',
      imageUrl: data['foto_url'],
      imageUrls: urlsData != null ? List<String>.from(urlsData) : null,
      latitude: (data['latitud'] ?? 0.0).toDouble(),
      longitude: (data['longitud'] ?? 0.0).toDouble(),
      createdAt: data['fecha_creacion'] != null
          ? (data['fecha_creacion'] as Timestamp).toDate()
          : DateTime.now(),
      updatedAt: data['fecha_edicion'] != null
          ? (data['fecha_edicion'] as Timestamp).toDate()
          : null,
      status: data['estado'] ?? 'pendiente',
      userId: data['id_usuario'] ?? '',
      categoryId: data['id_categoria'] ?? '',
      lastReminderAt: data['ultimo_recordatorio'] != null
          ? (data['ultimo_recordatorio'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'titulo': title,
      'description': description,
      'foto_url': imageUrl,
      'fotos_urls': imageUrls,
      'latitud': latitude,
      'longitud': longitude,
      'fecha_creacion': createdAt,
      'fecha_edicion': updatedAt,
      'estado': status,
      'id_usuario': userId,
      'id_categoria': categoryId,
      'ultimo_recordatorio': lastReminderAt,
    };
  }
}
