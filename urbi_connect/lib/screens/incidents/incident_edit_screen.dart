import 'dart:io' show File;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:urbi_connect/models/incident.dart';
import 'package:urbi_connect/services/database_service.dart';

class IncidentEditScreen extends StatefulWidget {
  final Incident incident;
  const IncidentEditScreen({super.key, required this.incident});

  @override
  State<IncidentEditScreen> createState() => _IncidentEditScreenState();
}

class _IncidentEditScreenState extends State<IncidentEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final DatabaseService _dbService = DatabaseService();
  late TextEditingController _descriptionController;

  String? _selectedCategoryId;
  List<Map<String, String>> _firestoreCategories = [];
  XFile? _imageFile;
  Uint8List? _webImage;
  Position? _currentPosition;
  bool _isLoading = false;

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _descriptionController =
        TextEditingController(text: widget.incident.description);
    _selectedCategoryId = widget.incident.categoryId;
    _currentPosition = Position(
      latitude: widget.incident.latitude,
      longitude: widget.incident.longitude,
      timestamp: DateTime.now(),
      accuracy: 0,
      altitude: 0,
      heading: 0,
      speed: 0,
      speedAccuracy: 0,
      altitudeAccuracy: 0,
      headingAccuracy: 0,
    );
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      final snapshot =
          await FirebaseFirestore.instance.collection('Categoria').get();
      final cats = snapshot.docs
          .map((doc) => {
                'id': doc.id,
                'nombre': doc.get('nombre').toString(),
                'descripcion': doc.data().containsKey('descripcion')
                    ? doc.get('descripcion').toString()
                    : '',
              })
          .toList();

      setState(() {
        _firestoreCategories = cats;
      });
    } catch (e) {
      debugPrint('Error loading categories: $e');
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submitForm() async {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      setState(() => _isLoading = true);

      try {
        String? imageUrl = widget.incident.imageUrl;

        // Solo subir imagen si se ha seleccionado una nueva
        if (_imageFile != null) {
          try {
            if (kIsWeb) {
              imageUrl = await _dbService.uploadImageWeb(_webImage!);
            } else {
              imageUrl = await _dbService.uploadImage(File(_imageFile!.path));
            }
          } catch (e) {
            debugPrint('Error uploading image: $e');
          }
        }

        final updatedIncident = Incident(
          id: widget.incident.id,
          description: _descriptionController.text.trim(),
          imageUrl: imageUrl,
          latitude: _currentPosition!.latitude,
          longitude: _currentPosition!.longitude,
          createdAt: widget.incident.createdAt,
          status: widget.incident.status,
          userId: widget.incident.userId,
          categoryId: _selectedCategoryId ?? widget.incident.categoryId,
        );

        await _dbService.updateIncident(updatedIncident);

        if (!mounted) return;
        setState(() => _isLoading = false);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Incidencia actualizada con éxito.')),
        );
        Navigator.pop(context, true); // Retornamos true para indicar éxito
      } catch (e) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al actualizar incidencia: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Editar incidencia')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Editar los detalles de tu reporte',
                        style: TextStyle(color: Colors.grey)),
                    const SizedBox(height: 24),
                    if (_firestoreCategories.isEmpty)
                      const LinearProgressIndicator()
                    else
                      DropdownButtonFormField<String>(
                        initialValue: _selectedCategoryId,
                        items: _firestoreCategories
                            .map((cat) => DropdownMenuItem(
                                  value: cat['id'],
                                  child: Text(cat['nombre']!,
                                      style: const TextStyle(fontSize: 14)),
                                ))
                            .toList(),
                        onChanged: (value) =>
                            setState(() => _selectedCategoryId = value),
                        decoration: InputDecoration(
                          labelText: 'Categoría',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16)),
                          filled: true,
                          fillColor: Colors.grey.withValues(alpha: 0.05),
                        ),
                        isExpanded: true,
                      ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _descriptionController,
                      decoration: InputDecoration(
                        labelText: 'Descripción',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16)),
                        filled: true,
                        fillColor: Colors.grey.withValues(alpha: 0.05),
                        alignLabelWithHint: true,
                      ),
                      maxLines: 4,
                      validator: (value) => (value == null || value.isEmpty)
                          ? 'Describe el problema'
                          : null,
                    ),
                    const SizedBox(height: 24),
                    const Text('Evidencia fotográfica (opcional si ya existe)',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    _buildImagePreview(),
                    const SizedBox(height: 40),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _submitForm,
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              Theme.of(context).colorScheme.primary,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Guardar cambios',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildImagePreview() {
    return Container(
      height: 180,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (_imageFile != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: kIsWeb
                  ? Image.memory(_webImage!,
                      fit: BoxFit.cover, width: double.infinity)
                  : Image.file(File(_imageFile!.path),
                      fit: BoxFit.cover, width: double.infinity),
            )
          else if (widget.incident.imageUrl != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(widget.incident.imageUrl!,
                  fit: BoxFit.cover, width: double.infinity),
            )
          else
            const Icon(Icons.image_outlined, size: 48, color: Colors.grey),
          Positioned(
            bottom: 8,
            right: 8,
            child: FloatingActionButton.small(
              onPressed: () => _showImageSourceActionSheet(context),
              child: const Icon(Icons.edit),
            ),
          ),
        ],
      ),
    );
  }

  void _showImageSourceActionSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Cámara'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Galería'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    final XFile? pickedFile =
        await _picker.pickImage(source: source, imageQuality: 50);
    if (pickedFile != null) {
      if (kIsWeb) {
        final bytes = await pickedFile.readAsBytes();
        setState(() {
          _webImage = bytes;
          _imageFile = pickedFile;
        });
      } else {
        setState(() => _imageFile = pickedFile);
      }
    }
  }
}
