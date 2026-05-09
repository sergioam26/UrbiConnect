import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:urbi_connect/models/user_profile.dart';
import 'package:urbi_connect/screens/support/support_chat_screen.dart';
import 'package:urbi_connect/services/database_service.dart';
import 'package:urbi_connect/services/notification_service.dart';
import 'package:urbi_connect/services/support_service.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  final NotificationService _notificationService = NotificationService();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          'Usuarios del sistema',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        elevation: 0,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: Theme.of(context).textTheme.titleLarge?.color,
        actions: [
          IconButton(
            onPressed: () => _showBroadcastDialog(context),
            icon: const Icon(Icons.campaign_rounded),
            tooltip: 'Comunicado general',
            style: IconButton.styleFrom(
              foregroundColor: const Color(0xFF6366F1),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: Theme.of(context).scaffoldBackgroundColor,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: TextField(
              controller: _searchController,
              onChanged: (value) =>
                  setState(() => _searchQuery = value.toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Buscar por nombre o email...',
                prefixIcon: Icon(Icons.search,
                    color: Theme.of(context).textTheme.bodySmall?.color),
                filled: true,
                fillColor:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .where('email_verificado', isEqualTo: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(child: Text('Error al cargar usuarios'));
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final users = snapshot.data!.docs
                    .map((doc) => UserProfile.fromMap(
                        doc.data() as Map<String, dynamic>, doc.id))
                    .toList();

                final filteredUsers = users.where((user) {
                  final name = '${user.name} ${user.surnames}'.toLowerCase();
                  final email = user.email.toLowerCase();
                  return name.contains(_searchQuery) ||
                      email.contains(_searchQuery);
                }).toList();

                if (filteredUsers.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.person_off_rounded,
                            size: 64, color: Theme.of(context).dividerColor),
                        const SizedBox(height: 16),
                        Text(
                          'No se encontraron usuarios',
                          style: TextStyle(
                              color:
                                  Theme.of(context).textTheme.bodySmall?.color,
                              fontSize: 16),
                        ),
                      ],
                    ),
                  );
                }

                final admins = filteredUsers
                    .where((u) => u.role.toLowerCase() == 'admin')
                    .toList();
                final responsables = filteredUsers
                    .where((u) =>
                        u.role.toLowerCase() == 'responsable' ||
                        u.role.toLowerCase() == 'responsable municipal')
                    .toList();
                final ciudadanos = filteredUsers
                    .where((u) => u.role.toLowerCase() == 'ciudadano')
                    .toList();
                final otros = filteredUsers
                    .where((u) =>
                        u.role.toLowerCase() != 'admin' &&
                        u.role.toLowerCase() != 'responsable' &&
                        u.role.toLowerCase() != 'responsable municipal' &&
                        u.role.toLowerCase() != 'ciudadano')
                    .toList();

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (admins.isNotEmpty) ...[
                      _buildHeader('Administradores (${admins.length})'),
                      ...admins.map((u) => _buildUserCard(context, u)),
                      const SizedBox(height: 16),
                    ],
                    if (responsables.isNotEmpty) ...[
                      _buildHeader(
                          'Responsables municipales (${responsables.length})'),
                      ...responsables.map((u) => _buildUserCard(context, u)),
                      const SizedBox(height: 16),
                    ],
                    if (ciudadanos.isNotEmpty) ...[
                      _buildHeader('Ciudadanos (${ciudadanos.length})'),
                      ...ciudadanos.map((u) => _buildUserCard(context, u)),
                      const SizedBox(height: 16),
                    ],
                    if (otros.isNotEmpty) ...[
                      _buildHeader('Otros perfiles (${otros.length})'),
                      ...otros.map((u) => _buildUserCard(context, u)),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 12),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: Theme.of(context)
              .textTheme
              .bodySmall
              ?.color
              ?.withValues(alpha: 0.7),
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  void _showBroadcastDialog(BuildContext context) {
    final titleController = TextEditingController();
    final messageController = TextEditingController();
    bool targetCitizens = true;
    bool targetResponsibles = true;
    bool isSaving = false;
    String? imageUrl;
    final ImagePicker picker = ImagePicker();

    showDialog(
      context: context,
      barrierDismissible: !isSaving,
      builder: (context) => StatefulBuilder(builder: (context, setDialogState) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Row(
            children: [
              Icon(Icons.campaign_rounded, color: Color(0xFF6366F1)),
              SizedBox(width: 12),
              Text('Comunicado general'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Enviar a:',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                Row(
                  children: [
                    Checkbox(
                      value: targetCitizens,
                      onChanged: (val) =>
                          setDialogState(() => targetCitizens = val ?? false),
                      activeColor: const Color(0xFF6366F1),
                    ),
                    const Text('Ciudadanos'),
                  ],
                ),
                Row(
                  children: [
                    Checkbox(
                      value: targetResponsibles,
                      onChanged: (val) => setDialogState(
                          () => targetResponsibles = val ?? false),
                      activeColor: const Color(0xFF6366F1),
                    ),
                    const Text('Responsables'),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: titleController,
                  decoration: InputDecoration(
                    labelText: 'Título corto',
                    hintText: 'Ej: Mantenimiento del servicio...',
                    filled: true,
                    fillColor: Colors.grey[100],
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: messageController,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: 'Mensaje detallado',
                    hintText: 'Escribe aquí el contenido de la notificación...',
                    filled: true,
                    fillColor: Colors.grey[100],
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
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
                  onPressed: () async {
                    final XFile? image = await picker.pickImage(
                      source: ImageSource.gallery,
                      imageQuality: 50,
                      maxWidth: 1024,
                      maxHeight: 1024,
                    );
                    if (image == null) return;

                    // Validación de tipo de archivo mejorada
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
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text(
                                  'Error: "$fileName" no es una imagen permitida.')),
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
                    setDialogState(() {
                      imageUrl = url;
                      isSaving = false;
                    });
                  },
                  icon: const Icon(Icons.image_outlined),
                  label: const Text('Adjuntar imagen'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(context),
              child: const Text('Cancelar',
                  style: TextStyle(color: Color(0xFF64748B))),
            ),
            ElevatedButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      if (titleController.text.isEmpty ||
                          messageController.text.isEmpty ||
                          (!targetCitizens && !targetResponsibles)) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                              content: Text(
                                  'Por favor, rellena todos los campos y selecciona al menos un grupo destinatario.')));
                        }
                        return;
                      }

                      setDialogState(() => isSaving = true);

                      try {
                        final roles = <String>[];
                        if (targetCitizens) {
                          roles.add('Ciudadano');
                        }
                        if (targetResponsibles) {
                          roles.add('Responsable');
                          roles.add('Responsable Municipal');
                        }

                        await _notificationService.broadcastNotification(
                          roles: roles,
                          title: titleController.text.trim(),
                          body: messageController.text.trim(),
                          imageUrl: imageUrl,
                        );

                        if (context.mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                  'Comunicado enviado con éxito a todos los destinatarios.'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content:
                                    Text('Error al enviar comunicado: $e')),
                          );
                        }
                      } finally {
                        setDialogState(() => isSaving = false);
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Enviar ahora'),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildUserCard(BuildContext context, UserProfile user) {
    Color roleColor;
    IconData roleIcon;
    switch (user.role) {
      case 'admin':
        roleColor = const Color(0xFF6366F1);
        roleIcon = Icons.admin_panel_settings_rounded;
        break;
      case 'responsable':
      case 'responsable municipal':
        roleColor = const Color(0xFFF59E0B);
        roleIcon = Icons.engineering_rounded;
        break;
      default:
        roleColor = const Color(0xFF10B981);
        roleIcon = Icons.person_rounded;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
                alpha: Theme.of(context).brightness == Brightness.dark
                    ? 0.3
                    : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: user.uid == FirebaseAuth.instance.currentUser?.uid
                ? null
                : () => _showRoleAssignment(context, user),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  _buildUserAvatar(user),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${user.name} ${user.surnames}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Theme.of(context).textTheme.bodyLarge?.color,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          user.email,
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.color
                                ?.withValues(alpha: 0.7),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: roleColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(roleIcon, size: 14, color: roleColor),
                              const SizedBox(width: 4),
                              Text(
                                _formatRole(user.role),
                                style: TextStyle(
                                  color: roleColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  _buildActionButtons(context, user),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUserAvatar(UserProfile user) {
    return _buildUserAvatarFromProps(user);
  }

  String _formatRole(String role) {
    final r = role.toLowerCase();
    if (r == 'admin') {
      return 'Admin';
    }
    if (r == 'ciudadano') {
      return 'Ciudadano';
    }
    if (r == 'responsable' || r == 'responsable municipal') {
      return 'Responsable municipal';
    }
    return r;
  }

  Widget _buildUserAvatarFromProps(UserProfile user) {
    final photoUrl = user.profilePhoto;
    return photoUrl != null && photoUrl.isNotEmpty
        ? CircleAvatar(
            radius: 26,
            backgroundImage: NetworkImage(photoUrl),
          )
        : CircleAvatar(
            radius: 26,
            backgroundColor:
                Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Text(
              user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
              style: TextStyle(
                color: Theme.of(context).textTheme.bodyMedium?.color,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          );
  }

  Widget _buildActionButtons(BuildContext context, UserProfile user) {
    // No permitir que un administrador se realice acciones a sí mismo
    if (user.uid == FirebaseAuth.instance.currentUser?.uid) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.chat_bubble_outline_rounded,
                  size: 20, color: Color(0xFF6366F1)),
              onPressed: () => _showContactDialog(context, user),
              tooltip: 'Iniciar chat',
              constraints: const BoxConstraints(),
              padding: const EdgeInsets.all(8),
            ),
            IconButton(
              icon: const Icon(Icons.notifications_active_outlined,
                  size: 20, color: Color(0xFFF59E0B)),
              onPressed: () => _showNotifyDialog(context, user),
              tooltip: 'Enviar notificación',
              constraints: const BoxConstraints(),
              padding: const EdgeInsets.all(8),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.shield_outlined,
                  size: 20, color: Color(0xFF6366F1)),
              onPressed: () => _showRoleAssignment(context, user),
              tooltip: 'Gestionar permisos',
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1).withValues(alpha: 0.1),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded,
                  size: 20, color: Color(0xFFEF4444)),
              onPressed: () => _confirmDelete(context, user),
              tooltip: 'Eliminar usuario',
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444).withValues(alpha: 0.1),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showContactDialog(BuildContext context, UserProfile user) {
    final controller = TextEditingController();
    String? imageUrl;
    bool isSaving = false;
    String currentText = '';
    final ImagePicker picker = ImagePicker();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(builder: (context, setDialogState) {
        final bool canSend =
            !isSaving && (currentText.trim().isNotEmpty || imageUrl != null);

        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text('Chat con ${user.name}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  maxLines: 3,
                  onChanged: (val) => setDialogState(() => currentText = val),
                  style: TextStyle(
                      color: Theme.of(context).textTheme.bodyLarge?.color),
                  decoration: InputDecoration(
                    hintText: 'Escribe el primer mensaje...',
                    hintStyle: TextStyle(
                        color: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.color
                            ?.withValues(alpha: 0.6)),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16)),
                    filled: true,
                    fillColor:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                ),
                const SizedBox(height: 12),
                if (imageUrl != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    height: 80,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      image: DecorationImage(
                          image: NetworkImage(imageUrl!), fit: BoxFit.cover),
                    ),
                    child: Align(
                      alignment: Alignment.topRight,
                      child: IconButton(
                        icon: const Icon(Icons.close,
                            color: Colors.white, size: 18),
                        onPressed: () => setDialogState(() => imageUrl = null),
                      ),
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final XFile? image = await picker.pickImage(
                            source: ImageSource.gallery,
                            imageQuality: 50,
                            maxWidth: 1024,
                            maxHeight: 1024,
                          );
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
                                        'Error: "$fileName" no es una imagen permitida.')),
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
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: !canSend
                  ? null
                  : () async {
                      setDialogState(() => isSaving = true);
                      final ticketId = await SupportService().startAdminChat(
                        user.uid,
                        currentText.trim(),
                        imageUrl: imageUrl,
                      );
                      if (context.mounted) {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => SupportChatScreen(
                                ticketId: ticketId, isAdmin: true),
                          ),
                        );
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
                foregroundColor: Colors.white,
              ),
              child: const Text('Enviar mensaje'),
            ),
          ],
        );
      }),
    );
  }

  void _showNotifyDialog(BuildContext context, UserProfile user) {
    final titleController = TextEditingController();
    final bodyController = TextEditingController();
    String? imageUrl;
    bool isSaving = false;
    final ImagePicker picker = ImagePicker();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(builder: (context, setDialogState) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text('Notificar a ${user.name}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(labelText: 'Título'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: bodyController,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Mensaje'),
                ),
                const SizedBox(height: 12),
                if (imageUrl != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    height: 80,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      image: DecorationImage(
                          image: NetworkImage(imageUrl!), fit: BoxFit.cover),
                    ),
                    child: Align(
                      alignment: Alignment.topRight,
                      child: IconButton(
                        icon: const Icon(Icons.close,
                            color: Colors.white, size: 18),
                        onPressed: () => setDialogState(() => imageUrl = null),
                      ),
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final XFile? image = await picker.pickImage(
                            source: ImageSource.gallery,
                            imageQuality: 50,
                            maxWidth: 1024,
                            maxHeight: 1024,
                          );
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
                                        'Error: "$fileName" no es una imagen permitida.')),
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
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      if (titleController.text.isEmpty ||
                          bodyController.text.isEmpty) {
                        return;
                      }
                      setDialogState(() => isSaving = true);
                      await NotificationService().sendNotification(
                        userId: user.uid,
                        title: titleController.text.trim(),
                        body: bodyController.text.trim(),
                        type: 'oficial',
                        esOficial: true,
                        imageUrl: imageUrl,
                      );
                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Notificación enviada')),
                        );
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF59E0B),
                foregroundColor: Colors.white,
              ),
              child: const Text('Enviar notificación'),
            ),
          ],
        );
      }),
    );
  }

  void _confirmDelete(BuildContext context, UserProfile user) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar usuario'),
        content: Text(
            '¿Estás seguro de que deseas eliminar a ${user.name}? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          TextButton(
            onPressed: () async {
              try {
                await DatabaseService().deleteUserFully(user.uid, user.email);
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text(
                            'Usuario ${user.name} eliminado y bloqueado permanentemente.')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error al eliminar usuario: $e')),
                  );
                }
              }
            },
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showRoleAssignment(BuildContext context, UserProfile user) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => RoleAssignmentSheet(user: user),
    );
  }
}

class RoleAssignmentSheet extends StatefulWidget {
  final UserProfile user;
  const RoleAssignmentSheet({super.key, required this.user});

  @override
  State<RoleAssignmentSheet> createState() => _RoleAssignmentSheetState();
}

class _RoleAssignmentSheetState extends State<RoleAssignmentSheet> {
  late String _selectedRole;
  List<String> _selectedCategories = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _selectedRole = widget.user.role;
    _selectedCategories = List<String>.from(widget.user.categories ?? []);
  }

  @override
  Widget build(BuildContext context) {
    // Normalizar rol para el dropdown
    String currentRoleValue = 'ciudadano';
    final normalizedRole = _selectedRole.toLowerCase();
    if (normalizedRole == 'admin') {
      currentRoleValue = 'admin';
    }
    if (normalizedRole == 'responsable municipal' ||
        normalizedRole == 'responsable') {
      currentRoleValue = 'responsable municipal';
    }

    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Asignar rol a ${widget.user.name}',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          const Text('Rol:', style: TextStyle(fontWeight: FontWeight.bold)),
          DropdownButton<String>(
            value: currentRoleValue,
            isExpanded: true,
            items: const [
              DropdownMenuItem(value: 'ciudadano', child: Text('Ciudadano')),
              DropdownMenuItem(
                  value: 'responsable municipal',
                  child: Text('Responsable Municipal')),
              DropdownMenuItem(value: 'admin', child: Text('Admin')),
            ],
            onChanged: (val) {
              if (val != null) {
                setState(() => _selectedRole = val);
              }
            },
          ),
          if (currentRoleValue == 'responsable municipal') ...[
            const SizedBox(height: 20),
            const Text('Categorías asignadas:',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('Categoria')
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const CircularProgressIndicator();
                }
                final categories = snapshot.data!.docs;
                return Wrap(
                  spacing: 8,
                  children: categories.map((doc) {
                    final catId = doc.id;
                    final data = doc.data() as Map<String, dynamic>?;
                    final catName = data?['nombre'] ?? 'Sin nombre';
                    final isSelected = _selectedCategories.contains(catId);
                    return FilterChip(
                      label: Text(catName),
                      selected: isSelected,
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            _selectedCategories.add(catId);
                          } else {
                            _selectedCategories.remove(catId);
                          }
                        });
                      },
                    );
                  }).toList(),
                );
              },
            ),
          ],
          const SizedBox(height: 30),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _saveChanges,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6750A4),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Guardar cambios'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveChanges() async {
    setState(() {
      _isLoading = true;
    });
    try {
      await DatabaseService().updateUserRoleAndCategories(
        widget.user.uid,
        _selectedRole,
        (_selectedRole.toLowerCase() == 'responsable municipal' ||
                _selectedRole.toLowerCase() == 'responsable')
            ? _selectedCategories
            : null,
      );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cambios guardados con éxito')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar cambios: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
}
