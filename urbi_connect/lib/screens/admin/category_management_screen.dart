import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:urbi_connect/models/category.dart';

import 'add_category_screen.dart';

class CategoryManagementScreen extends StatefulWidget {
  const CategoryManagementScreen({super.key});

  @override
  State<CategoryManagementScreen> createState() =>
      _CategoryManagementScreenState();
}

class _CategoryManagementScreenState extends State<CategoryManagementScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          'Categorías de incidencias',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        elevation: 0,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: Theme.of(context).textTheme.titleLarge?.color,
      ),
      body: Column(
        children: [
          Container(
            color: Theme.of(context).scaffoldBackgroundColor,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: TextField(
              controller: _searchController,
              onChanged: (value) =>
                  setState(() => _searchQuery = value.toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Buscar categorías...',
                prefixIcon: Icon(Icons.search,
                    color: Theme.of(context).textTheme.bodySmall?.color),
                filled: true,
                fillColor:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('Categoria')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(
                      child: Text('Error al cargar categorías'));
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final categories = snapshot.data!.docs
                    .map((doc) => Category.fromMap(
                        doc.data() as Map<String, dynamic>, doc.id))
                    .toList();

                final filteredCategories = categories.where((cat) {
                  return cat.name.toLowerCase().contains(_searchQuery) ||
                      cat.description.toLowerCase().contains(_searchQuery);
                }).toList();

                if (categories.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.category_outlined,
                            size: 64, color: Colors.grey[300]),
                        const SizedBox(height: 16),
                        const Text('No hay categorías creadas.'),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () => _seedDefaultCategories(context),
                          icon: const Icon(Icons.auto_awesome_rounded),
                          label: const Text('Cargar por defecto'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6366F1),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                if (filteredCategories.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.search_off_rounded,
                            size: 64, color: Colors.grey[300]),
                        const SizedBox(height: 16),
                        Text(
                          'No se encontraron categorías',
                          style:
                              TextStyle(color: Colors.grey[600], fontSize: 16),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: filteredCategories.length,
                  itemBuilder: (context, index) {
                    final cat = filteredCategories[index];
                    return _buildCategoryCard(context, cat);
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const AddCategoryScreen()),
          );
        },
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Nueva categoría'),
      ),
    );
  }

  Widget _buildCategoryCard(BuildContext context, Category cat) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
                alpha: Theme.of(context).brightness == Brightness.dark
                    ? 0.3
                    : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child:
                  const Icon(Icons.category_rounded, color: Color(0xFF6366F1)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    cat.name,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Theme.of(context).textTheme.titleMedium?.color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    cat.description,
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.color
                          ?.withValues(alpha: 0.7),
                      height: 1.4,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded,
                  color: Color(0xFFEF4444)),
              onPressed: () => _confirmDelete(context, cat),
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444).withValues(alpha: 0.1),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _seedDefaultCategories(BuildContext context) async {
    final defaults = [
      {
        'nombre': 'Limpieza',
        'descripcion':
            'Esta categoría recoge incidencias relacionadas con la suciedad de las calles, así como problemas con papeleras y contenedores.'
      },
      {
        'nombre': 'Alumbrado',
        'descripcion':
            'Esta categoría abarca percances relacionados con la iluminación urbana, por ejemplo, farolas que no funcionan correctamente.'
      },
      {
        'nombre': 'Vía pública',
        'descripcion':
            'Esta categoría recoge problemas en el espacio urbano, como agujeros en calles o losas rotas.'
      },
      {
        'nombre': 'Red de alcantarillado',
        'descripcion':
            'Incidencias como alcantarillas rotas o atascadas, malos olores, etc.'
      },
      {
        'nombre': 'Control de plagas',
        'descripcion':
            'Notificaciones sobre la presencia de animales indeseados. Por ejemplo, ratas o cucarachas.'
      },
      {
        'nombre': 'Jardinería',
        'descripcion':
            'Incidencias en parques o jardines, como ramas rotas o árboles caídos.'
      },
      {
        'nombre': 'Tráfico y señalización',
        'descripcion':
            'Semáforos que no funcionan, señales de tráfico caídas o borrosas, pasos de peatones dañados…'
      },
      {
        'nombre': 'Mobiliario urbano',
        'descripcion':
            'Bancos rotos, marquesinas de bus dañadas, señales informativas deterioradas, farolas ornamentales dañadas.'
      },
      {
        'nombre': 'Obras o infraestructura en construcción',
        'descripcion':
            'Barreras mal señalizadas, zonas peligrosas, calles cortadas sin aviso.'
      },
    ];

    final collection = FirebaseFirestore.instance.collection('Categoria');

    try {
      for (var cat in defaults) {
        await collection.add(cat);
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Categorías por defecto cargadas.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar categorías: $e')),
        );
      }
    }
  }

  void _confirmDelete(BuildContext context, Category category) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar categoría'),
        content: Text(
            '¿Estás seguro de que deseas eliminar la categoría "${category.name}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          TextButton(
            onPressed: () async {
              await FirebaseFirestore.instance
                  .collection('Categoria')
                  .doc(category.id)
                  .delete();
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
