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
                final error = await authService.signInWithGoogle();
                if (!mounted) return;
                setState(() => _isLoading = false);
                if (error != null) {
                  messenger.showSnackBar(
                    SnackBar(content: Text(error)),
                  );
                }
              },
        icon: _isLoading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Image.network(
                'https://upload.wikimedia.org/wikipedia/commons/thumb/c/c1/Google_"G"_logo.svg/1200px-Google_"G"_logo.svg.png',
                height: 24,
              ),
        label:
            Text(widget.label, style: const TextStyle(color: Colors.black87)),
        style: OutlinedButton.styleFrom(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          side: const BorderSide(color: Colors.grey),
        ),
      ),
    );
  }
}
