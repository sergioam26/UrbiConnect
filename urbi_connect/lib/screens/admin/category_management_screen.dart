import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:urbi_connect/models/category.dart';

import 'add_category_screen.dart';

class CategoryManagementScreen extends StatelessWidget {
  const CategoryManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gestión de categorías')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('Categoria').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Error al cargar categorías'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final categories = snapshot.data!.docs
              .map((doc) =>
                  Category.fromMap(doc.data() as Map<String, dynamic>, doc.id))
              .toList();

          if (categories.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('No hay categorías creadas.'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => _seedDefaultCategories(context),
                    child: const Text('Cargar categorías por defecto'),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final cat = categories[index];
              return ListTile(
                title: Text(cat.name),
                subtitle: Text(cat.description),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => _confirmDelete(context, cat),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const AddCategoryScreen()),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _seedDefaultCategories(BuildContext context) async {
    final defaults = [
      {
        'nombre': 'LIMPIEZA',
        'descripcion':
            'Esta categoría recoge incidencias relacionadas con la suciedad de las calles, así como problemas con papeleras y contenedores.'
      },
      {
        'nombre': 'ALUMBRADO',
        'descripcion':
            'Esta categoría abarca percances relacionados con la iluminación urbana, por ejemplo, farolas que no funcionan correctamente.'
      },
      {
        'nombre': 'VÍA PÚBLICA',
        'descripcion':
            'Esta categoría recoge problemas en el espacio urbano, como agujeros en calles o losas rotas.'
      },
      {
        'nombre': 'RED DE ALCANTARILLADO',
        'descripcion':
            'Incidencias como alcantarillas rotas o atascadas, malos olores, etc.'
      },
      {
        'nombre': 'CONTROL DE PLAGAS',
        'descripcion':
            'Notificaciones sobre la presencia de animales indeseados. Por ejemplo, ratas o cucarachas.'
      },
      {
        'nombre': 'JARDINERÍA',
        'descripcion':
            'Incidencias en parques o jardines, como ramas rotas o árboles caídos.'
      },
      {
        'nombre': 'TRÁFICO Y SEÑALIZACIÓN',
        'descripcion':
            'Semáforos que no funcionan, señales de tráfico caídas o borrosas, pasos de peatones dañados…'
      },
      {
        'nombre': 'MOBILIARIO URBANO',
        'descripcion':
            'Bancos rotos, marquesinas de bus dañadas, señales informativas deterioradas, farolas ornamentales dañadas.'
      },
      {
        'nombre': 'OBRAS O INFRAESTRUCTURA EN CONSTRUCCIÓN',
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
