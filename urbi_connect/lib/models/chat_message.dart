import 'package:cloud_firestore/cloud_firestore.dart';

class ChatMessage {
  final String id;
  final String text;
  final DateTime createdAt;
  final String senderId;
  final String incidentId;

  ChatMessage({
    required this.id,
    required this.text,
    required this.createdAt,
    required this.senderId,
    required this.incidentId,
  });

  factory ChatMessage.fromFirestore(DocumentSnapshot doc) {
    Map data = doc.data() as Map;
    return ChatMessage(
      id: doc.id,
      text: data['texto'] ?? '',
      createdAt: (data['fecha'] as Timestamp).toDate(),
      senderId: data['emisor_id'] ?? '',
      incidentId: data['id_incidencia'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'texto': text,
      'fecha': createdAt,
      'emisor_id': senderId,
      'id_incidencia': incidentId,
    };
  }
}
