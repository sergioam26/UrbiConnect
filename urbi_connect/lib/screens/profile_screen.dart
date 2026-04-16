import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:urbi_connect/models/user_profile.dart';
import 'package:urbi_connect/screens/admin/category_management_screen.dart';
import 'package:urbi_connect/screens/admin/user_management_screen.dart';
import 'package:urbi_connect/services/auth_service.dart';
import 'package:urbi_connect/services/database_service.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildHeader(context, user),
            const SizedBox(height: 24),
            _buildInfoSection(context, user),
            const SizedBox(height: 24),
            _buildActionsSection(context, authService),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, User? user) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 50,
            backgroundColor: Colors.white,
            backgroundImage:
                user?.photoURL != null ? NetworkImage(user!.photoURL!) : null,
            child: user?.photoURL == null
                ? Icon(Icons.person,
                    size: 50, color: Theme.of(context).primaryColor)
                : null,
          ),
          const SizedBox(height: 16),
          Text(
            user?.displayName ?? 'Ciudadano de Cantillana',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            user?.email ?? '',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoSection(BuildContext context, User? user) {
    return StreamBuilder<UserProfile?>(
      stream: DatabaseService().getUserProfile(user?.uid ?? ''),
      builder: (context, snapshot) {
        final profile = snapshot.data;
        final isResponsible = profile?.role == 'Responsable' ||
            profile?.role == 'Responsable Municipal';

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Información personal',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              _buildInfoTile(Icons.badge, 'Nombre de usuario',
                  user?.displayName ?? 'No configurado'),
              _buildInfoTile(Icons.email, 'Correo electrónico',
                  user?.email ?? 'No configurado'),
              _buildInfoTile(
                  Icons.verified_user,
                  'Estado de cuenta',
                  user?.emailVerified == true
                      ? 'Verificada'
                      : 'Pendiente de verificación'),
              _buildInfoTile(
                  Icons.security, 'Rol', profile?.role ?? 'Ciudadano'),
              if (isResponsible &&
                  profile?.categories != null &&
                  profile!.categories!.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text(
                  'Categorías gestionadas:',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const SizedBox(height: 4),
                FutureBuilder<QuerySnapshot>(
                  future: FirebaseFirestore.instance
                      .collection('Categoria')
                      .where(FieldPath.documentId, whereIn: profile.categories)
                      .get(),
                  builder: (context, catSnapshot) {
                    if (!catSnapshot.hasData) {
                      return const Text('Cargando categorías...');
                    }
                    final names = catSnapshot.data!.docs
                        .map((doc) => doc.get('nombre'))
                        .join(', ');
                    return Text(
                      names,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w500),
                    );
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildInfoTile(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Icon(icon, color: Colors.grey[600], size: 24),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(color: Colors.grey, fontSize: 12)),
              Text(value,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w500)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionsSection(BuildContext context, AuthService authService) {
    return StreamBuilder<UserProfile?>(
        stream: DatabaseService()
            .getUserProfile(FirebaseAuth.instance.currentUser?.uid ?? ''),
        builder: (context, snapshot) {
          final profile = snapshot.data;
          final isAdmin = profile?.role == 'Admin';

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isAdmin) ...[
                  const Text(
                    'Panel de administración',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    leading: const Icon(Icons.people, color: Colors.indigo),
                    title: const Text('Gestionar usuarios'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => const UserManagementScreen()),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.category, color: Colors.teal),
                    title: const Text('Gestionar categorías'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) =>
                                const CategoryManagementScreen()),
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                ],
                const Text(
                  'Ajustes',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(Icons.edit, color: Colors.blue),
                  title: const Text('Editar perfil'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content:
                              Text('Funcionalidad de edición próximamente.')),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.lock, color: Colors.orange),
                  title: const Text('Cambiar contraseña'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text(
                              'Funcionalidad de cambio de contraseña próximamente.')),
                    );
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.red),
                  title: const Text('Cerrar sesión',
                      style: TextStyle(color: Colors.red)),
                  onTap: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Cerrar sesión'),
                        content: const Text(
                            '¿Estás seguro de que quieres salir de UrbiConnect?'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Cancelar')),
                          TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Salir',
                                  style: TextStyle(color: Colors.red))),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      await authService.signOut();
                    }
                  },
                ),
              ],
            ),
          );
        });
  }
}
