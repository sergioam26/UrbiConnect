import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:urbi_connect/services/auth_service.dart';

class GoogleAuthButton extends StatefulWidget {
  final String label;
  const GoogleAuthButton({super.key, required this.label});

  @override
  State<GoogleAuthButton> createState() => _GoogleAuthButtonState();
}

class _GoogleAuthButtonState extends State<GoogleAuthButton> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);

    return SizedBox(
      width: double.infinity,
      height: 50,
      child: OutlinedButton.icon(
        onPressed: _isLoading
            ? null
            : () async {
                final messenger = ScaffoldMessenger.of(context);
                setState(() => _isLoading = true);
                try {
                  final error = await authService.signInWithGoogle();
                  if (!mounted) return;
                  if (error != null) {
                    messenger.showSnackBar(
                      SnackBar(content: Text(error)),
                    );
                  } else {
                    // Si el login es exitoso, volvemos a la pantalla principal
                    // Esto es necesario si estamos en RegisterScreen (que fue pusheada)
                    if (Navigator.of(context).canPop()) {
                      Navigator.of(context).pop();
                    }
                  }
                } finally {
                  if (mounted) {
                    setState(() => _isLoading = false);
                  }
                }
              },
        icon: _isLoading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Image.network(
                'https://www.gstatic.com/images/branding/product/2x/googleg_96dp.png',
                height: 24,
                errorBuilder: (context, error, stackTrace) => const Icon(
                    Icons.account_circle,
                    size: 24,
                    color: Colors.blue),
              ),
        label: Text(widget.label),
        style: OutlinedButton.styleFrom(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          side: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
    );
  }
}
