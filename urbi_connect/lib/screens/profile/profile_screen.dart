import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:urbi_connect/models/user_profile.dart';
import 'package:urbi_connect/screens/profile/change_password_screen.dart'
    as security;
import 'package:urbi_connect/screens/profile/edit_profile_screen.dart';
import 'package:urbi_connect/screens/support/support_screen.dart';
import 'package:urbi_connect/services/auth_service.dart';
import 'package:urbi_connect/services/database_service.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: StreamBuilder<UserProfile?>(
          stream: DatabaseService().getUserProfile(user?.uid ?? ''),
          builder: (context, snapshot) {
            final profile = snapshot.data;

            return SingleChildScrollView(
              child: Column(
                children: [
                  _buildHeader(context, user, profile),
                  const SizedBox(height: 12),
                  _buildInfoSection(context, user, profile),
                  const SizedBox(height: 12),
                  _buildSettingsSection(context, authService, profile),
                  const SizedBox(height: 32),
                ],
              ),
            );
          }),
    );
  }

  Widget _buildHeader(BuildContext context, User? user, UserProfile? profile) {
    final photoUrl = profile?.profilePhoto ?? user?.photoURL;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(top: 80, bottom: 48, left: 24, right: 24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(48),
          bottomRight: Radius.circular(48),
        ),
        boxShadow: [
          BoxShadow(
            color:
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
            blurRadius: 30,
            offset: const Offset(0, 15),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white24, width: 2),
              shape: BoxShape.circle,
            ),
            child: CircleAvatar(
              radius: 56,
              backgroundColor: Colors.white,
              backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
              child: photoUrl == null
                  ? Icon(Icons.person_rounded,
                      size: 56, color: Theme.of(context).colorScheme.primary)
                  : null,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            profile != null
                ? '${profile.name} ${profile.surnames}'
                : (user?.displayName ?? 'Ciudadano'),
            textAlign: TextAlign.center,
            style: GoogleFonts.montserrat(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              profile?.email ?? (user?.email ?? ''),
              style: GoogleFonts.inter(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 12,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoSection(
      BuildContext context, User? user, UserProfile? profile) {
    final String role = profile?.role.toLowerCase() ?? '';
    final isResponsible =
        role == 'responsable' || role == 'responsable municipal';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 12, top: 24),
            child: Text(
              'Información personal',
              style: GoogleFonts.inter(
                color: const Color(0xFF94A3B8),
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: [
                _buildModernTile(
                    context,
                    Icons.alternate_email_rounded,
                    'Usuario',
                    profile?.username ?? (user?.email?.split('@')[0] ?? '-')),
                _buildDivider(),
                _buildModernTile(context, Icons.verified_user_rounded, 'Rol',
                    _capitalize(profile?.role ?? 'ciudadano')),
                _buildDivider(),
                _buildModernTile(
                  context,
                  Icons.verified_rounded,
                  'Cuenta',
                  user?.emailVerified == true ? 'Verificada' : 'No verificada',
                  valueColor: user?.emailVerified == true
                      ? const Color(0xFF059669)
                      : Colors.orange[600],
                ),
                if (isResponsible &&
                    profile?.categories != null &&
                    profile!.categories!.isNotEmpty) ...[
                  _buildDivider(),
                  _buildResponsibleCategories(context, profile.categories!),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResponsibleCategories(
      BuildContext context, List<String> categories) {
    return FutureBuilder<QuerySnapshot>(
      future: FirebaseFirestore.instance
          .collection('Categoria')
          .where(FieldPath.documentId, whereIn: categories)
          .get(),
      builder: (context, catSnapshot) {
        final names = catSnapshot.hasData
            ? catSnapshot.data!.docs.map((doc) => doc.get('nombre')).join(', ')
            : 'Cargando...';
        return _buildModernTile(
            context, Icons.category_outlined, 'Categorías', names);
      },
    );
  }

  String _capitalize(String text) {
    if (text.isEmpty) return text;
    final r = text.toLowerCase();
    if (r == 'admin') return 'Admin';
    if (r == 'ciudadano') return 'Ciudadano';
    if (r == 'responsable' || r == 'responsable municipal')
      return 'Responsable Municipal';
    return r[0].toUpperCase() + r.substring(1);
  }

  Widget _buildDivider() => const Divider(
      height: 1, indent: 64, endIndent: 20, color: Color(0xFFF1F5F9));

  Widget _buildSettingsSection(
      BuildContext context, AuthService authService, UserProfile? profile) {
    final isAdmin = profile?.role.toLowerCase() == 'admin';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 12, top: 32),
            child: Text(
              'Ajustes de cuenta',
              style: GoogleFonts.inter(
                color: const Color(0xFF94A3B8),
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: [
                _buildActionTile(
                  context,
                  Icons.edit_note_rounded,
                  'Editar perfil',
                  Colors.blue[600]!,
                  () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const EditProfileScreen())),
                ),
                _buildDivider(),
                _buildActionTile(
                  context,
                  Icons.lock_person_rounded,
                  'Cambiar contraseña',
                  Theme.of(context).colorScheme.secondary,
                  () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              const security.ChangePasswordScreen())),
                ),
                if (!isAdmin) ...[
                  _buildDivider(),
                  _buildActionTile(
                    context,
                    Icons.support_agent_rounded,
                    'Soporte técnico',
                    const Color(0xFF059669),
                    () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const SupportScreen())),
                  ),
                ],
                _buildDivider(),
                _buildActionTile(
                  context,
                  Icons.logout_rounded,
                  'Finalizar sesión',
                  Colors.red[600]!,
                  () => _showLogoutDialog(context, authService),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernTile(
      BuildContext context, IconData icon, String label, String value,
      {Color? valueColor}) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
        ),
        child:
            Icon(icon, color: Theme.of(context).colorScheme.primary, size: 20),
      ),
      title: Text(label,
          style: GoogleFonts.inter(
              fontSize: 11,
              color: const Color(0xFF94A3B8),
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4.0),
        child: Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: valueColor ?? const Color(0xFF0F172A),
          ),
        ),
      ),
    );
  }

  Widget _buildActionTile(BuildContext context, IconData icon, String title,
      Color color, VoidCallback onTap) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(title,
          style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1E293B))),
      trailing: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.chevron_right_rounded,
            color: Color(0xFFCBD5E1), size: 18),
      ),
      onTap: onTap,
    );
  }

  void _showLogoutDialog(BuildContext context, AuthService authService) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Cerrar sesión'),
        content:
            const Text('¿Estás seguro de que deseas salir de UrbiConnect?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              authService.signOut();
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Salir'),
          ),
        ],
      ),
    );
  }
}
