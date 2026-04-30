import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/client.dart';
import '../../theme.dart';

Future<bool?> showCreateCircleSheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _CreateCircleSheet(),
  );
}

class _CreateCircleSheet extends StatefulWidget {
  const _CreateCircleSheet();

  @override
  State<_CreateCircleSheet> createState() => _CreateCircleSheetState();
}

class _CreateCircleSheetState extends State<_CreateCircleSheet> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  double _radiusKm = 2.0;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Circle name is required.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });

    // Access Dio via context — caller already has WidgetRef, but this sheet
    // avoids bringing in Riverpod by using a simple callback pattern.
    // Instead we pass the Dio instance up via a ProviderScope look-up at
    // the root level. Since this sheet is inside ProviderScope via the app,
    // we can use ProviderScope.containerOf.
    try {
      // ignore: use_build_context_synchronously
      final container = ProviderScope.containerOf(context, listen: false);
      final dio = container.read(dioProvider);
      await dio.post('/circles/', data: {
        'name': name,
        'description': _descCtrl.text.trim(),
        'radius_km': _radiusKm,
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      setState(() {
        _loading = false;
        _error = 'Could not create circle. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 20),
            const Text('Create a Circle',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Circle name *',
                border: OutlineInputBorder(),
                hintText: 'e.g. Andheri Dentists, Bandra General MDs',
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _descCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            Text('Radius: ${_radiusKm.toStringAsFixed(1)} km',
                style: const TextStyle(fontWeight: FontWeight.w500)),
            Slider(
              value: _radiusKm,
              min: 0.5,
              max: 10.0,
              divisions: 19,
              label: '${_radiusKm.toStringAsFixed(1)} km',
              activeColor: MedUnityColors.primary,
              onChanged: (v) => setState(() => _radiusKm = v),
            ),
            const Text('Members within this radius will be suggested to join.',
                style: TextStyle(fontSize: 12, color: MedUnityColors.textSecondary)),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: MedUnityColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Text('Create Circle',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
