import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:urbi_connect/components/google_auth_button.dart';
import 'package:urbi_connect/screens/auth/register_screen.dart';
import 'package:urbi_connect/services/auth_service.dart';
import 'package:urbi_connect/services/support_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;

  Future<void> _handleLogin(AuthService authService) async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, rellena todos los campos')),
      );
      return;
    }

    setState(() => _isLoading = true);
    final error = await authService.signIn(
      _emailController.text,
      _passwordController.text,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Calculamos si la pantalla es "corta" para reducir espacios
            final bool isShortScreen = constraints.maxHeight < 700;

            return SingleChildScrollView(
              physics: isShortScreen
                  ? const BouncingScrollPhysics()
                  : const NeverScrollableScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: constraints.maxWidth,
                  minHeight: constraints.maxHeight,
                ),
                child: IntrinsicHeight(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 500),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: 32.0,
                            vertical: isShortScreen ? 16.0 : 32.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            if (!isShortScreen) const Spacer(flex: 1),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surface,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(
                                        alpha: Theme.of(context).brightness ==
                                                Brightness.dark
                                            ? 0.3
                                            : 0.05),
                                    blurRadius: 15,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: Image.asset(
                                'assets/images/logo.png',
                                height: isShortScreen ? 60 : 100,
                                fit: BoxFit.contain,
                              ),
                            ),
                            SizedBox(height: isShortScreen ? 16 : 24),
                            Text(
                              'UrbiConnect',
                              style: GoogleFonts.montserrat(
                                fontSize: isShortScreen ? 28 : 36,
                                fontWeight: FontWeight.w900,
                                color: colorScheme.primary,
                                letterSpacing: -1.0,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Gestión de incidencias y comunicación local',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(
                                color: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.color
                                    ?.withValues(alpha: 0.7),
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            SizedBox(height: isShortScreen ? 24 : 40),
                            const GoogleAuthButton(label: 'Entrar con Google'),
                            SizedBox(height: isShortScreen ? 16 : 24),
                            Row(
                              children: [
                                Expanded(
                                    child: Divider(
                                        color: Theme.of(context)
                                            .dividerColor
                                            .withValues(alpha: 0.2))),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16),
                                  child: Text(
                                    'O usa tu correo',
                                    style: GoogleFonts.inter(
                                      color: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.color
                                          ?.withValues(alpha: 0.6),
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                ),
                                Expanded(
                                    child: Divider(
                                        color: Theme.of(context)
                                            .dividerColor
                                            .withValues(alpha: 0.2))),
                              ],
                            ),
                            SizedBox(height: isShortScreen ? 16 : 24),
                            TextField(
                              controller: _emailController,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Usuario o correo',
                                prefixIcon: Icon(Icons.alternate_email_rounded,
                                    size: 20),
                                contentPadding: EdgeInsets.symmetric(
                                    vertical: 16, horizontal: 20),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _handleLogin(authService),
                              decoration: InputDecoration(
                                labelText: 'Contraseña',
                                prefixIcon: const Icon(
                                    Icons.lock_outline_rounded,
                                    size: 20),
                                contentPadding: const EdgeInsets.symmetric(
                                    vertical: 16, horizontal: 20),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_off_rounded
                                        : Icons.visibility_rounded,
                                    size: 20,
                                  ),
                                  onPressed: () => setState(() =>
                                      _obscurePassword = !_obscurePassword),
                                ),
                              ),
                            ),
                            SizedBox(height: isShortScreen ? 20 : 24),
                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: ElevatedButton(
                                onPressed: _isLoading
                                    ? null
                                    : () => _handleLogin(authService),
                                child: _isLoading
                                    ? const SizedBox(
                                        height: 24,
                                        width: 24,
                                        child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2),
                                      )
                                    : const Text('Iniciar sesión'),
                              ),
                            ),
                            SizedBox(height: isShortScreen ? 16 : 24),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  '¿No tienes cuenta?',
                                  style: GoogleFonts.inter(
                                    color: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.color
                                        ?.withValues(alpha: 0.7),
                                    fontSize: 13,
                                  ),
                                ),
                                TextButton(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                          builder: (context) =>
                                              const RegisterScreen()),
                                    );
                                  },
                                  child: Text(
                                    'Regístrate',
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w700,
                                      color: colorScheme.secondary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            TextButton.icon(
                              onPressed: _showGuestSupportDialog,
                              icon: const Icon(Icons.help_outline_rounded,
                                  size: 16),
                              label: const Text('Soporte técnico'),
                              style: TextButton.styleFrom(
                                foregroundColor: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.color
                                    ?.withValues(alpha: 0.8),
                                textStyle: GoogleFonts.inter(
                                    fontSize: 12, fontWeight: FontWeight.w500),
                                padding: EdgeInsets.zero,
                              ),
                            ),
                            if (!isShortScreen) const Spacer(flex: 2),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _showGuestSupportDialog() {
    final nameController = TextEditingController();
    final surnameController = TextEditingController();
    final emailController = TextEditingController();
    final messageController = TextEditingController();
    final supportService = SupportService();

    showDialog(
      context: context,
      builder: (context) {
        bool isDialogLoading = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24)),
              title: const Text('Contactar soporte'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: 'Nombre'),
                      enabled: !isDialogLoading,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: surnameController,
                      decoration: const InputDecoration(labelText: 'Apellidos'),
                      enabled: !isDialogLoading,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                          labelText: 'Correo electrónico'),
                      enabled: !isDialogLoading,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: messageController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                          labelText: 'Mensaje / Problema'),
                      enabled: !isDialogLoading,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed:
                      isDialogLoading ? null : () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: isDialogLoading
                      ? null
                      : () async {
                          final name = nameController.text.trim();
                          final email = emailController.text.trim();
                          final message = messageController.text.trim();

                          if (name.isEmpty ||
                              email.isEmpty ||
                              message.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text(
                                      'Por favor, rellena todos los campos obligatorios')),
                            );
                            return;
                          }

                          // Email validation
                          final emailRegex =
                              RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
                          if (!emailRegex.hasMatch(email)) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text(
                                      'Por favor, introduce un correo electrónico válido')),
                            );
                            return;
                          }

                          setDialogState(() => isDialogLoading = true);

                          try {
                            await supportService.createGuestSupportTicket(
                              name: name,
                              surname: surnameController.text.trim(),
                              email: email,
                              message: message,
                              imageUrl: null,
                            );

                            if (context.mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        'Mensaje enviado. Te contactaremos pronto.')),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              setDialogState(() => isDialogLoading = false);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content:
                                        Text('Error al enviar el ticket: $e')),
                              );
                            }
                          }
                        },
                  child: isDialogLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Enviar'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
