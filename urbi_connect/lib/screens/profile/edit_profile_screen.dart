import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
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
  bool _isLoading = false;
  bool _isInit = true;

  @override
  void didChangeDependencies() {
    if (_isInit) {
      final user = FirebaseAuth.instance.currentUser;
      _nameController = TextEditingController();
      _surnamesController = TextEditingController();
      _usernameController = TextEditingController();

      DatabaseService().getUserProfile(user?.uid ?? '').first.then((profile) {
        if (profile != null) {
          setState(() {
            _nameController.text = profile.name;
            _surnamesController.text = profile.surnames;
            _usernameController.text = profile.username;
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
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    final authService = Provider.of<AuthService>(context, listen: false);
    final user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      final error = await authService.updateProfile(
        uid: user.uid,
        name: _nameController.text.trim(),
        surnames: _surnamesController.text.trim(),
        username: _usernameController.text.trim(),
      );

      if (!mounted) return;
      setState(() => _isLoading = false);

      if (error == null) {
        // Actualizar el nombre en Firebase Auth también
        await user.updateDisplayName(
            '${_nameController.text.trim()} ${_surnamesController.text.trim()}');

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Perfil actualizado correctamente')),
        );
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $error')),
        );
      }
    }
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
              _buildTextField(
                label: 'Nombre',
                controller: _nameController,
                icon: Icons.person_outline,
                validator: (v) =>
                    v!.isEmpty ? 'El nombre es obligatorio' : null,
              ),
              const SizedBox(height: 20),
              _buildTextField(
                label: 'Apellidos',
                controller: _surnamesController,
                icon: Icons.badge_outlined,
                validator: (v) =>
                    v!.isEmpty ? 'Los apellidos son obligatorios' : null,
              ),
              const SizedBox(height: 20),
              _buildTextField(
                label: 'Nombre de usuario',
                controller: _usernameController,
                icon: Icons.alternate_email,
                validator: (v) =>
                    v!.isEmpty ? 'El usuario es obligatorio' : null,
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
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        filled: true,
        fillColor: Colors.grey.withValues(alpha: 0.05),
      ),
    );
  }
}
