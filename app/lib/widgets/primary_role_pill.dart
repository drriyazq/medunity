import 'package:flutter/material.dart';

/// Compact coloured pill that surfaces the doctor's `primary_role` on a card.
///
/// Drops in next to the doctor's name on Find Associates / Find Consultants /
/// Home preview cards so a viewer can instantly see what role the other
/// person primarily plays even when they have multiple roles configured.
///
/// Renders nothing when `role` is empty.
class PrimaryRolePill extends StatelessWidget {
  final String role;
  final String label;
  final double fontSize;

  const PrimaryRolePill({
    super.key,
    required this.role,
    this.label = '',
    this.fontSize = 10,
  });

  static const _color = {
    'clinic_owner': Color(0xFF1E88E5),
    'hospital_owner': Color(0xFF6D4C41),
    'visiting_consultant': Color(0xFF00897B),
    'associate_doctor': Color(0xFF8E24AA),
    'academic_teaching': Color(0xFFEF6C00),
  };
  static const _short = {
    'clinic_owner': 'Clinic',
    'hospital_owner': 'Hospital',
    'visiting_consultant': 'Consultant',
    'associate_doctor': 'Associate',
    'academic_teaching': 'Faculty',
  };

  @override
  Widget build(BuildContext context) {
    if (role.isEmpty) return const SizedBox.shrink();
    final c = _color[role] ?? Colors.grey;
    final text = _short[role] ?? (label.isNotEmpty ? label : role);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: c.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.withOpacity(0.3)),
      ),
      child: Text(text,
          style: TextStyle(
            color: c,
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
          )),
    );
  }
}
