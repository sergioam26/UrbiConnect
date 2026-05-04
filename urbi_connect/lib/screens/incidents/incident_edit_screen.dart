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
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;

  String? _selectedCategoryId;
  List<Map<String, String>> _firestoreCategories = [];
  final List<XFile> _imageFiles = [];
  final List<Uint8List> _webImages = [];
  List<String> _existingUrls = [];
  Position? _currentPosition;
  bool _isLoading = false;

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.incident.title);
    _descriptionController =
        TextEditingController(text: widget.incident.description);
    _selectedCategoryId = widget.incident.categoryId;
    _existingUrls = List<String>.from(widget.incident.imageUrls ??
        (widget.incident.imageUrl != null ? [widget.incident.imageUrl!] : []));
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
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submitForm() async {
    if (_formKey.currentState!.validate()) {
      if (_existingUrls.isEmpty && _imageFiles.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Por favor, añade al menos una foto')),
        );
        return;
      }

      _formKey.currentState!.save();
      setState(() => _isLoading = true);

      try {
        final List<String> allUrls = List<String>.from(_existingUrls);

        // Subir nuevas imagenes
        for (int i = 0; i < _imageFiles.length; i++) {
          String? url;
          if (kIsWeb) {
            url = await _dbService.uploadImageWeb(_webImages[i]);
          } else {
            url = await _dbService.uploadImage(File(_imageFiles[i].path));
          }
          if (url != null) allUrls.add(url);
        }

        final updatedIncident = Incident(
          id: widget.incident.id,
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
          imageUrl: allUrls.first,
          imageUrls: allUrls,
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
        Navigator.pop(context, true);
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
                        style: TextStyle(color: Color(0xFF94A3B8))),
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
                          fillColor: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                        ),
                        isExpanded: true,
                      ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _titleController,
                      decoration: InputDecoration(
                        labelText: 'Título de la incidencia',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16)),
                        filled: true,
                        fillColor: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        counterText: '',
                      ),
                      maxLength: 100,
                      validator: (value) => (value == null || value.isEmpty)
                          ? 'Introduce un título'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _descriptionController,
                      decoration: InputDecoration(
                        labelText: 'Descripción',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16)),
                        filled: true,
                        fillColor: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        alignLabelWithHint: true,
                      ),
                      maxLines: 4,
                      validator: (value) => (value == null || value.isEmpty)
                          ? 'Describe el problema'
                          : null,
                    ),
                    const SizedBox(height: 24),
                    const Text('Evidencia fotográfica (actuales y nuevas)',
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Imágenes actuales y nuevas:',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        SizedBox(
          height: 120,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              // Imágenes existentes
              ..._existingUrls.asMap().entries.map((entry) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: Stack(
                    children: [
                      Container(
                        width: 100,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          image: DecorationImage(
                              image: NetworkImage(entry.value),
                              fit: BoxFit.cover),
                        ),
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: GestureDetector(
                          onTap: () =>
                              setState(() => _existingUrls.removeAt(entry.key)),
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(
                                color: Colors.red, shape: BoxShape.circle),
                            child: const Icon(Icons.close,
                                size: 16, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
              // Imágenes nuevas
              ..._imageFiles.asMap().entries.map((entry) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: Stack(
                    children: [
                      Container(
                        width: 100,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          image: DecorationImage(
                            image: kIsWeb
                                ? MemoryImage(_webImages[entry.key])
                                : FileImage(File(entry.value.path))
                                    as ImageProvider,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: GestureDetector(
                          onTap: () => setState(() {
                            _imageFiles.removeAt(entry.key);
                            if (kIsWeb) _webImages.removeAt(entry.key);
                          }),
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(
                                color: Colors.red, shape: BoxShape.circle),
                            child: const Icon(Icons.close,
                                size: 16, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
              // Botón añadir
              GestureDetector(
                onTap: () => _showImageSourceActionSheet(context),
                child: Container(
                  width: 100,
                  decoration: BoxDecoration(
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  child: Icon(Icons.add_a_photo_outlined,
                      color: Theme.of(context).textTheme.bodySmall?.color),
                ),
              ),
            ],
          ),
        ),
      ],
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
              title: const Text('Galería (múltiple)'),
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
    try {
      if (source == ImageSource.gallery) {
        final List<XFile> pickedFiles = await _picker.pickMultiImage(
          imageQuality: 50,
          maxWidth: 1024,
          maxHeight: 1024,
        );
        if (pickedFiles.isNotEmpty) {
          for (var pickedFile in pickedFiles) {
            // Validación de tipo de archivo mejorada
            final String fileName = pickedFile.name.toLowerCase();
            final String? mimeType = pickedFile.mimeType?.toLowerCase();
            final List<String> allowedExtensions = [
              '.jpg',
              '.jpeg',
              '.png',
              '.webp',
              '.heic',
              '.heif',
              '.gif',
              '.svg',
              '.svgz',
              '.bmp',
              '.ico',
              '.tiff',
              '.tif',
              '.jfif',
              '.pjp',
              '.apng',
              '.xbm',
              '.jxl',
              '.jpe',
              '.pjpeg',
              '.avif'
            ];

            bool isImage = false;
            if (mimeType != null && mimeType.startsWith('image/')) {
              isImage = true;
            } else {
              for (var ext in allowedExtensions) {
                if (fileName.endsWith(ext)) {
                  isImage = true;
                  break;
                }
              }
            }

            if (!isImage) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text(
                          'Error: "$fileName" no es una imagen permitida.')),
                );
              }
              continue;
            }

            if (kIsWeb) {
              final bytes = await pickedFile.readAsBytes();
              setState(() {
                _webImages.add(bytes);
                _imageFiles.add(pickedFile);
              });
            } else {
              setState(() => _imageFiles.add(pickedFile));
            }
          }
        }
      } else {
        final XFile? pickedFile = await _picker.pickImage(
          source: source,
          imageQuality: 50,
          maxWidth: 1024,
          maxHeight: 1024,
        );
        if (pickedFile != null) {
          // Validación de tipo de archivo mejorada
          final String fileName = pickedFile.name.toLowerCase();
          final String? mimeType = pickedFile.mimeType?.toLowerCase();
          final List<String> allowedExtensions = [
            '.jpg',
            '.jpeg',
            '.png',
            '.webp',
            '.heic',
            '.heif',
            '.gif',
            '.svg',
            '.svgz',
            '.bmp',
            '.ico',
            '.tiff',
            '.tif',
            '.jfif',
            '.pjp',
            '.apng',
            '.xbm',
            '.jxl',
            '.jpe',
            '.pjpeg',
            '.avif'
          ];

          bool isImage = false;
          if (mimeType != null && mimeType.startsWith('image/')) {
            isImage = true;
          } else {
            for (var ext in allowedExtensions) {
              if (fileName.endsWith(ext)) {
                isImage = true;
                break;
              }
            }
          }

          if (!isImage) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content:
                        Text('Error: "$fileName" no es una imagen permitida.')),
              );
            }
            return;
          }

          if (kIsWeb) {
            final bytes = await pickedFile.readAsBytes();
            setState(() {
              _webImages.add(bytes);
              _imageFiles.add(pickedFile);
            });
          } else {
            setState(() => _imageFiles.add(pickedFile));
          }
        }
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
    }
  }
}
