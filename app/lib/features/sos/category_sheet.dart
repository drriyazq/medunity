import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../theme.dart';

const _categories = [
  (
    id: 'medical_emergency',
    label: 'Medical Emergency',
    icon: Icons.local_hospital,
    color: Color(0xFFD32F2F),
  ),
  (
    id: 'legal_issue',
    label: 'Legal Issue',
    icon: Icons.gavel,
    color: Color(0xFF7B1FA2),
  ),
  (
    id: 'clinic_threat',
    label: 'Clinic Under Threat',
    icon: Icons.warning_amber_rounded,
    color: Color(0xFFE65100),
  ),
  (
    id: 'urgent_clinical',
    label: 'Urgent Clinical Assistance',
    icon: Icons.medical_services,
    color: Color(0xFF1565C0),
  ),
];

/// Shows SOS category bottom sheet. Resolves with (category, position) or null if cancelled.
Future<({String category, Position position})?> showSosCategorySheet(
    BuildContext context) async {
  return showModalBottomSheet<({String category, Position position})>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _CategorySheet(),
  );
}

class _CategorySheet extends StatefulWidget {
  const _CategorySheet();

  @override
  State<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends State<_CategorySheet> {
  bool _locating = false;
  String? _error;

  Future<void> _onCategoryTap(String categoryId) async {
    setState(() {
      _locating = true;
      _error = null;
    });
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever ||
          perm == LocationPermission.denied) {
        setState(() {
          _locating = false;
          _error = 'Location permission required for SOS.';
        });
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      if (mounted) Navigator.of(context).pop((category: categoryId, position: pos));
    } catch (_) {
      setState(() {
        _locating = false;
        _error = 'Could not get location. Enable GPS and retry.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: MedUnityColors.sos.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.sos, color: MedUnityColors.sos, size: 22),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Send SOS Alert',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Text('Select the type of help needed',
                      style: TextStyle(fontSize: 13, color: MedUnityColors.textSecondary)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (_error != null)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(_error!,
                          style: const TextStyle(color: Colors.red, fontSize: 13))),
                ],
              ),
            ),
          if (_locating)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Column(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('Getting your location…',
                      style: TextStyle(color: MedUnityColors.textSecondary)),
                ],
              ),
            )
          else
            ...List.generate(_categories.length, (i) {
              final cat = _categories[i];
              return _CategoryTile(
                icon: cat.icon,
                label: cat.label,
                color: cat.color,
                onTap: () => _onCategoryTap(cat.id),
              );
            }),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel', style: TextStyle(color: MedUnityColors.textSecondary)),
          ),
        ],
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _CategoryTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            border: Border.all(color: color.withOpacity(0.3)),
            borderRadius: BorderRadius.circular(14),
            color: color.withOpacity(0.04),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(label,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
              ),
              Icon(Icons.chevron_right, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }
}
