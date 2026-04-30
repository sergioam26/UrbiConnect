import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:urbi_connect/models/chat_message.dart';
import 'package:urbi_connect/services/chat_service.dart';
import 'package:urbi_connect/services/database_service.dart';

class ChatScreen extends StatefulWidget {
  final String incidentId;

  const ChatScreen({super.key, required this.incidentId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ChatService _chatService = ChatService();
  final DatabaseService _dbService = DatabaseService();
  final String _currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
  final ImagePicker _picker = ImagePicker();

  bool _isUploading = false;

  Future<void> _sendImage() async {
    final XFile? image =
        await _picker.pickImage(source: ImageSource.gallery, imageQuality: 50);
    if (image == null) {
      return;
    }

    // Validación de tipo de archivo mejorado
    final String fileName = image.name.toLowerCase();
    final String? mimeType = image.mimeType?.toLowerCase();
    final List<String> allowedExtensions = [
      '.jpg',
      '.jpeg',
      '.png',
      '.webp',
      '.heic',
      '.heif',
      '.gif',
      '.svg',
      '.svgz',
      '.bmp',
      '.ico',
      '.tiff',
      '.tif',
      '.jfif',
      '.pjp',
      '.apng',
      '.xbm',
      '.jxl',
      '.jpe',
      '.pjpeg',
      '.avif'
    ];

    bool isImage = false;
    if (mimeType != null && mimeType.startsWith('image/')) {
      isImage = true;
    } else {
      for (var ext in allowedExtensions) {
        if (fileName.endsWith(ext)) {
          isImage = true;
          break;
        }
      }
    }

    if (!isImage) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: "$fileName" no es una imagen permitida.')),
        );
      }
      return;
    }

    setState(() => _isUploading = true);

    String? imageUrl;
    if (kIsWeb) {
      final bytes = await image.readAsBytes();
      imageUrl = await _dbService.uploadImageWeb(bytes);
    } else {
      imageUrl = await _dbService.uploadImage(File(image.path));
    }

    if (imageUrl != null) {
      await _chatService.sendMessage(
        widget.incidentId,
        _currentUserId,
        '',
        imageUrl: imageUrl,
      );
    }

    setState(() => _isUploading = false);
  }

  void _sendMessage() {
    if (_messageController.text.trim().isEmpty) {
      return;
    }

    _chatService.sendMessage(
      widget.incidentId,
      _currentUserId,
      _messageController.text.trim(),
    );
    _messageController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat de incidencia'),
      ),
      body: Column(
        children: [
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('Incidencia')
                .doc(widget.incidentId)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData || !snapshot.data!.exists) {
                return const SizedBox();
              }
              final data = snapshot.data!.data() as Map<String, dynamic>;
              final String? imageUrl = data['foto_url'];
              if (imageUrl == null) {
                return const SizedBox();
              }

              return Container(
                height: 60,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(
                      bottom: BorderSide(
                          color: Colors.grey.withValues(alpha: 0.1))),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(imageUrl,
                          width: 44, height: 44, fit: BoxFit.cover),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(data['titulo'] ?? 'Incidencia',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 13)),
                          Text(data['estado'] ?? '',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey[600])),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          Expanded(
            child: StreamBuilder<List<ChatMessage>>(
              stream: _chatService.getMessages(widget.incidentId),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(child: Text('Error al cargar mensajes'));
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final messages = snapshot.data ?? [];

                if (messages.isEmpty) {
                  return const Center(
                      child: Text(
                          'No hay mensajes aún. ¡Inicia la conversación!'));
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    return FutureBuilder<DocumentSnapshot>(
                      future: FirebaseFirestore.instance
                          .collection('users')
                          .doc(msg.senderId)
                          .get(),
                      builder: (context, userSnapshot) {
                        String senderName = 'Cargando...';
                        if (userSnapshot.hasData && userSnapshot.data!.exists) {
                          final userData =
                              userSnapshot.data!.data() as Map<String, dynamic>;
                          senderName = userData['nombre'] ??
                              userData['email'] ??
                              'Usuario';
                        }

                        return ChatBubble(
                          message: msg.text,
                          imageUrl: msg.imageUrl,
                          isMe: msg.senderId == _currentUserId,
                          sender: msg.senderId == _currentUserId
                              ? 'Tú'
                              : senderName,
                          avatarUrl: (userSnapshot.hasData &&
                                  userSnapshot.data!.exists)
                              ? (userSnapshot.data!.data()
                                  as Map<String, dynamic>)['foto_perfil']
                              : null,
                          onAvatarTap: () {
                            if (userSnapshot.hasData &&
                                userSnapshot.data!.exists) {
                              _showUserProfile(
                                  context,
                                  msg.senderId,
                                  userSnapshot.data!.data()
                                      as Map<String, dynamic>);
                            }
                          },
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
          _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 5,
              offset: const Offset(0, -2))
        ],
      ),
      child: Column(
        children: [
          if (_isUploading)
            const Padding(
              padding: EdgeInsets.only(bottom: 8.0),
              child: LinearProgressIndicator(),
            ),
          Row(
            children: [
              IconButton(
                icon:
                    const Icon(Icons.image_outlined, color: Color(0xFF6750A4)),
                onPressed: _isUploading ? null : _sendImage,
              ),
              Expanded(
                child: TextField(
                  controller: _messageController,
                  decoration: InputDecoration(
                    hintText: 'Escribe un mensaje...',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none),
                    filled: true,
                    fillColor: Colors.grey[100],
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
              const SizedBox(width: 8),
              CircleAvatar(
                backgroundColor: const Color(0xFF6750A4),
                child: IconButton(
                  icon: const Icon(Icons.send, color: Colors.white),
                  onPressed: _sendMessage,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showUserProfile(
      BuildContext context, String userId, Map<String, dynamic> userData) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 40,
              backgroundImage: userData['foto_perfil'] != null
                  ? NetworkImage(userData['foto_perfil'])
                  : null,
              child: userData['foto_perfil'] == null
                  ? const Icon(Icons.person, size: 40)
                  : null,
            ),
            const SizedBox(height: 16),
            Text(userData['nombre'] ?? 'Usuario',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text('@${userData['usuario'] ?? ''}',
                style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 8),
            Text(userData['email'] ?? '', style: const TextStyle(fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar')),
        ],
      ),
    );
  }
}

class ChatBubble extends StatelessWidget {
  final String message;
  final String? imageUrl;
  final bool isMe;
  final String sender;
  final String? avatarUrl;
  final VoidCallback onAvatarTap;

  const ChatBubble({
    super.key,
    required this.message,
    this.imageUrl,
    required this.isMe,
    required this.sender,
    this.avatarUrl,
    required this.onAvatarTap,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            GestureDetector(
              onTap: onAvatarTap,
              child: CircleAvatar(
                radius: 16,
                backgroundImage:
                    avatarUrl != null ? NetworkImage(avatarUrl!) : null,
                child: avatarUrl == null
                    ? const Icon(Icons.person, size: 16)
                    : null,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12),
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.7),
              decoration: BoxDecoration(
                color: isMe ? const Color(0xFF6750A4) : Colors.grey[200],
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: isMe ? const Radius.circular(16) : Radius.zero,
                  bottomRight: isMe ? Radius.zero : const Radius.circular(16),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sender,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isMe ? Colors.white70 : Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (imageUrl != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4.0),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          imageUrl!,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return const SizedBox(
                              height: 150,
                              child: Center(child: CircularProgressIndicator()),
                            );
                          },
                        ),
                      ),
                    ),
                  if (message.isNotEmpty)
                    Text(
                      message,
                      style: TextStyle(
                          color: isMe ? Colors.white : Colors.black87),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
