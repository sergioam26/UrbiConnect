import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:urbi_connect/components/google_auth_button.dart';
import 'package:urbi_connect/services/auth_service.dart';
import 'package:url_launcher/url_launcher.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _surnamesController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  final _nameFocus = FocusNode();
  final _surnamesFocus = FocusNode();
  final _usernameFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _confirmPasswordFocus = FocusNode();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _surnamesController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _nameFocus.dispose();
    _surnamesFocus.dispose();
    _usernameFocus.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _confirmPasswordFocus.dispose();
    super.dispose();
  }

  Future<void> _handleRegister(AuthService authService) async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);

      // Check username availability
      final isAvailable =
          await authService.isUsernameAvailable(_usernameController.text);
      if (!isAvailable) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('El nombre de usuario ya está en uso. Elige otro.')),
        );
        return;
      }

      final error = await authService.register(
        email: _emailController.text,
        password: _passwordController.text,
        name: _nameController.text,
        surnames: _surnamesController.text,
        username: _usernameController.text,
      );
      if (!mounted) return;
      setState(() => _isLoading = false);

      if (error == null) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Verificación enviada'),
            content: const Text(
                'Se ha enviado un correo de verificación. Por favor, revisa tu bandeja de entrada antes de iniciar sesión.'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pop(context);
                },
                child: const Text('Entendido'),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error)),
        );
      }
    }
  }

  Future<void> _downloadApk() async {
    // Sustituye esta URL por el enlace real donde subas tu archivo app-release.apk (por ejemplo, en tu servidor Plesk)
    final Uri apkUrl = Uri.parse(
        'https://alumno21.fpcantillana.org/descargas/urbiconnect.apk');

    try {
      if (!await launchUrl(apkUrl, mode: LaunchMode.externalApplication)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('No se pudo abrir el enlace de descarga')),
          );
        }
      }
    } catch (e) {
      debugPrint('Error al descargar APK: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Registro'),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Calculamos si la pantalla es "corta" para reducir espacios
            final bool isShortScreen = constraints.maxHeight < 850;

            return SingleChildScrollView(
              physics: isShortScreen
                  ? const BouncingScrollPhysics()
                  : const AlwaysScrollableScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: constraints.maxWidth,
                  minHeight: constraints.maxHeight,
                ),
                child: IntrinsicHeight(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 450),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: 24.0,
                            vertical: isShortScreen ? 12.0 : 24.0),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
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
                              SizedBox(height: isShortScreen ? 12 : 20),
                              Text(
                                'UrbiConnect',
                                style: TextStyle(
                                  fontSize: isShortScreen ? 26 : 34,
                                  fontWeight: FontWeight.w900,
                                  color: Theme.of(context).colorScheme.primary,
                                  letterSpacing: -1,
                                ),
                              ),
                              SizedBox(height: isShortScreen ? 12 : 20),
                              Column(
                                children: [
                                  TextFormField(
                                    controller: _nameController,
                                    focusNode: _nameFocus,
                                    textInputAction: TextInputAction.next,
                                    onFieldSubmitted: (_) =>
                                        FocusScope.of(context)
                                            .requestFocus(_surnamesFocus),
                                    decoration: InputDecoration(
                                      labelText: 'Nombre',
                                      prefixIcon:
                                          const Icon(Icons.person_outline),
                                      border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(12)),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              vertical: 12, horizontal: 16),
                                    ),
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'Campo obligatorio';
                                      }
                                      return null;
                                    },
                                  ),
                                  SizedBox(height: isShortScreen ? 8 : 12),
                                  TextFormField(
                                    controller: _surnamesController,
                                    focusNode: _surnamesFocus,
                                    textInputAction: TextInputAction.next,
                                    onFieldSubmitted: (_) =>
                                        FocusScope.of(context)
                                            .requestFocus(_usernameFocus),
                                    decoration: InputDecoration(
                                      labelText: 'Apellidos',
                                      prefixIcon:
                                          const Icon(Icons.people_outline),
                                      border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(12)),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              vertical: 12, horizontal: 16),
                                    ),
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'Campo obligatorio';
                                      }
                                      return null;
                                    },
                                  ),
                                  SizedBox(height: isShortScreen ? 8 : 12),
                                  TextFormField(
                                    controller: _usernameController,
                                    focusNode: _usernameFocus,
                                    textInputAction: TextInputAction.next,
                                    onFieldSubmitted: (_) =>
                                        FocusScope.of(context)
                                            .requestFocus(_emailFocus),
                                    decoration: InputDecoration(
                                      labelText: 'Nombre de usuario',
                                      prefixIcon:
                                          const Icon(Icons.alternate_email),
                                      border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(12)),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              vertical: 12, horizontal: 16),
                                    ),
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'Campo obligatorio';
                                      }
                                      return null;
                                    },
                                  ),
                                  SizedBox(height: isShortScreen ? 8 : 12),
                                  TextFormField(
                                    controller: _emailController,
                                    focusNode: _emailFocus,
                                    textInputAction: TextInputAction.next,
                                    onFieldSubmitted: (_) =>
                                        FocusScope.of(context)
                                            .requestFocus(_passwordFocus),
                                    decoration: InputDecoration(
                                      labelText: 'Email',
                                      prefixIcon:
                                          const Icon(Icons.email_outlined),
                                      border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(12)),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              vertical: 12, horizontal: 16),
                                    ),
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'Campo obligatorio';
                                      }
                                      if (!value.contains('@')) {
                                        return 'Email inválido';
                                      }
                                      return null;
                                    },
                                  ),
                                  SizedBox(height: isShortScreen ? 8 : 12),
                                  TextFormField(
                                    controller: _passwordController,
                                    focusNode: _passwordFocus,
                                    obscureText: _obscurePassword,
                                    textInputAction: TextInputAction.next,
                                    onFieldSubmitted: (_) =>
                                        FocusScope.of(context).requestFocus(
                                            _confirmPasswordFocus),
                                    decoration: InputDecoration(
                                      labelText: 'Contraseña',
                                      prefixIcon:
                                          const Icon(Icons.lock_outline),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              vertical: 12, horizontal: 16),
                                      suffixIcon: IconButton(
                                        focusNode: FocusNode(
                                            skipTraversal:
                                                true), // Salta el botón con tabulación
                                        icon: Icon(
                                          _obscurePassword
                                              ? Icons.visibility_off
                                              : Icons.visibility,
                                          color:
                                              Theme.of(context).iconTheme.color,
                                          size: 20,
                                        ),
                                        onPressed: () {
                                          setState(() {
                                            _obscurePassword =
                                                !_obscurePassword;
                                          });
                                        },
                                      ),
                                      border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(12)),
                                    ),
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'Campo obligatorio';
                                      }
                                      if (value.length < 6) {
                                        return 'Mínimo 6 caracteres';
                                      }
                                      return null;
                                    },
                                  ),
                                  SizedBox(height: isShortScreen ? 8 : 12),
                                  TextFormField(
                                    controller: _confirmPasswordController,
                                    focusNode: _confirmPasswordFocus,
                                    obscureText: _obscureConfirmPassword,
                                    textInputAction: TextInputAction.done,
                                    onFieldSubmitted: (_) =>
                                        _handleRegister(authService),
                                    decoration: InputDecoration(
                                      labelText: 'Repetir contraseña',
                                      prefixIcon: const Icon(Icons.lock_reset),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              vertical: 12, horizontal: 16),
                                      suffixIcon: IconButton(
                                        focusNode:
                                            FocusNode(skipTraversal: true),
                                        icon: Icon(
                                          _obscureConfirmPassword
                                              ? Icons.visibility_off
                                              : Icons.visibility,
                                          color:
                                              Theme.of(context).iconTheme.color,
                                          size: 20,
                                        ),
                                        onPressed: () {
                                          setState(() {
                                            _obscureConfirmPassword =
                                                !_obscureConfirmPassword;
                                          });
                                        },
                                      ),
                                      border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(12)),
                                    ),
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'Campo obligatorio';
                                      }
                                      if (value != _passwordController.text) {
                                        return 'Las contraseñas no coinciden';
                                      }
                                      return null;
                                    },
                                  ),
                                ],
                              ),
                              SizedBox(height: isShortScreen ? 20 : 32),
                              Column(
                                children: [
                                  SizedBox(
                                    width: double.infinity,
                                    height: 50,
                                    child: ElevatedButton(
                                      onPressed: _isLoading
                                          ? null
                                          : () => _handleRegister(authService),
                                      style: ElevatedButton.styleFrom(
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12)),
                                      ),
                                      child: _isLoading
                                          ? const SizedBox(
                                              height: 20,
                                              width: 20,
                                              child: CircularProgressIndicator(
                                                  color: Colors.white,
                                                  strokeWidth: 2),
                                            )
                                          : const Text('Registrarse',
                                              style: TextStyle(
                                                  fontWeight: FontWeight.bold)),
                                    ),
                                  ),
                                  SizedBox(height: isShortScreen ? 12 : 20),
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
                                        child: Text('O regístrate con',
                                            style: TextStyle(
                                                color: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall
                                                    ?.color
                                                    ?.withValues(alpha: 0.7),
                                                fontSize: 11)),
                                      ),
                                      Expanded(
                                          child: Divider(
                                              color: Theme.of(context)
                                                  .dividerColor
                                                  .withValues(alpha: 0.2))),
                                    ],
                                  ),
                                  SizedBox(height: isShortScreen ? 12 : 16),
                                  const GoogleAuthButton(label: 'Google'),
                                ],
                              ),
                              // --- NUEVO BOTÓN DE DESCARGA APK ---
                              const SizedBox(height: 8),
                              TextButton.icon(
                                onPressed: _downloadApk,
                                icon: const Icon(Icons.android_rounded,
                                    size: 18,
                                    color:
                                        Color(0xFF3DDC84)), // Verde de Android
                                label: const Text('Descargar App para Android'),
                                style: TextButton.styleFrom(
                                  foregroundColor: const Color(0xFF3DDC84),
                                  textStyle: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600),
                                  padding: EdgeInsets.zero,
                                ),
                              ),
// ------------------------------------
                              if (!isShortScreen) const Spacer(flex: 2),
                            ],
                          ),
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
}
