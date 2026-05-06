import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:urbi_connect/components/google_auth_button.dart';
import 'package:urbi_connect/services/auth_service.dart';

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
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;

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

      final user = await authService.register(
        email: _emailController.text,
        password: _passwordController.text,
        name: _nameController.text,
        surnames: _surnamesController.text,
        username: _usernameController.text,
      );
      if (!mounted) return;
      setState(() => _isLoading = false);
      if (user != null) {
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
      }
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
            final bool isShortScreen = constraints.maxHeight < 800;

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
                                    textInputAction: TextInputAction.next,
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
                                    textInputAction: TextInputAction.next,
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
                                    textInputAction: TextInputAction.next,
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
                                    textInputAction: TextInputAction.next,
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
                                    obscureText: _obscurePassword,
                                    textInputAction: TextInputAction.next,
                                    decoration: InputDecoration(
                                      labelText: 'Contraseña',
                                      prefixIcon:
                                          const Icon(Icons.lock_outline),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              vertical: 12, horizontal: 16),
                                      suffixIcon: IconButton(
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
