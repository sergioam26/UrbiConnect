import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:urbi_connect/services/auth_service.dart';
import 'package:urbi_connect/services/database_service.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _surnamesController;
  late TextEditingController _usernameController;
  late TextEditingController _emailController;
  String? _originalUsername;
  String? _originalEmail;
  String? _profilePhotoUrl;
  bool _isLoading = false;
  bool _isInit = true;
  bool _isGoogleUser = false;

  @override
  void didChangeDependencies() {
    if (_isInit) {
      final user = FirebaseAuth.instance.currentUser;
      _isGoogleUser =
          user?.providerData.any((p) => p.providerId == 'google.com') ?? false;

      _nameController = TextEditingController();
      _surnamesController = TextEditingController();
      _usernameController = TextEditingController();
      _emailController = TextEditingController();

      DatabaseService().getUserProfile(user?.uid ?? '').first.then((profile) {
        if (profile != null && mounted) {
          setState(() {
            _nameController.text = profile.name;
            _surnamesController.text = profile.surnames;
            _usernameController.text = profile.username;
            _emailController.text = profile.email;
            _originalUsername = profile.username;
            _originalEmail = profile.email;
            _profilePhotoUrl = profile.profilePhoto;
          });
        }
      });
      _isInit = false;
    }
    super.didChangeDependencies();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _surnamesController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 50);

    if (pickedFile != null) {
      // Validación de tipo de archivo mejorada
      final String fileName = pickedFile.name.toLowerCase();
      final String? mimeType = pickedFile.mimeType?.toLowerCase();
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
      // Primero intentamos por tipo MIME
      if (mimeType != null && mimeType.startsWith('image/')) {
        isImage = true;
      } else {
        // Si no hay MIME o falla, revisamos extensión
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
                content:
                    Text('Error: "$fileName" no es una imagen permitida.')),
          );
        }
        return;
      }

      if (!mounted) return;
      setState(() => _isLoading = true);
      final authService = Provider.of<AuthService>(context, listen: false);
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final imageBytes = await pickedFile.readAsBytes();
        final newUrl = await authService.uploadProfilePhoto(
          user.uid,
          imageBytes: imageBytes,
        );
        if (mounted) {
          setState(() {
            _profilePhotoUrl = newUrl;
            _isLoading = false;
          });
        }
      }
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    final authService = Provider.of<AuthService>(context, listen: false);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isLoading = true);

    // 1. Check Username availability if changed
    if (_usernameController.text.trim() != _originalUsername) {
      final isAvailable = await authService
          .isUsernameAvailable(_usernameController.text.trim());
      if (!isAvailable) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('El nombre de usuario ya está en uso')),
        );
        return;
      }
    }

    // 2. Check Email availability if changed
    if (_emailController.text.trim() != _originalEmail) {
      final isAvailable =
          await authService.isEmailAvailable(_emailController.text.trim());
      if (!isAvailable) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('El email ya está en uso por otra cuenta')),
        );
        return;
      }

      // Handle re-auth for email change
      String? password = await _showPasswordDialog();
      if (password == null) {
        setState(() => _isLoading = false);
        return;
      }

      final error = await authService.updateProfile(
        uid: user.uid,
        name: _nameController.text.trim(),
        surnames: _surnamesController.text.trim(),
        username: _usernameController.text.trim(),
        email: _emailController.text.trim(),
        currentPassword: password,
      );

      _handleUpdateResult(error);
    } else {
      // Normal update without email change
      final error = await authService.updateProfile(
        uid: user.uid,
        name: _nameController.text.trim(),
        surnames: _surnamesController.text.trim(),
        username: _usernameController.text.trim(),
      );
      _handleUpdateResult(error);
    }
  }

  void _handleUpdateResult(String? error) async {
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (error == null) {
      String message = 'Perfil actualizado correctamente';
      if (_emailController.text.trim() != _originalEmail) {
        message =
            'Se ha solicitado el cambio de email. Por favor, verifica tu nueva bandeja de entrada.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $error')),
      );
    }
  }

  Future<String?> _showPasswordDialog() {
    final passwordController = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar cambios'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
                'Para cambiar tu email es necesario confirmar tu contraseña actual.'),
            const SizedBox(height: 16),
            TextField(
              controller: passwordController,
              obscureText: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (value) => Navigator.pop(context, value),
              decoration: const InputDecoration(
                labelText: 'Contraseña',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, passwordController.text),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Editar Perfil'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Personaliza tu información pública',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Colors.grey),
              ),
              const SizedBox(height: 32),
              Center(
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 50,
                      backgroundColor:
                          Theme.of(context).primaryColor.withValues(alpha: 0.1),
                      backgroundImage: _profilePhotoUrl != null
                          ? CachedNetworkImageProvider(_profilePhotoUrl!)
                          : null,
                      child: _profilePhotoUrl == null
                          ? Icon(Icons.person,
                              size: 50, color: Theme.of(context).primaryColor)
                          : null,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: GestureDetector(
                        onTap: _pickImage,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Theme.of(context).primaryColor,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const Icon(Icons.camera_alt,
                              size: 20, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              _buildTextField(
                label: 'Nombre',
                controller: _nameController,
                icon: Icons.person_outline,
                textInputAction: TextInputAction.next,
                validator: (v) =>
                    v!.isEmpty ? 'El nombre es obligatorio' : null,
              ),
              const SizedBox(height: 20),
              _buildTextField(
                label: 'Apellidos',
                controller: _surnamesController,
                icon: Icons.badge_outlined,
                textInputAction: TextInputAction.next,
                validator: (v) =>
                    v!.isEmpty ? 'Los apellidos son obligatorios' : null,
              ),
              const SizedBox(height: 20),
              _buildTextField(
                label: 'Nombre de usuario',
                controller: _usernameController,
                icon: Icons.alternate_email,
                textInputAction: TextInputAction.next,
                validator: (v) =>
                    v!.isEmpty ? 'El usuario es obligatorio' : null,
              ),
              const SizedBox(height: 20),
              _buildTextField(
                label: 'Correo electrónico',
                controller: _emailController,
                icon: Icons.email_outlined,
                enabled: !_isGoogleUser,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _saveProfile(),
                helperText: _isGoogleUser
                    ? 'Los usuarios de Google no pueden cambiar su email desde aquí'
                    : null,
                validator: (v) {
                  if (v!.isEmpty) return 'El email es obligatorio';
                  if (!v.contains('@')) return 'Email inválido';
                  return null;
                },
              ),
              const SizedBox(height: 48),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _saveProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Guardar cambios',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    TextInputAction? textInputAction,
    Function(String)? onFieldSubmitted,
    String? Function(String?)? validator,
    bool enabled = true,
    String? helperText,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      enabled: enabled,
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
      decoration: InputDecoration(
        labelText: label,
        helperText: helperText,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        filled: true,
        fillColor: enabled
            ? Colors.grey.withValues(alpha: 0.05)
            : Colors.grey.withValues(alpha: 0.1),
      ),
    );
  }
}
