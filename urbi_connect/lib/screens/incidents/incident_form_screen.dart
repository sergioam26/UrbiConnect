import 'dart:io' show File;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:urbi_connect/models/incident.dart';
import 'package:urbi_connect/services/database_service.dart';

class IncidentFormScreen extends StatefulWidget {
  const IncidentFormScreen({super.key});

  @override
  State<IncidentFormScreen> createState() => _IncidentFormScreenState();
}

class _IncidentFormScreenState extends State<IncidentFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final DatabaseService _dbService = DatabaseService();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  String? _selectedCategoryId;
  List<Map<String, String>> _firestoreCategories = [];
  final List<XFile> _imageFiles = [];
  final List<Uint8List> _webImages = [];
  Position? _currentPosition;
  bool _isLoading = false;

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
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
        if (cats.isNotEmpty) {
          _selectedCategoryId = cats.first['id'];
        }
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

  Future<void> _pickImage(ImageSource source) async {
    try {
      if (source == ImageSource.gallery) {
        final List<XFile> pickedFiles = await _picker.pickMultiImage(
          imageQuality: 50,
          maxWidth: 800,
          maxHeight: 800,
        );
        if (pickedFiles.isNotEmpty) {
          for (var pickedFile in pickedFiles) {
            if (kIsWeb) {
              final bytes = await pickedFile.readAsBytes();
              setState(() {
                _webImages.add(bytes);
                _imageFiles.add(pickedFile);
              });
            } else {
              setState(() {
                _imageFiles.add(pickedFile);
              });
            }
          }
        }
      } else {
        final XFile? pickedFile = await _picker.pickImage(
          source: source,
          imageQuality: 50,
          maxWidth: 800,
          maxHeight: 800,
        );
        if (pickedFile != null) {
          if (kIsWeb) {
            final bytes = await pickedFile.readAsBytes();
            setState(() {
              _webImages.add(bytes);
              _imageFiles.add(pickedFile);
            });
          } else {
            setState(() {
              _imageFiles.add(pickedFile);
            });
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al acceder a la cámara/galería: $e')),
        );
      }
    }
  }

  void _removeImage(int index) {
    setState(() {
      _imageFiles.removeAt(index);
      if (kIsWeb) _webImages.removeAt(index);
    });
  }

  void _showImageSourceActionSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: const Text('Cámara'),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Galería (múltiple)'),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickImage(ImageSource.gallery);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Los servicios de ubicación están desactivados.')),
        );
      }
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Permisos de ubicación denegados.')),
          );
        }
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('Permisos de ubicación denegados permanentemente.')),
        );
      }
      return;
    }

    setState(() => _isLoading = true);
    try {
      Position position = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      setState(() {
        _currentPosition = position;
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ubicación capturada correctamente.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al obtener ubicación: $e')),
      );
    }
  }

  Future<void> _submitForm() async {
    if (_formKey.currentState!.validate()) {
      if (_imageFiles.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('Por favor, añade al menos una foto de la incidencia.')),
        );
        return;
      }

      if (_currentPosition == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Por favor, captura la ubicación GPS.')),
        );
        return;
      }

      _formKey.currentState!.save();
      setState(() => _isLoading = true);

      try {
        final List<String> imageUrls = [];

        for (int i = 0; i < _imageFiles.length; i++) {
          String? url;
          if (kIsWeb) {
            url = await _dbService.uploadImageWeb(_webImages[i]);
          } else {
            url = await _dbService.uploadImage(File(_imageFiles[i].path));
          }
          if (url != null) imageUrls.add(url);
        }

        if (imageUrls.isEmpty) {
          if (!mounted) return;
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Error al subir las imágenes.')),
          );
          return;
        }

        final user = FirebaseAuth.instance.currentUser;
        if (user == null) return;

        Incident incident = Incident(
          id: '',
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
          imageUrl: imageUrls.first, // Mantenemos el primero como principal
          imageUrls: imageUrls,
          latitude: _currentPosition!.latitude,
          longitude: _currentPosition!.longitude,
          createdAt: DateTime.now(),
          status: 'pendiente',
          userId: user.uid,
          categoryId: _selectedCategoryId ?? '',
        );

        await _dbService.createIncident(incident);

        if (!mounted) return;
        setState(() => _isLoading = false);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Incidencia enviada con éxito.')),
        );
        Navigator.pop(context);
      } catch (e) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al enviar incidencia: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nueva incidencia')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_firestoreCategories.isEmpty)
                      const LinearProgressIndicator()
                    else
                      DropdownButtonFormField<String>(
                        initialValue: _selectedCategoryId,
                        items: _firestoreCategories
                            .map((cat) => DropdownMenuItem(
                                  value: cat['id'],
                                  child: Text(cat['nombre']!,
                                      style: const TextStyle(fontSize: 12)),
                                ))
                            .toList(),
                        onChanged: (value) =>
                            setState(() => _selectedCategoryId = value),
                        decoration: const InputDecoration(
                          labelText: 'Categoría',
                          border: OutlineInputBorder(),
                        ),
                        isExpanded: true,
                      ),
                    if (_selectedCategoryId != null) ...[
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          _firestoreCategories.firstWhere((c) =>
                                  c['id'] ==
                                  _selectedCategoryId)['descripcion'] ??
                              '',
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                              fontStyle: FontStyle.italic),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _titleController,
                      decoration: const InputDecoration(
                        labelText: 'Título de la incidencia',
                        border: OutlineInputBorder(),
                        counterText: '',
                      ),
                      maxLength: 100,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Por favor, introduce un título';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _descriptionController,
                      decoration: const InputDecoration(
                        labelText: 'Descripción',
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                      maxLines: 4,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Por favor, describe el problema';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Evidencias gráficas (mín. 1):',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                            if (_imageFiles.isEmpty && _isLoading == false)
                              const Text(
                                'Obligatorio *',
                                style: TextStyle(
                                    color: Colors.red,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: _imageFiles.isEmpty
                                  ? Colors.red.withValues(alpha: 0.3)
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: SizedBox(
                            height: 100,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: _imageFiles.length + 1,
                              itemBuilder: (context, index) {
                                if (index == _imageFiles.length) {
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 8.0),
                                    child: GestureDetector(
                                      onTap: () =>
                                          _showImageSourceActionSheet(context),
                                      child: Container(
                                        width: 100,
                                        decoration: BoxDecoration(
                                          color: Colors.grey[200],
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          border: Border.all(
                                              color: Colors.grey[400]!),
                                        ),
                                        child: const Icon(
                                            Icons.add_a_photo_outlined,
                                            color: Colors.grey),
                                      ),
                                    ),
                                  );
                                }
                                return Padding(
                                  padding: const EdgeInsets.only(right: 8.0),
                                  child: Stack(
                                    children: [
                                      Container(
                                        width: 100,
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          image: DecorationImage(
                                            image: kIsWeb
                                                ? MemoryImage(_webImages[index])
                                                : FileImage(File(
                                                        _imageFiles[index]
                                                            .path))
                                                    as ImageProvider,
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        top: 4,
                                        right: 4,
                                        child: GestureDetector(
                                          onTap: () => _removeImage(index),
                                          child: Container(
                                            padding: const EdgeInsets.all(2),
                                            decoration: const BoxDecoration(
                                                color: Colors.red,
                                                shape: BoxShape.circle),
                                            child: const Icon(Icons.close,
                                                size: 16, color: Colors.white),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Ubicación del incidente:',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: _getCurrentLocation,
                          child: Container(
                            height: 80,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: _currentPosition != null
                                  ? Colors.green[50]
                                  : Colors.grey[100],
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: _currentPosition != null
                                      ? Colors.green
                                      : Colors.grey[300]!),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _currentPosition != null
                                      ? Icons.location_on
                                      : Icons.location_off,
                                  color: _currentPosition != null
                                      ? Colors.green
                                      : Colors.grey,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  _currentPosition != null
                                      ? 'Ubicación capturada correctamente'
                                      : 'Pulsa para capturar ubicación GPS',
                                  style: TextStyle(
                                    color: _currentPosition != null
                                        ? Colors.green[700]
                                        : Colors.grey[600],
                                    fontWeight: _currentPosition != null
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 40),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _submitForm,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0F172A),
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Enviar incidencia',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
