import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:urbi_connect/models/user_profile.dart';
import 'package:urbi_connect/services/auth_service.dart';
import 'package:urbi_connect/services/database_service.dart';

import 'admin/category_management_screen.dart';
import 'admin/user_management_screen.dart';
import 'incidents/incident_form_screen.dart';
import 'incidents/incident_list_screen.dart';
import 'notifications/notification_list_screen.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  List<Widget> _getPages(bool isAdmin) {
    if (isAdmin) {
      return [
        const AdminDashboard(),
        const NotificationListScreen(),
        const ProfileScreen(),
      ];
    }
    return [
      const IncidentListScreen(),
      const NotificationListScreen(),
      const ProfileScreen(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return StreamBuilder<UserProfile?>(
      stream: DatabaseService().getUserProfile(user.uid),
      builder: (context, profileSnapshot) {
        final profile = profileSnapshot.data;
        final isAdmin = profile?.role == 'Admin';
        final isResponsible = profile?.role == 'Responsable' ||
            profile?.role == 'Responsable Municipal';

        final pages = _getPages(isAdmin);

        return Scaffold(
          appBar: AppBar(
            title: const Text('UrbiConnect'),
            actions: [
              IconButton(
                icon: const Icon(Icons.logout),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Cerrar sesión'),
                      content: const Text(
                          '¿Estás seguro de que deseas salir de la aplicación?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancelar'),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.pop(context);
                            Provider.of<AuthService>(context, listen: false)
                                .signOut();
                          },
                          child: const Text('Salir',
                              style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    ),
                  );
                },
              )
            ],
          ),
          body: pages[_selectedIndex],
          floatingActionButton:
              (_selectedIndex == 0 && !isResponsible && !isAdmin)
                  ? FloatingActionButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => const IncidentFormScreen()),
                        );
                      },
                      child: const Icon(Icons.add),
                    )
                  : null,
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _selectedIndex,
            onTap: (index) => setState(() => _selectedIndex = index),
            items: [
              BottomNavigationBarItem(
                icon: Icon(isAdmin ? Icons.admin_panel_settings : Icons.home),
                label: isAdmin ? 'Admin' : 'Inicio',
              ),
              const BottomNavigationBarItem(
                  icon: Icon(Icons.notifications), label: 'Buzón'),
              const BottomNavigationBarItem(
                  icon: Icon(Icons.person), label: 'Perfil'),
            ],
          ),
        );
      },
    );
  }
}

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Panel de administración',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          _buildAdminCard(
            context,
            title: 'Gestionar usuarios',
            subtitle: 'Consultar y eliminar usuarios registrados',
            icon: Icons.people,
            color: Colors.indigo,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) => const UserManagementScreen()),
            ),
          ),
          const SizedBox(height: 16),
          _buildAdminCard(
            context,
            title: 'Gestionar categorías',
            subtitle: 'Crear, editar y eliminar categorías de incidencias',
            icon: Icons.category,
            color: Colors.teal,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) => const CategoryManagementScreen()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdminCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.1),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
