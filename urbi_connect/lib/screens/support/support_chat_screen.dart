import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:urbi_connect/services/database_service.dart';
import 'package:urbi_connect/services/support_service.dart';

class SupportChatScreen extends StatefulWidget {
  final String ticketId;
  final bool isAdmin;

  const SupportChatScreen(
      {super.key, required this.ticketId, required this.isAdmin});

  @override
  State<SupportChatScreen> createState() => _SupportChatScreenState();
}

class _SupportChatScreenState extends State<SupportChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final SupportService _supportService = SupportService();
  final DatabaseService _dbService = DatabaseService();
  final String _currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
  final ImagePicker _picker = ImagePicker();
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _markRead();
  }

  Future<void> _markRead() async {
    await _supportService.markAsRead(widget.ticketId, widget.isAdmin);
  }

  Future<void> _sendImage() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 50,
      maxWidth: 1024,
      maxHeight: 1024,
    );
    if (image == null) return;

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
      await _supportService.sendSupportMessage(
        widget.ticketId,
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
    _supportService.sendSupportMessage(
        widget.ticketId, _currentUserId, _messageController.text.trim());
    _messageController.clear();
  }

  // --- NUEVA FUNCIÓN: Construye el título dinámico con nombre y rol ---
  Widget _buildChatTitle(Map<String, dynamic> ticketData) {
    if (widget.isAdmin) {
      // 1. El Admin está viendo el chat: Comprobamos si el otro usuario es invitado
      if (ticketData['es_invitado'] == true) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
                '${ticketData['nombre_invitado']} ${ticketData['apellidos_invitado']}',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const Text('INVITADO',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal)),
          ],
        );
      } else {
        // 2. El Admin está viendo el chat: El otro usuario es un ciudadano registrado
        return FutureBuilder<DocumentSnapshot>(
          future: FirebaseFirestore.instance
              .collection('users')
              .doc(ticketData['id_usuario'])
              .get(),
          builder: (context, snapshot) {
            if (!snapshot.hasData || !snapshot.data!.exists) {
              return const Text('Cargando...',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold));
            }
            final userData = snapshot.data!.data() as Map<String, dynamic>;
            final nombre = userData['nombre'] ?? 'Usuario';
            final apellidos = userData['apellidos'] ?? '';
            final rol =
                (userData['rol'] ?? 'Ciudadano').toString().toUpperCase();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text('$nombre $apellidos',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                Text(rol,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.normal)),
              ],
            );
          },
        );
      }
    } else {
      // 3. El ciudadano está viendo el chat: Siempre habla con la administración
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text('Administración',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          Text('ADMINISTRADOR',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal)),
        ],
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('Soporte')
            .doc(widget.ticketId)
            .snapshots(),
        builder: (context, ticketSnapshot) {
          if (!ticketSnapshot.hasData) {
            return Scaffold(
                appBar: AppBar(),
                body: const Center(child: CircularProgressIndicator()));
          }
          final ticketData =
              ticketSnapshot.data!.data() as Map<String, dynamic>?;
          if (ticketData == null) {
            return Scaffold(
                appBar: AppBar(),
                body: const Center(child: Text('Ticket no encontrado')));
          }
          final String status = ticketData['estado'] ?? 'Abierto';

          return Scaffold(
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            appBar: AppBar(
              title: _buildChatTitle(ticketData),
              actions: widget.isAdmin
                  ? [
                      if (status != 'Cerrado')
                        TextButton.icon(
                          onPressed: () => _supportService.updateTicketStatus(
                              widget.ticketId, 'Cerrado'),
                          icon: const Icon(Icons.close_rounded,
                              size: 18, color: Colors.red),
                          label: const Text('Cerrar',
                              style: TextStyle(color: Colors.red)),
                        ),
                      PopupMenuButton<String>(
                        onSelected: (val) => _supportService.updateTicketStatus(
                            widget.ticketId, val),
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                              value: 'Abierto', child: Text('Marcar abierto')),
                          const PopupMenuItem(
                              value: 'Cerrado', child: Text('Marcar cerrado')),
                        ],
                        icon: const Icon(Icons.more_vert),
                      )
                    ]
                  : null,
            ),
            body: Column(
              children: [
                _buildTicketHeaderFromData(ticketData),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('Soporte')
                        .doc(widget.ticketId)
                        .collection('Chat')
                        .snapshots(),
                    builder: (context, chatSnapshot) {
                      if (chatSnapshot.hasError) {
                        return Center(
                            child: Text(
                                'Error al cargar mensajes: ${chatSnapshot.error}'));
                      }
                      if (!chatSnapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final messages = chatSnapshot.data!.docs;

                      // In-memory sort
                      final sortedMessages =
                          List<QueryDocumentSnapshot>.from(messages);
                      sortedMessages.sort((a, b) {
                        final timestampA = (a.data()
                            as Map<String, dynamic>)['fecha'] as Timestamp?;
                        final timestampB = (b.data()
                            as Map<String, dynamic>)['fecha'] as Timestamp?;

                        final dateA = timestampA?.toDate() ?? DateTime.now();
                        final dateB = timestampB?.toDate() ?? DateTime.now();
                        return dateB.compareTo(
                            dateA); // Descending for reversed ListView
                      });

                      final hasMessages = sortedMessages.isNotEmpty;

                      return Column(
                        children: [
                          Expanded(
                            child: ListView.builder(
                              reverse: true,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 16),
                              itemCount: sortedMessages.length,
                              itemBuilder: (context, index) {
                                final msg = sortedMessages[index];
                                final isMe = msg['id_emisor'] == _currentUserId;
                                final data = msg.data() as Map<String, dynamic>;
                                return _buildMessageBubble(
                                  data['mensaje'] ?? '',
                                  isMe,
                                  msg['fecha'],
                                  msg['id_emisor'],
                                  data['url_imagen'],
                                );
                              },
                            ),
                          ),
                          _buildMessageInput(status, ticketData, hasMessages),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        });
  }

  Widget _buildTicketHeaderFromData(Map<String, dynamic> data) {
    final String? imageUrl = data['url_imagen'];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
            bottom: BorderSide(
                color: Theme.of(context).dividerColor.withValues(alpha: 1))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Ticket #${widget.ticketId.substring(0, 5).toUpperCase()}${data['es_invitado'] == true ? ' (Invitado)' : ''}',
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Colors.grey),
              ),
              _buildStatusSmall(data['estado']),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 14, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      'MENSAJE INICIAL:',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  data['descripcion'] ?? 'Sin descripción',
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          if (imageUrl != null) ...[
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => Scaffold(
                    backgroundColor: Colors.black,
                    body: InkWell(
                      onTap: () => Navigator.pop(context),
                      child: Center(child: Image.network(imageUrl)),
                    ),
                  ),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.network(
                  imageUrl,
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusSmall(String status) {
    Color color;
    switch (status) {
      case 'Abierto':
        color = Colors.green;
        break;
      case 'Cerrado':
        color = Colors.red;
        break;
      default:
        color = Colors.grey;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(
            status,
            style: TextStyle(
                color: color, fontSize: 10, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(
      String text, bool isMe, dynamic timestamp, String senderId,
      [String? imageUrl]) {
    final DateTime date = (timestamp as Timestamp?)?.toDate() ?? DateTime.now();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) _buildAvatar(senderId),
          if (!isMe) const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isMe
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(20),
                  topRight: const Radius.circular(20),
                  bottomLeft: isMe ? const Radius.circular(20) : Radius.zero,
                  bottomRight: isMe ? Radius.zero : const Radius.circular(20),
                ),
                boxShadow: [
                  if (!isMe)
                    BoxShadow(
                        color: Colors.black.withValues(
                            alpha:
                                Theme.of(context).brightness == Brightness.dark
                                    ? 0.3
                                    : 0.05),
                        blurRadius: 5,
                        offset: const Offset(0, 2)),
                ],
              ),
              child: Column(
                crossAxisAlignment:
                    isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  if (imageUrl != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4.0),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          imageUrl,
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
                  if (text.isNotEmpty)
                    Text(
                      text,
                      style: TextStyle(
                          color: isMe
                              ? Theme.of(context).colorScheme.onPrimary
                              : Theme.of(context).colorScheme.onSurface,
                          fontSize: 14,
                          height: 1.4),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('HH:mm').format(date),
                    style: TextStyle(
                        fontSize: 10,
                        color: isMe
                            ? Theme.of(context)
                                .colorScheme
                                .onPrimary
                                .withValues(alpha: 0.7)
                            : Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant
                                .withValues(alpha: 0.7)),
                  ),
                ],
              ),
            ),
          ),
          if (isMe) const SizedBox(width: 8),
          if (isMe) _buildAvatar(senderId),
        ],
      ),
    );
  }

  Widget _buildAvatar(String uid) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(uid).get(),
      builder: (context, snapshot) {
        final data = snapshot.hasData
            ? snapshot.data!.data() as Map<String, dynamic>?
            : null;
        final photoUrl = data?['foto_perfil'];
        return CircleAvatar(
          radius: 14,
          backgroundColor: Colors.grey[200],
          backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
          child: photoUrl == null
              ? const Icon(Icons.person, size: 14, color: Colors.grey)
              : null,
        );
      },
    );
  }

  Widget _buildMessageInput(
      String status, Map<String, dynamic> ticketData, bool hasMessages) {
    if (status == 'Cerrado') {
      return Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          border: Border(
              top: BorderSide(
                  color:
                      Theme.of(context).dividerColor.withValues(alpha: 0.1))),
        ),
        child: Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline_rounded,
                  size: 16,
                  color: Theme.of(context).textTheme.bodySmall?.color),
              const SizedBox(width: 8),
              Text(
                'Este ticket ha sido cerrado y no admite más mensajes.',
                style: TextStyle(
                    color: Theme.of(context).textTheme.bodySmall?.color,
                    fontSize: 13,
                    fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      );
    }

    final bool isGuest = ticketData['es_invitado'] == true;

    if (isGuest) {
      return Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        decoration: BoxDecoration(
          color: Colors.amber.withValues(alpha: 0.1),
          border: Border(
              top: BorderSide(color: Colors.amber.withValues(alpha: 0.1))),
        ),
        child: const Center(
          child: Text(
            'Consulta de invitado. No se permite chat directo.',
            style: TextStyle(
                color: Colors.amber, fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ),
      );
    }

    final bool canChat = widget.isAdmin || (status == 'Abierto');

    if (!canChat) {
      String messageText =
          'Reporte enviado. Un administrador iniciará el chat si es necesario.';
      if (status == 'Cerrado' && !widget.isAdmin) {
        messageText = 'Ticket pendiente de revisión por el administrador.';
      }
      return Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.05),
          border: Border(
              top: BorderSide(
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.1))),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.hourglass_empty_rounded,
                color: Theme.of(context).colorScheme.primary, size: 24),
            const SizedBox(height: 8),
            Text(
              messageText,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(
                  alpha: Theme.of(context).brightness == Brightness.dark
                      ? 0.3
                      : 0.05),
              blurRadius: 10,
              offset: const Offset(0, -5))
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
                icon: Icon(Icons.image_outlined,
                    color: Theme.of(context).colorScheme.primary),
                onPressed: _isUploading ? null : _sendImage,
              ),
              Expanded(
                child: TextField(
                  controller: _messageController,
                  style: TextStyle(
                      color: Theme.of(context).textTheme.bodyLarge?.color),
                  decoration: InputDecoration(
                    hintText: 'Escribe un mensaje...',
                    hintStyle: TextStyle(
                        color: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.color
                            ?.withValues(alpha: 0.6)),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none),
                    filled: true,
                    fillColor:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                  ),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
              const SizedBox(width: 8),
              CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primary,
                child: IconButton(
                  onPressed: _sendMessage,
                  icon: const Icon(Icons.send_rounded,
                      color: Colors.white, size: 20),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
