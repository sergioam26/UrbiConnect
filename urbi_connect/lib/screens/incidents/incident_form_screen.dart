import 'package:flutter/material.dart';

class IncidentFormScreen extends StatefulWidget {
  const IncidentFormScreen({super.key});

  @override
  State<IncidentFormScreen> createState() => _IncidentFormScreenState();
}

class _IncidentFormScreenState extends State<IncidentFormScreen> {
  final _formKey = GlobalKey<FormState>();
  String _description = '';
  String _category = 'Limpieza';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nueva Incidencia')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              DropdownButtonFormField<String>(
                value: _category,
                items: ['Limpieza', 'Alumbrado', 'Vía Pública']
                    .map(
                      (label) =>
                          DropdownMenuItem(value: label, child: Text(label)),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _category = value!),
                decoration: const InputDecoration(labelText: 'Categoría'),
              ),
              TextFormField(
                decoration: const InputDecoration(labelText: 'Descripción'),
                maxLines: 3,
                validator: (value) => value == null || value.isEmpty
                    ? 'Por favor, describe el problema'
                    : null,
                onSaved: (value) => _description = value ?? '',
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () {
                  // Lógica para capturar foto
                },
                icon: const Icon(Icons.camera_alt),
                label: const Text('Tomar Foto'),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () {
                  // Lógica para capturar GPS
                },
                icon: const Icon(Icons.location_on),
                label: const Text('Capturar Ubicación GPS'),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    if (_formKey.currentState!.validate()) {
                      _formKey.currentState!.save();
                      // Ahora _description ya no está marcada como no usada
                      print('Enviando incidencia: $_description');
                      Navigator.pop(context);
                    }
                  },
                  child: const Text('ENVIAR INCIDENCIA'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
