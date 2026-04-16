import 'package:cloud_firestore/cloud_firestore.dart';

class AppNotification {
  final String id;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool isRead;
  final String userId;
  final String? referenceId;
  final String? type;

  AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.isRead,
    required this.userId,
    this.referenceId,
    this.type,
  });

  factory AppNotification.fromFirestore(DocumentSnapshot doc) {
    Map data = doc.data() as Map;
    return AppNotification(
      id: doc.id,
      title: data['titulo'] ?? '',
      body: data['mensaje'] ?? '',
      createdAt: data['fecha_creacion'] != null
          ? (data['fecha_creacion'] as Timestamp).toDate()
          : DateTime.now(),
      isRead: data['leido'] ?? false,
      userId: data['id_usuario'] ?? '',
      referenceId: data['id_referencia'],
      type: data['tipo'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'titulo': title,
      'mensaje': body,
      'fecha_creacion': createdAt,
      'leido': isRead,
      'id_usuario': userId,
      'id_referencia': referenceId,
      'tipo': type,
    };
  }
}
