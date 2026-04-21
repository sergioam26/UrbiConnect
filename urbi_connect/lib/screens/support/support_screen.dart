import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:urbi_connect/screens/support/support_chat_screen.dart';
import 'package:urbi_connect/services/support_service.dart';

class SupportScreen extends StatefulWidget {
  final bool isAdmin;
  const SupportScreen({super.key, this.isAdmin = false});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  final SupportService _supportService = SupportService();
  final _descriptionController = TextEditingController();

  void _showNewTicketDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Reportar problema'),
        content: TextField(
          controller: _descriptionController,
          maxLines: 4,
          decoration: InputDecoration(
            hintText: 'Describe el problema con la aplicación...',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              if (_descriptionController.text.trim().isNotEmpty) {
                await _supportService
                    .createSupportTicket(_descriptionController.text.trim());
                _descriptionController.clear();
                if (context.mounted) {
                  Navigator.pop(context);
                }
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Ticket creado con éxito')));
                }
              }
            },
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Inicia sesión')));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Soporte técnico')),
      body: StreamBuilder<QuerySnapshot>(
        stream: widget.isAdmin
            ? _supportService.getAllTickets()
            : _supportService.getUserTickets(user.uid),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final tickets = snapshot.data!.docs;

          if (tickets.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.support_agent, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  const Text('No tienes tickets de soporte activos',
                      style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: tickets.length,
            itemBuilder: (context, index) {
              final ticket = tickets[index];
              final data = ticket.data() as Map<String, dynamic>;
              final date =
                  (data['fecha'] as Timestamp?)?.toDate() ?? DateTime.now();

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: _buildStatusIndicator(data['estado']),
                  title: Text(data['descripcion'],
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(DateFormat('dd/MM HH:mm').format(date)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => SupportChatScreen(
                          ticketId: ticket.id, isAdmin: widget.isAdmin),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: !widget.isAdmin
          ? FloatingActionButton.extended(
              onPressed: _showNewTicketDialog,
              icon: const Icon(Icons.add),
              label: const Text('Nuevo reporte'),
            )
          : null,
    );
  }

  Widget _buildStatusIndicator(String status) {
    Color color;
    switch (status) {
      case 'Abierto':
        color = Colors.red;
        break;
      case 'En proceso':
        color = Colors.orange;
        break;
      case 'Cerrado':
        color = Colors.green;
        break;
      default:
        color = Colors.grey;
    }
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
