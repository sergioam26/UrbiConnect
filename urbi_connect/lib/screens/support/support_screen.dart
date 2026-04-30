import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:urbi_connect/screens/support/support_chat_screen.dart';
import 'package:urbi_connect/services/database_service.dart';
import 'package:urbi_connect/services/support_service.dart';

class SupportScreen extends StatefulWidget {
  final bool isAdmin;
  const SupportScreen({super.key, this.isAdmin = false});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  final SupportService _supportService = SupportService();

  void _showNewTicketDialog() {
    final controller = TextEditingController();
    String? imageUrl;
    bool isSaving = false;
    final ImagePicker picker = ImagePicker();

    showDialog(
      context: context,
      barrierDismissible: !isSaving,
      builder: (context) => StatefulBuilder(builder: (context, setDialogState) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text('Reportar problema'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  maxLines: 4,
                  onChanged: (_) => setDialogState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Describe el problema con la aplicación...',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16)),
                    filled: true,
                    fillColor: Colors.grey[100],
                  ),
                ),
                const SizedBox(height: 12),
                if (imageUrl != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    height: 100,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      image: DecorationImage(
                          image: NetworkImage(imageUrl!), fit: BoxFit.cover),
                    ),
                    child: Align(
                      alignment: Alignment.topRight,
                      child: IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => setDialogState(() => imageUrl = null),
                      ),
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final XFile? image = await picker.pickImage(
                              source: ImageSource.gallery, imageQuality: 50);
                          if (image == null) return;

                          // Validación de tipo de archivo mejorada
                          final String fileName = image.name.toLowerCase();
                          final String? mimeType =
                              image.mimeType?.toLowerCase();
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
                          if (mimeType != null &&
                              mimeType.startsWith('image/')) {
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
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text(
                                        'Error: "${image.name}" no es una imagen permitida.')),
                              );
                            }
                            return;
                          }

                          setDialogState(() => isSaving = true);
                          final dbService = DatabaseService();
                          String? url;
                          if (kIsWeb) {
                            final bytes = await image.readAsBytes();
                            url = await dbService.uploadImageWeb(bytes);
                          } else {
                            url = await dbService.uploadImage(File(image.path));
                          }
                          if (url == null) {
                            setDialogState(() {
                              isSaving = false;
                            });
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        'Error al subir la imagen. Por favor, inténtalo de nuevo.')),
                              );
                            }
                            return;
                          }
                          setDialogState(() {
                            imageUrl = url;
                            isSaving = false;
                          });
                        },
                  icon: isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.image_outlined),
                  label: const Text('Adjuntar imagen'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: isSaving ? null : () => Navigator.pop(context),
                child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: (isSaving ||
                      (controller.text.trim().isEmpty && imageUrl == null))
                  ? null
                  : () async {
                      setDialogState(() => isSaving = true);
                      try {
                        final ticketId =
                            await _supportService.createSupportTicket(
                          controller.text.trim(),
                          imageUrl: imageUrl,
                        );
                        if (context.mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text(
                                    'Ticket enviado. Espera a que un administrador responda.')),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error: $e')),
                          );
                        }
                      } finally {
                        if (context.mounted)
                          setDialogState(() => isSaving = false);
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Enviar'),
            ),
          ],
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Inicia sesión')));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Soporte técnico')),
      body: StreamBuilder<QuerySnapshot>(
        stream: widget.isAdmin
            ? _supportService.getAllTickets()
            : _supportService.getUserTickets(user.uid),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Text('Error al cargar tickets:\n${snapshot.error}',
                    textAlign: TextAlign.center),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          // Sort in memory to avoid index requirements
          final tickets = snapshot.data!.docs;
          final List<QueryDocumentSnapshot> sortedTickets =
              List<QueryDocumentSnapshot>.from(tickets);
          sortedTickets.sort((a, b) {
            final dataA = a.data() as Map<String, dynamic>;
            final dataB = b.data() as Map<String, dynamic>;
            final dateA = (dataA['fecha'] as Timestamp?) ??
                (dataA['fecha_creacion'] as Timestamp?) ??
                Timestamp.now();
            final dateB = (dataB['fecha'] as Timestamp?) ??
                (dataB['fecha_creacion'] as Timestamp?) ??
                Timestamp.now();
            return dateB.compareTo(dateA);
          });

          if (sortedTickets.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.support_agent, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  const Text('No tienes tickets de soporte activos',
                      style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: sortedTickets.length,
            itemBuilder: (context, index) {
              final ticket = sortedTickets[index];
              final data = ticket.data() as Map<String, dynamic>;
              final date =
                  (data['fecha'] as Timestamp?)?.toDate() ?? DateTime.now();

              String titleText = data['descripcion'];
              String subtitlePrefix = '';

              if (widget.isAdmin) {
                if (data['es_invitado'] == true) {
                  subtitlePrefix = 'Invitado: ${data['email_invitado']} • ';
                } else if (data['id_usuario'] != null) {
                  return FutureBuilder<DocumentSnapshot>(
                    future: FirebaseFirestore.instance
                        .collection('users')
                        .doc(data['id_usuario'])
                        .get(),
                    builder: (context, userSnap) {
                      String username = 'Usuario';
                      String? role;
                      if (userSnap.hasData && userSnap.data != null) {
                        final userData =
                            userSnap.data!.data() as Map<String, dynamic>?;
                        username = userData?['usuario'] ??
                            userData?['nombre'] ??
                            'Usuario';
                        role =
                            (userData?['rol'] ?? '').toString().toLowerCase();
                      } else if (userSnap.hasError) {
                        username = 'Error';
                      } else if (userSnap.connectionState ==
                          ConnectionState.waiting) {
                        username = 'Cargando...';
                      }
                      return _buildTicketCard(ticket, data, date,
                          '$username: $titleText', '', role);
                    },
                  );
                }
              }
              final bool isGuest = data['es_invitado'] ?? false;
              return _buildTicketCard(
                  ticket, data, date, titleText, subtitlePrefix, null, isGuest);
            },
          );
        },
      ),
      floatingActionButton: !widget.isAdmin
          ? FloatingActionButton.extended(
              onPressed: _showNewTicketDialog,
              icon: const Icon(Icons.add_comment_rounded),
              label: const Text('Nueva consulta',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              backgroundColor: const Color(0xFF0F172A),
              foregroundColor: Colors.white,
            )
          : null,
    );
  }

  Widget _buildTicketCard(
      QueryDocumentSnapshot ticket,
      Map<String, dynamic> data,
      DateTime date,
      String title,
      String subtitlePrefix,
      [String? role,
      bool isGuest = false]) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle:
            Text('$subtitlePrefix${DateFormat('dd/MM HH:mm').format(date)}'),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (widget.isAdmin && role != null) ...[
              _buildRoleBadge(role),
              const SizedBox(height: 4),
            ],
            if (widget.isAdmin && isGuest) ...[
              _buildBadge('Invitado', Colors.orange[800]!),
              const SizedBox(height: 4),
            ],
            // Usamos un badge para el estado en lugar del punto
            _buildBadge(data['estado'], _getStatusColor(data['estado'])),
          ],
        ),
        onTap: () {
          if (data['es_invitado'] == true && widget.isAdmin) {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Ticket de Invitado'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        'Nombre: ${data['nombre_invitado']} ${data['apellidos_invitado']}'),
                    const SizedBox(height: 8),
                    Text('Email: ${data['email_invitado']}'),
                    const SizedBox(height: 16),
                    const Text(
                        'Los tickets de invitados no permiten chat directo ya que el usuario no tiene cuenta. Por favor, contacta con él vía email.'),
                  ],
                ),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Entendido')),
                ],
              ),
            );
            return;
          }
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => SupportChatScreen(
                  ticketId: ticket.id, isAdmin: widget.isAdmin),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatusIndicator(String status) {
    Color color;
    switch (status) {
      case 'Abierto':
        color = Colors.red;
        break;
      case 'En proceso':
        color = Colors.orange;
        break;
      case 'Cerrado':
        color = Colors.green;
        break;
      default:
        color = Colors.grey;
    }
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Abierto':
        return Colors.red;
      case 'En proceso':
        return Colors.orange;
      case 'Cerrado':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  Widget _buildRoleBadge(String role) {
    final String r = role.toLowerCase();
    Color color = Colors.blue;
    String text = 'Ciudadano';

    if (r.contains('responsable')) {
      color = Colors.purple;
      text = 'Responsable';
    } else if (r.contains('admin')) {
      color = Colors.red;
      text = 'Admin';
    }

    return _buildBadge(text, color);
  }

  Widget _buildGuestBadge() {
    return _buildBadge('Invitado', Colors.orange[800]!);
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      width: 90,
      padding: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Center(
        child: Text(
          text,
          style:
              TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
