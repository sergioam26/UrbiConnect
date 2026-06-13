import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:urbi_connect/config/app_config.dart';
import 'package:urbi_connect/models/user_profile.dart';
import 'package:urbi_connect/screens/profile/change_password_screen.dart'
    as security;
import 'package:urbi_connect/screens/profile/edit_profile_screen.dart';
import 'package:urbi_connect/screens/support/support_screen.dart';
import 'package:urbi_connect/services/auth_service.dart';
import 'package:urbi_connect/services/notification_service.dart';
import 'package:urbi_connect/services/theme_service.dart';

class ProfileScreen extends StatefulWidget {
  final UserProfile profile;
  const ProfileScreen({super.key, required this.profile});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  List<String>? _localPushRoles;

  @override
  void initState() {
    super.initState();
    _syncEmail();
    _localPushRoles = widget.profile.enabledPushRoles != null
        ? List<String>.from(widget.profile.enabledPushRoles!)
        : ['admin', 'responsable', 'ciudadano'];
  }

  @override
  void didUpdateWidget(covariant ProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.profile.enabledPushRoles != oldWidget.profile.enabledPushRoles) {
      _localPushRoles = widget.profile.enabledPushRoles != null
          ? List<String>.from(widget.profile.enabledPushRoles!)
          : ['admin', 'responsable', 'ciudadano'];
    }
  }

  Future<void> _syncEmail() async {
    // Sync email when entering profile screen
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Provider.of<AuthService>(context, listen: false)
            .syncEmailWithFirestore();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: RefreshIndicator(
        onRefresh: () => authService.syncEmailWithFirestore(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              _buildHeader(context, user, widget.profile),
              const SizedBox(height: 12),
              _buildInfoSection(context, user, widget.profile),
              const SizedBox(height: 12),
              _buildSettingsSection(context, authService, widget.profile),
              if (widget.profile.email.toLowerCase() ==
                  AppConfig.superUserEmail.toLowerCase()) ...[
                const SizedBox(height: 12),
                _buildSuperuserPushSettings(context, widget.profile),
              ],
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, User? user, UserProfile? profile) {
    final photoUrl = profile?.profilePhoto ?? user?.photoURL;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(top: 80, bottom: 48, left: 24, right: 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Theme.of(context).colorScheme.primary,
            Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
          ],
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(48),
          bottomRight: Radius.circular(48),
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
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
              backgroundColor: Theme.of(context).colorScheme.surface,
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
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white
                  : Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(
                  alpha: Theme.of(context).brightness == Brightness.dark
                      ? 0.2
                      : 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              profile?.email ?? (user?.email ?? ''),
              style: GoogleFonts.inter(
                color: Colors.white.withValues(alpha: 0.9),
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
                color: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.color
                    ?.withValues(alpha: 0.5),
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant),
            ),
            child: Column(
              children: [
                _buildModernTile(
                    context,
                    Icons.alternate_email_rounded,
                    'Usuario',
                    profile?.username ?? (user?.email?.split('@')[0] ?? '-')),
                _buildDivider(context),
                _buildModernTile(context, Icons.verified_user_rounded, 'Rol',
                    _formatRole(profile?.role ?? 'ciudadano')),
                _buildDivider(context),
                _buildModernTile(
                  context,
                  Icons.verified_rounded,
                  'Cuenta',
                  user?.emailVerified == true ? 'Verificada' : 'No verificada',
                  valueColor: user?.emailVerified == true
                      ? const Color(0xFF0F172A)
                      : const Color(0xFFF59E0B),
                ),
                if (isResponsible &&
                    profile?.categories != null &&
                    profile!.categories!.isNotEmpty) ...[
                  _buildDivider(context),
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

  String _formatRole(String text) {
    if (text.isEmpty) {
      return text;
    }
    final r = text.toLowerCase();
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

  Widget _buildDivider(BuildContext context) => Divider(
      height: 1,
      indent: 64,
      endIndent: 20,
      color: Theme.of(context).dividerColor.withValues(alpha: 0.1));

  Widget _buildSettingsSection(
      BuildContext context, AuthService authService, UserProfile? profile) {
    if (profile == null) return const SizedBox.shrink();
    final themeService = Provider.of<ThemeService>(context);

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
                color: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.color
                    ?.withValues(alpha: 0.5),
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant),
            ),
            child: Column(
              children: [
                _buildThemeTile(context, themeService),
                _buildDivider(context),
                _buildActionTile(
                  context,
                  Icons.edit_note_rounded,
                  'Editar perfil',
                  Theme.of(context).colorScheme.primary, // Prof. Primary
                  () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const EditProfileScreen()),
                    );
                  },
                ),
                _buildDivider(context),
                _buildActionTile(
                  context,
                  Icons.lock_person_rounded,
                  'Cambiar contraseña',
                  Theme.of(context).colorScheme.secondary,
                  () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              const security.ChangePasswordScreen()),
                    );
                  },
                ),
                if (profile?.role.toLowerCase() != 'admin' &&
                    profile?.email.toLowerCase() !=
                        AppConfig.superUserEmail.toLowerCase()) ...[
                  _buildDivider(context),
                  _buildActionTile(
                    context,
                    Icons.support_agent_rounded,
                    'Soporte técnico',
                    Theme.of(context).colorScheme.primary,
                    () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                const SupportScreen(isAdmin: false)),
                      );
                    },
                  ),
                ],
                if (profile?.email.toLowerCase() ==
                    AppConfig.superUserEmail.toLowerCase()) ...[
                  _buildDivider(context),
                  _buildActionTile(
                    context,
                    Icons.supervised_user_circle_rounded,
                    'Conmutar rol activo (Súper usuario)',
                    Colors.amber[700]!,
                    () => _showSuperuserSwitcher(
                        context, profile.uid, profile.role),
                  ),
                ],
                _buildDivider(context),
                _buildActionTile(
                  context,
                  Icons.logout_rounded,
                  'Finalizar sesión',
                  const Color(0xFFEF4444),
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
              color: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.color
                  ?.withValues(alpha: 0.5),
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4.0),
        child: Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: valueColor ?? Theme.of(context).textTheme.bodyLarge?.color,
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
              color: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.color
                  ?.withValues(alpha: 0.9))),
      trailing: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(Icons.chevron_right_rounded,
            color: Theme.of(context).dividerColor, size: 18),
      ),
      onTap: onTap,
    );
  }

  Widget _buildThemeTile(BuildContext context, ThemeService themeService) {
    final isDark = themeService.isDarkMode;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: (isDark ? const Color(0xFFF59E0B) : const Color(0xFF3B82F6))
              .withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(
          isDark ? Icons.wb_sunny_rounded : Icons.nightlight_round,
          color: isDark ? const Color(0xFFF59E0B) : const Color(0xFF3B82F6),
          size: 20,
        ),
      ),
      title: Text(
        'Modo Oscuro',
        style: GoogleFonts.inter(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: Theme.of(context)
              .textTheme
              .bodyLarge
              ?.color
              ?.withValues(alpha: 0.9),
        ),
      ),
      trailing: Switch.adaptive(
        value: isDark,
        activeColor: const Color(0xFF3B82F6),
        onChanged: (value) => themeService.toggleTheme(value),
      ),
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

  void _showSuperuserSwitcher(
      BuildContext context, String uid, String currentRole) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.shield_rounded,
                    color: Colors.amber, size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Simulador de rol',
                  style: GoogleFonts.montserrat(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Como súper usuario, puedes simular cualquiera de los roles del sistema. Las vistas, accesos y permisos se actualizarán de forma instantánea.',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white70
                      : Colors.black54,
                ),
              ),
              const SizedBox(height: 20),
              _buildRoleSwitcherOption(
                context,
                uid: uid,
                roleValue: 'admin',
                label: 'Administrador',
                icon: Icons.admin_panel_settings_rounded,
                color: Colors.blueGrey,
                isSelected: currentRole == 'admin',
              ),
              const SizedBox(height: 12),
              _buildRoleSwitcherOption(
                context,
                uid: uid,
                roleValue: 'responsable',
                label: 'Responsable municipal',
                icon: Icons.engineering_rounded,
                color: Colors.teal,
                isSelected: currentRole == 'responsable' ||
                    currentRole == 'responsable municipal',
              ),
              const SizedBox(height: 12),
              _buildRoleSwitcherOption(
                context,
                uid: uid,
                roleValue: 'ciudadano',
                label: 'Ciudadano',
                icon: Icons.person_rounded,
                color: Theme.of(context).colorScheme.primary,
                isSelected: currentRole == 'ciudadano',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildRoleSwitcherOption(
    BuildContext context, {
    required String uid,
    required String roleValue,
    required String label,
    required IconData icon,
    required Color color,
    required bool isSelected,
  }) {
    return InkWell(
      onTap: () async {
        Navigator.pop(context);
        try {
          final currentUser = FirebaseAuth.instance.currentUser;
          final isSuperuser = currentUser?.email?.toLowerCase() ==
              AppConfig.superUserEmail.toLowerCase();
          if (isSuperuser) {
            SuperuserSession.simulatedRole = roleValue;
          } else {
            final updates = <String, dynamic>{'rol': roleValue};
            await FirebaseFirestore.instance
                .collection('users')
                .doc(uid)
                .update(updates);
          }
          await NotificationService().syncFcmTokenState();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded, color: Colors.white),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                          'Rol simulado cambiado a ${label.toLowerCase()} con éxito.'),
                    ),
                  ],
                ),
                backgroundColor: color,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error al cambiar rol: $e'),
                backgroundColor: Colors.red,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? color
                : Theme.of(context).colorScheme.outlineVariant,
            width: isSelected ? 2 : 1,
          ),
          color: isSelected
              ? color.withValues(alpha: 0.08)
              : Theme.of(context).colorScheme.surface,
        ),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? color : Colors.grey, size: 24),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.inter(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  fontSize: 14,
                  color: isSelected
                      ? color
                      : Theme.of(context).textTheme.bodyLarge?.color,
                ),
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle_rounded, color: color, size: 20)
            else
              const Icon(Icons.circle_outlined, color: Colors.grey, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSuperuserPushSettings(
      BuildContext context, UserProfile profile) {
    _localPushRoles ??= List<String>.from(
        profile.enabledPushRoles ?? ['admin', 'responsable', 'ciudadano']);
    final List<String> currentRoles = _localPushRoles!;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 12, top: 24),
            child: Text(
              'NOTIFICACIONES PUSH POR ROL',
              style: GoogleFonts.inter(
                color: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.color
                    ?.withValues(alpha: 0.5),
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant),
            ),
            child: Column(
              children: [
                _buildPushRoleSwitch(
                  context,
                  roleKey: 'admin',
                  label: 'Administrador',
                  subtitle:
                      'Mensajes de soporte y alertas globales de administración',
                  icon: Icons.admin_panel_settings_rounded,
                  color: Colors.blue,
                  isSelected: currentRoles.contains('admin'),
                  profile: profile,
                ),
                _buildDivider(context),
                _buildPushRoleSwitch(
                  context,
                  roleKey: 'responsable',
                  label: 'Responsable municipal',
                  subtitle: 'Nuevas incidencias creadas de tus categorías',
                  icon: Icons.supervised_user_circle_rounded,
                  color: Colors.amber[700]!,
                  isSelected: currentRoles.contains('responsable'),
                  profile: profile,
                ),
                _buildDivider(context),
                _buildPushRoleSwitch(
                  context,
                  roleKey: 'ciudadano',
                  label: 'Ciudadano',
                  subtitle:
                      'Actualizaciones de estado sobre incidencias y respuestas',
                  icon: Icons.person_rounded,
                  color: Colors.green,
                  isSelected: currentRoles.contains('ciudadano'),
                  profile: profile,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPushRoleSwitch(
    BuildContext context, {
    required String roleKey,
    required String label,
    required String subtitle,
    required IconData icon,
    required Color color,
    required bool isSelected,
    required UserProfile profile,
  }) {
    return SwitchListTile(
      value: isSelected,
      activeColor: Theme.of(context).colorScheme.primary,
      secondary: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).textTheme.bodyLarge?.color,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: GoogleFonts.inter(
          fontSize: 11,
          color: Theme.of(context).textTheme.bodySmall?.color,
        ),
      ),
      onChanged: (bool value) async {
        setState(() {
          _localPushRoles ??= List<String>.from(profile.enabledPushRoles ??
              ['admin', 'responsable', 'ciudadano']);
          final List<String> variations = [];
          if (roleKey == 'responsable') {
            variations.addAll([
              'responsable',
              'responsable_municipal',
              'responsable municipal',
              'Responsable',
              'Responsable Municipal',
              'Responsable municipal',
            ]);
          } else if (roleKey == 'admin') {
            variations.addAll(['admin', 'Admin', 'ADMIN']);
          } else if (roleKey == 'ciudadano') {
            variations.addAll(['ciudadano', 'Ciudadano', 'CIUDADANO']);
          } else {
            variations.add(roleKey);
          }

          if (value) {
            for (var v in variations) {
              if (!_localPushRoles!.contains(v)) {
                _localPushRoles!.add(v);
              }
            }
          } else {
            for (var v in variations) {
              _localPushRoles!.remove(v);
            }
          }
        });

        try {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(profile.uid)
              .update({'enabled_push_roles': _localPushRoles});

          try {
            final prefs = await SharedPreferences.getInstance();
            if (_localPushRoles != null) {
              await prefs.setStringList('enabled_push_roles', _localPushRoles!);
            }
          } catch (e) {
            debugPrint(
                'Error actualizando caché local en SharedPreferences: $e');
          }

          await NotificationService().syncFcmTokenState();

          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content:
                    Text('Ajuste de notificación para $label actualizado.'),
                backgroundColor: color,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            );
          }
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error al actualizar notificaciones: $e'),
                backgroundColor: Colors.red,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      },
    );
  }
}
