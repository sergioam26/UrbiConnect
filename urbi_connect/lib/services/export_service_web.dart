import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';

import '../models/incident.dart';

class ExportPlatformService {
  static Future<void> exportIncidentsToCSV(List<Incident> incidents,
      Map<String, String> categoryNames, Map<String, String> userEmails) async {
    final StringBuffer csvBuffer = StringBuffer();

    // Cabeceras de columna descriptivas respetando mayúsculas en español (separadas por punto y coma ';')
    csvBuffer.writeln(
        'ID;Título;Descripción;Estado;Dirección;Latitud;Longitud;Fecha de creación;Última actualización;Categoría;Usuario (correo electrónico)');

    for (final incident in incidents) {
      final id = _escapeCsvValue(incident.id);
      final title = _escapeCsvValue(incident.title);
      final description = _escapeCsvValue(incident.description);
      final status = _escapeCsvValue(_translateStatus(incident.status));
      final address = _escapeCsvValue(incident.address ?? 'Sin dirección');
      final lat = incident.latitude.toString();
      final lng = incident.longitude.toString();
      final createdAt = incident.createdAt.toLocal().toString();
      final updatedAt = incident.updatedAt != null
          ? incident.updatedAt!.toLocal().toString()
          : 'Sin modificaciones';

      final category = _escapeCsvValue(categoryNames[incident.categoryId] ??
          (incident.categoryId.isEmpty
              ? 'Sin categoría'
              : 'Categoría no registrada'));

      final emailValue = userEmails[incident.userId] ??
          (incident.userId.isEmpty || incident.userId == 'anonimo'
              ? 'Anónimo'
              : 'Usuario no registrado / Eliminado');
      final userEmail = _escapeCsvValue(emailValue);

      csvBuffer.writeln(
          '$id;$title;$description;$status;$address;$lat;$lng;$createdAt;$updatedAt;$category;$userEmail');
    }

    // Prependemos explícitamente los 3 bytes del BOM UTF-8 (0xEF, 0xBB, 0xBF)
    // para indicar a Excel de forma indiscutible que la codificación es UTF-8.
    final List<int> contentBytes = utf8.encode(csvBuffer.toString());
    final Uint8List bytes =
        Uint8List.fromList([0xEF, 0xBB, 0xBF, ...contentBytes]);
    final blob = html.Blob([bytes], 'text/csv;charset=utf-8');
    final url = html.Url.createObjectUrlFromBlob(blob);

    final now = DateTime.now();
    final String timestamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';

    html.AnchorElement(href: url)
      ..setAttribute('download', 'incidencias_urbiconnect_$timestamp.csv')
      ..click();

    html.Url.revokeObjectUrl(url);
  }

  static Future<void> exportIncidentsToPDF(List<Incident> incidents,
      Map<String, String> categoryNames, Map<String, String> userEmails) async {
    final StringBuffer rowsBuffer = StringBuffer();
    for (final inc in incidents) {
      final statusText = _translateStatus(inc.status);
      final statusClass = inc.status == 'pendiente'
          ? 'pending'
          : inc.status == 'en proceso'
              ? 'process'
              : 'resolved';
      final formattedDate =
          '${inc.createdAt.day.toString().padLeft(2, '0')}/${inc.createdAt.month.toString().padLeft(2, '0')}/${inc.createdAt.year} ${inc.createdAt.hour.toString().padLeft(2, '0')}:${inc.createdAt.minute.toString().padLeft(2, '0')}';

      final catName = categoryNames[inc.categoryId] ??
          (inc.categoryId.isEmpty
              ? 'Sin categoría'
              : 'Categoría no registrada');

      final idLen = inc.id.length;
      final shortId = inc.id.substring(0, idLen < 6 ? idLen : 6).toUpperCase();
      final reporterEmail = userEmails[inc.userId] ??
          (inc.userId.isEmpty || inc.userId == 'anonimo'
              ? 'Anónimo'
              : 'Usuario no registrado / Eliminado');

      rowsBuffer.write('''
        <tr>
          <td style="font-weight: bold; color: #475569;">#$shortId</td>
          <td>
            <b>${_escapeHtml(inc.title)}</b><br/>
            <span style="font-size: 11px; color: #64748b;">${_escapeHtml(inc.description)}</span><br/>
            <span style="font-size: 10px; color: #0284c7; font-weight: 500;">Reportado por: ${_escapeHtml(reporterEmail)}</span>
          </td>
          <td>${_escapeHtml(catName)}</td>
          <td><span class="badge $statusClass">${_escapeHtml(statusText)}</span></td>
          <td style="font-size: 11px;">${_escapeHtml(inc.address ?? 'Sin dirección')}</td>
          <td>$formattedDate</td>
        </tr>
      ''');
    }

    final String htmlContent = '''
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="utf-8">
        <title>Reporte de incidencias - UrbiConnect Cantillana</title>
        <style>
          body { font-family: 'Helvetica Neue', Helvetica, Arial, sans-serif; padding: 40px; color: #1e293b; background: white; margin: 0; }
          .header-container { display: flex; align-items: center; justify-content: space-between; border-bottom: 3px solid #0284c7; padding-bottom: 20px; margin-bottom: 24px; }
          .brand-title { font-size: 28px; font-weight: 800; color: #0284c7; margin: 0; }
          .subtitle { font-size: 14px; color: #64748b; margin: 4px 0 0 0; }
          .meta-info { text-align: right; font-size: 12px; color: #64748b; }
          table { width: 100%; border-collapse: collapse; margin-top: 10px; }
          th { background-color: #f1f5f9; color: #334155; text-align: left; padding: 12px 8px; border-bottom: 2px solid #cbd5e1; font-size: 11px; text-transform: uppercase; letter-spacing: 0.5px; }
          td { padding: 12px 8px; border-bottom: 1px solid #e2e8f0; font-size: 13px; line-height: 1.4; vertical-align: top; }
          .badge { display: inline-block; padding: 4px 8px; border-radius: 9999px; font-size: 11px; font-weight: bold; text-transform: uppercase; }
          .pending { background-color: #ffedd5; color: #ea580c; border: 1px solid #fed7aa; }
          .process { background-color: #dbeafe; color: #1d4ed8; border: 1px solid #bfdbfe; }
          .resolved { background-color: #dcfce7; color: #15803d; border: 1px solid #bbf7d0; }
          .footer { margin-top: 50px; text-align: center; color: #94a3b8; font-size: 11px; border-top: 1px solid #e2e8f0; padding-top: 15px; }
          @media print {
            body { padding: 0; }
            .header-container { margin-bottom: 15px; }
          }
        </style>
      </head>
      <body>
        <div class="header-container">
          <div>
            <h1 class="brand-title">UrbiConnect Cantillana</h1>
            <p class="subtitle">Reporte general de incidencias registradas</p>
          </div>
          <div class="meta-info">
            Fecha de impresión: ${DateTime.now().day.toString().padLeft(2, '0')}/${DateTime.now().month.toString().padLeft(2, '0')}/${DateTime.now().year}<br/>
            Total de incidencias exportadas: ${incidents.length}
          </div>
        </div>
        
        <table>
          <thead>
            <tr>
              <th style="width: 10%;">ID</th>
              <th style="width: 35%;">Título / descripción</th>
              <th style="width: 15%;">Categoría</th>
              <th style="width: 12%;">Estado</th>
              <th style="width: 18%;">Dirección</th>
              <th style="width: 10%;">Fecha</th>
            </tr>
          </thead>
          <tbody>
            ${rowsBuffer.toString()}
          </tbody>
        </table>
        
        <div class="footer">
          UrbiConnect Cantillana &copy; ${DateTime.now().year} - Panel de administración y estadísticas
        </div>
        
        <script>
          window.addEventListener('DOMContentLoaded', () => {
            setTimeout(() => {
              window.print();
            }, 600);
          });
        </script>
      </body>
      </html>
    ''';

    final bytes = utf8.encode(htmlContent);
    final blob = html.Blob([bytes], 'text/html;charset=utf-8');
    final url = html.Url.createObjectUrlFromBlob(blob);

    html.AnchorElement(href: url)
      ..target = '_blank'
      ..click();
  }

  static Future<void> exportStatsToPDF({
    required int citizens,
    required int staff,
    required int admins,
    required int pending,
    required int inProcess,
    required int resolved,
    required List<Map<String, dynamic>> categoryStats,
  }) async {
    final StringBuffer categoriesRows = StringBuffer();
    final int totalIncidents = pending + inProcess + resolved;

    for (var cat in categoryStats) {
      final name = cat['name'] ?? 'Categoría general';
      final count = cat['count'] ?? 0;
      final percentage = totalIncidents > 0
          ? (count / totalIncidents * 100).toStringAsFixed(1)
          : '0.0';

      categoriesRows.write('''
        <tr>
          <td><b>${_escapeHtml(name)}</b></td>
          <td style="text-align: right; font-weight: bold; color: #0284c7;">$count</td>
          <td style="text-align: right; color: #64748b;">$percentage%</td>
          <td style="width: 40%; padding-left: 20px;">
            <div style="background-color: #f1f5f9; border-radius: 9999px; width: 100%; height: 8px; overflow: hidden; display: flex;">
              <div style="background-color: #0284c7; width: $percentage%; height: 100%; border-radius: 9999px;"></div>
            </div>
          </td>
        </tr>
      ''');
    }

    final double pendingPercent =
        totalIncidents > 0 ? (pending / totalIncidents * 100) : 0;
    final double processPercent =
        totalIncidents > 0 ? (inProcess / totalIncidents * 100) : 0;
    final double resolvedPercent =
        totalIncidents > 0 ? (resolved / totalIncidents * 100) : 0;

    final String htmlContent = '''
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="utf-8">
        <title>Informe estadístico - UrbiConnect Cantillana</title>
        <style>
          body { font-family: 'Helvetica Neue', Helvetica, Arial, sans-serif; padding: 40px; color: #1e293b; background: white; margin: 0; }
          .header-container { display: flex; align-items: center; justify-content: space-between; border-bottom: 3px solid #0284c7; padding-bottom: 20px; margin-bottom: 30px; }
          .brand-title { font-size: 28px; font-weight: 800; color: #0284c7; margin: 0; }
          .subtitle { font-size: 14px; color: #64748b; margin: 4px 0 0 0; }
          .meta-info { text-align: right; font-size: 12px; color: #64748b; }
          
          .grid { display: flex; gap: 20px; justify-content: space-between; margin-bottom: 30px; }
          .card { flex: 1; background-color: #f8fafc; border: 1px solid #e2e8f0; border-radius: 12px; padding: 20px; text-align: center; }
          .card-value { font-size: 32px; font-weight: 800; color: #0f172a; margin: 5px 0; }
          .card-label { font-size: 12px; font-weight: 700; color: #64748b; text-transform: uppercase; letter-spacing: 0.5px; }
          .card.primary { background-color: #eff6ff; border-color: #bfdbfe; }
          .card.primary .card-value { color: #2563eb; }
          .card.success { background-color: #f0fdf4; border-color: #bbf7d0; }
          .card.success .card-value { color: #16a34a; }
          
          h2 { font-size: 18px; font-weight: 700; color: #0f172a; margin-top: 30px; margin-bottom: 15px; border-bottom: 1px solid #e2e8f0; padding-bottom: 8px; }
          
          .progress-section { margin-bottom: 30px; }
          .progress-bar-container { display: flex; height: 24px; border-radius: 6px; overflow: hidden; background-color: #f1f5f9; margin-top: 10px; border: 1px solid #e2e8f0; }
          .progress-segment { height: 100%; display: flex; align-items: center; justify-content: center; color: white; font-size: 11px; font-weight: bold; }
          .bg-pending { background-color: #f97316; }
          .bg-process { background-color: #3b82f6; }
          .bg-resolved { background-color: #22c55e; }
          
          .legend { display: flex; gap: 20px; justify-content: center; margin-top: 12px; font-size: 13px; }
          .legend-item { display: flex; align-items: center; gap: 6px; }
          .legend-color { width: 12px; height: 12px; border-radius: 4px; }
          
          table { width: 100%; border-collapse: collapse; margin-top: 10px; }
          th { background-color: #f1f5f9; color: #334155; text-align: left; padding: 10px; border-bottom: 2px solid #cbd5e1; font-size: 12px; text-transform: uppercase; letter-spacing: 0.5px; }
          td { padding: 10px; border-bottom: 1px solid #e2e8f0; font-size: 13px; vertical-align: middle; }
          
          .footer { margin-top: 60px; text-align: center; color: #94a3b8; font-size: 11px; border-top: 1px solid #e2e8f0; padding-top: 15px; }
          @media print {
            body { padding: 0; }
            .card { break-inside: avoid; }
            table { break-inside: avoid; }
          }
        </style>
      </head>
      <body>
        <div class="header-container">
          <div>
            <h1 class="brand-title">UrbiConnect Cantillana</h1>
            <p class="subtitle">Informe estadístico de actividad y usuarios</p>
          </div>
          <div class="meta-info">
            Fecha de emisión: ${DateTime.now().day.toString().padLeft(2, '0')}/${DateTime.now().month.toString().padLeft(2, '0')}/${DateTime.now().year}<br/>
            Área: panel de administración
          </div>
        </div>

        <h2>Distribución de usuarios registrados</h2>
        <div class="grid">
          <div class="card primary">
            <div class="card-value">$citizens</div>
            <div class="card-label">Ciudadanos activos</div>
          </div>
          <div class="card">
            <div class="card-value">$staff</div>
            <div class="card-label">Personal de servicio</div>
          </div>
          <div class="card">
            <div class="card-value">$admins</div>
            <div class="card-label">Administradores</div>
          </div>
        </div>

        <h2>Resumen del estado de incidencias</h2>
        <div class="progress-section">
          <div style="display: flex; justify-content: space-between; font-size: 14px; font-weight: bold; margin-bottom: 5px;">
            <span>Total reportado: $totalIncidents incidencias</span>
          </div>
          <div class="progress-bar-container">
            <div class="progress-segment bg-pending" style="width: $pendingPercent%">${pendingPercent > 10 ? '${pendingPercent.toStringAsFixed(1)}%' : ''}</div>
            <div class="progress-segment bg-process" style="width: $processPercent%">${processPercent > 10 ? '${processPercent.toStringAsFixed(1)}%' : ''}</div>
            <div class="progress-segment bg-resolved" style="width: $resolvedPercent%">${resolvedPercent > 10 ? '${resolvedPercent.toStringAsFixed(1)}%' : ''}</div>
          </div>
          <div class="legend">
            <div class="legend-item">
              <div class="legend-color bg-pending"></div>
              <span>Pendiente ($pending)</span>
            </div>
            <div class="legend-item">
              <div class="legend-color bg-process"></div>
              <span>En proceso ($inProcess)</span>
            </div>
            <div class="legend-item">
              <div class="legend-color bg-resolved"></div>
              <span>Resuelta ($resolved)</span>
            </div>
          </div>
        </div>

        <h2>Distribución por categorías de incidencias</h2>
        <table>
          <thead>
            <tr>
              <th style="width: 35%;">Categoría</th>
              <th style="width: 15%; text-align: right;">Cant. de incidencias</th>
              <th style="width: 15%; text-align: right;">Proporción</th>
              <th style="width: 35%; padding-left: 20px;">Impacto visual</th>
            </tr>
          </thead>
          <tbody>
            ${categoriesRows.toString()}
          </tbody>
        </table>

        <div class="footer">
          UrbiConnect Cantillana &copy; ${DateTime.now().year} - Sistema de gestión de incidencias ciudadanas
        </div>

        <script>
          window.addEventListener('DOMContentLoaded', () => {
            setTimeout(() => {
              window.print();
            }, 600);
          });
        </script>
      </body>
      </html>
    ''';

    final bytes = utf8.encode(htmlContent);
    final blob = html.Blob([bytes], 'text/html;charset=utf-8');
    final url = html.Url.createObjectUrlFromBlob(blob);

    html.AnchorElement(href: url)
      ..target = '_blank'
      ..click();
  }

  static String _escapeCsvValue(String value) {
    if (value.contains(';') || value.contains('\n') || value.contains('"')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  static String _translateStatus(String status) {
    switch (status.toLowerCase()) {
      case 'pendiente':
        return 'Pendiente';
      case 'en proceso':
        return 'En proceso';
      case 'resuelta':
        return 'Resuelta';
      default:
        return status;
    }
  }

  static String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }
}
