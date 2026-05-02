import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/api/client.dart';
import '../../state/auth_provider.dart';
import '../../theme.dart';
import 'set_clinic_location.dart';

final _profileDataProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final dio = ref.read(dioProvider);
  final resp = await dio.get('/auth/me/');
  return Map<String, dynamic>.from(resp.data as Map);
});

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(_profileDataProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _confirmLogout(context, ref),
          ),
        ],
      ),
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('Could not load profile.')),
        data: (data) => _ProfileBody(data: data, ref: ref),
      ),
    );
  }

  void _confirmLogout(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You will need to verify your phone again to sign back in.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () {
                Navigator.pop(context);
                ref.read(authProvider.notifier).logout();
              },
              child: const Text('Log out', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
  }
}

class _ProfileBody extends StatelessWidget {
  final Map<String, dynamic> data;
  final WidgetRef ref;
  const _ProfileBody({required this.data, required this.ref});

  @override
  Widget build(BuildContext context) {
    final clinic = data['clinic'] as Map<String, dynamic>?;
    final isVerified = data['is_admin_verified'] as bool? ?? false;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar + name card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 36,
                  backgroundImage: (data['profile_photo'] as String?) != null
                      ? NetworkImage(data['profile_photo'] as String)
                      : null,
                  child: data['profile_photo'] == null
                      ? const Icon(Icons.person, size: 36)
                      : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(data['full_name'] as String? ?? '',
                                style: const TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.bold)),
                          ),
                          if (isVerified)
                            const Icon(Icons.verified, color: Colors.blue, size: 18),
                        ],
                      ),
                      Text(data['specialization_display'] as String? ?? '',
                          style: const TextStyle(
                              color: MedUnityColors.primary, fontSize: 14)),
                      if (clinic != null)
                        Text(
                          '${clinic['name']}, ${clinic['city']}',
                          style: const TextStyle(
                              fontSize: 12, color: MedUnityColors.textSecondary),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Clinic location tile
          _ClinicLocationTile(clinic: clinic, ref: ref),
          const SizedBox(height: 16),

          // Roles editor
          _RolesTile(data: data, ref: ref),
          const SizedBox(height: 20),

          // Quick links
          const Text('Activity',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 10),
          _QuickLink(
            icon: Icons.sos_outlined,
            label: 'My SOS Alerts',
            onTap: () => context.push('/sos/dashboard'),
          ),
          _QuickLink(
            icon: Icons.medical_services_outlined,
            label: 'Associate Doctors (Find / Bookings / Be one)',
            onTap: () => context.push('/associates'),
          ),
          _QuickLink(
            icon: Icons.handshake_outlined,
            label: 'My Coverage Requests',
            onTap: () => context.push('/support'),
          ),
          _QuickLink(
            icon: Icons.calendar_month_outlined,
            label: 'My Consultation Bookings',
            onTap: () => context.push('/consultants'),
          ),
          _QuickLink(
            icon: Icons.storefront_outlined,
            label: 'My Equipment Listings',
            onTap: () => context.push('/equipment/listings/mine'),
          ),
          _QuickLink(
            icon: Icons.group_work_outlined,
            label: 'My Co-Purchase Pools',
            onTap: () => context.push('/marketplace'),
          ),
          _QuickLink(
            icon: Icons.leaderboard,
            label: 'Leaderboard & Brownie Points',
            onTap: () => context.push('/support/leaderboard'),
          ),

          // Details
          const SizedBox(height: 20),
          const Text('Details',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 10),
          _DetailRow('Role', data['role_display'] as String? ?? ''),
          _DetailRow('Council', data['council_display'] as String? ?? ''),
          _DetailRow('License No.', data['license_number'] as String? ?? ''),
          if ((data['qualification'] as String? ?? '').isNotEmpty)
            _DetailRow('Qualification', data['qualification'] as String),
          if ((data['years_experience'] as int?) != null)
            _DetailRow('Experience', '${data['years_experience']} years'),
          if (clinic != null) ...[
            const SizedBox(height: 8),
            _DetailRow('Clinic', clinic['name'] as String? ?? ''),
            _DetailRow('Address',
                '${clinic['address']}, ${clinic['city']}, ${clinic['state']} ${clinic['pincode']}'),
            _DetailRow('Clinic Phone', clinic['phone'] as String? ?? ''),
          ],

          if ((data['about'] as String? ?? '').isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('About', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(data['about'] as String),
          ],
        ],
      ),
    );
  }
}

class _QuickLink extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _QuickLink({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: MedUnityColors.primary.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: MedUnityColors.primary, size: 20),
      ),
      title: Text(label),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: onTap,
    );
  }
}

class _ClinicLocationTile extends StatefulWidget {
  final Map<String, dynamic>? clinic;
  final WidgetRef ref;
  const _ClinicLocationTile({required this.clinic, required this.ref});

  @override
  State<_ClinicLocationTile> createState() => _ClinicLocationTileState();
}

class _ClinicLocationTileState extends State<_ClinicLocationTile> {
  bool _busy = false;

  Future<void> _onTap() async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await setClinicLocationFromGps(context, widget.ref);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      // Refresh profile data so the tile reflects new lat/lng
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      widget.ref.invalidate(_profileDataProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasLocation = widget.clinic != null && widget.clinic!['lat'] != null;
    final isLocked = (widget.clinic?['location_locked'] as bool?) ?? false;
    final lat = widget.clinic?['lat']?.toString();
    final lng = widget.clinic?['lng']?.toString();
    final subtitle = isLocked
        ? 'Pinned by admin: ${lat?.substring(0, lat.length.clamp(0, 8))}, ${lng?.substring(0, lng.length.clamp(0, 8))}'
        : hasLocation
            ? 'GPS set: ${lat?.substring(0, lat.length.clamp(0, 8))}, ${lng?.substring(0, lng.length.clamp(0, 8))}'
            : 'Required for SOS targeting and finding nearby consultants.';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: hasLocation ? Colors.white : MedUnityColors.primary.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasLocation ? Colors.grey[200]! : MedUnityColors.primary.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isLocked
                ? Icons.lock_outline
                : (hasLocation ? Icons.location_on : Icons.location_off),
            color: isLocked
                ? Colors.grey[600]
                : (hasLocation ? MedUnityColors.success : MedUnityColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isLocked
                      ? 'Clinic Location (Locked)'
                      : (hasLocation ? 'Clinic Location' : 'Set Clinic Location'),
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: const TextStyle(
                        fontSize: 12, color: MedUnityColors.textSecondary)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (!isLocked)
            ElevatedButton(
              onPressed: _busy ? null : _onTap,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
              child: _busy
                  ? const SizedBox(
                      height: 16, width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(hasLocation ? 'Update' : 'Use GPS'),
            ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: const TextStyle(
                    color: MedUnityColors.textSecondary, fontSize: 13)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

const List<Map<String, String>> _allRoles = [
  {'key': 'clinic_owner', 'label': 'Clinic Owner / Primary Physician'},
  {'key': 'hospital_owner', 'label': 'Hospital Owner / Director'},
  {'key': 'visiting_consultant', 'label': 'Visiting Consultant / Specialist'},
  {'key': 'associate_doctor', 'label': 'Associate Doctor (Short-term Coverage)'},
  {'key': 'academic_teaching', 'label': 'Academic / Teaching (Dental College Faculty)'},
];

/// Compact labels for the role pills on the profile body. Long descriptive
/// labels (in `_allRoles`) overflow the pill on small screens — use these
/// for chip-style display only. The editor checkbox still shows the full
/// label so users see the role description when picking.
const _rolePillLabels = {
  'clinic_owner': 'Clinic Owner',
  'hospital_owner': 'Hospital Owner',
  'visiting_consultant': 'Visiting Consultant',
  'associate_doctor': 'Associate Doctor',
  'academic_teaching': 'Academic / Teaching',
};

class _RolesTile extends StatefulWidget {
  final Map<String, dynamic> data;
  final WidgetRef ref;
  const _RolesTile({required this.data, required this.ref});

  @override
  State<_RolesTile> createState() => _RolesTileState();
}

class _RolesTileState extends State<_RolesTile> {
  bool _saving = false;

  List<String> _currentRoles() {
    final raw = widget.data['roles'];
    if (raw is List) return raw.map((e) => e.toString()).toList();
    final fallback = widget.data['role'] as String?;
    return fallback == null ? [] : [fallback];
  }

  Future<void> _edit() async {
    final selected = Set<String>.from(_currentRoles());
    final initialPrimary =
        widget.data['primary_role'] as String? ?? selected.firstOrNull ?? '';
    final result = await showModalBottomSheet<_RolesEditorResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RolesEditorSheet(
        initialSelection: selected,
        initialPrimary: initialPrimary,
      ),
    );
    if (result == null || result.roles.isEmpty) return;
    setState(() => _saving = true);
    try {
      final dio = widget.ref.read(dioProvider);
      await dio.patch('/auth/me/', data: {
        'roles': result.roles.toList(),
        'primary_role': result.primary,
      });
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      widget.ref.invalidate(_profileDataProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Roles updated.'), backgroundColor: Colors.green),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Could not save roles.'),
            backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final roles = _currentRoles();
    final labels = {for (final r in _allRoles) r['key']!: r['label']!};
    final primary = widget.data['primary_role'] as String? ?? '';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.badge_outlined,
                  color: MedUnityColors.primary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('My Roles',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
              TextButton(
                onPressed: _saving ? null : _edit,
                child: const Text('Edit'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (roles.isEmpty)
            const Text('No roles set yet.',
                style: TextStyle(
                    color: MedUnityColors.textSecondary, fontSize: 12))
          else
            // LayoutBuilder so each pill can be capped at the available card
            // width — long role labels were overflowing the right edge by
            // ~44 px on a 360 px screen.
            LayoutBuilder(
              builder: (ctx, c) => Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final r in roles)
                    ConstrainedBox(
                      constraints:
                          BoxConstraints(maxWidth: c.maxWidth),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: r == primary
                              ? MedUnityColors.primary
                              : MedUnityColors.primary.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (r == primary) ...[
                              const Icon(Icons.star,
                                  size: 12, color: Colors.white),
                              const SizedBox(width: 4),
                            ],
                            Flexible(
                              child: Text(
                                _rolePillLabels[r] ?? labels[r] ?? r,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: r == primary
                                        ? Colors.white
                                        : MedUnityColors.primary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          if (roles.isNotEmpty && primary.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Primary role drives your Home page sections.',
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
          ],
        ],
      ),
    );
  }
}

/// Result returned by the editor sheet — both the selected roles and the
/// chosen primary (always one of the selected roles, validated client-side).
class _RolesEditorResult {
  final Set<String> roles;
  final String primary;
  const _RolesEditorResult(this.roles, this.primary);
}

class _RolesEditorSheet extends StatefulWidget {
  final Set<String> initialSelection;
  final String initialPrimary;
  const _RolesEditorSheet({
    required this.initialSelection,
    required this.initialPrimary,
  });

  @override
  State<_RolesEditorSheet> createState() => _RolesEditorSheetState();
}

class _RolesEditorSheetState extends State<_RolesEditorSheet> {
  late Set<String> _sel = Set.from(widget.initialSelection);
  late String _primary = widget.initialPrimary.isNotEmpty &&
          widget.initialSelection.contains(widget.initialPrimary)
      ? widget.initialPrimary
      : (widget.initialSelection.isNotEmpty
          ? widget.initialSelection.first
          : '');

  void _toggle(String key, bool? on) {
    setState(() {
      if (on == true) {
        _sel.add(key);
        // First role auto-becomes primary.
        if (_primary.isEmpty) _primary = key;
      } else {
        _sel.remove(key);
        // If we just unchecked the primary, promote the next selected role.
        if (_primary == key) {
          _primary = _sel.isNotEmpty ? _sel.first : '';
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text('Select all that apply',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            'Tap the star to mark one role as your Primary — this drives your Home page sections.',
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
          const SizedBox(height: 12),
          for (final r in _allRoles)
            _RoleRow(
              roleKey: r['key']!,
              label: r['label']!,
              checked: _sel.contains(r['key']),
              isPrimary: _primary == r['key'],
              canBePrimary: _sel.contains(r['key']),
              onToggle: (v) => _toggle(r['key']!, v),
              onSetPrimary: () => setState(() {
                if (_sel.contains(r['key'])) _primary = r['key']!;
              }),
            ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: _sel.isEmpty
                ? null
                : () => Navigator.pop<_RolesEditorResult>(
                      context, _RolesEditorResult(_sel, _primary)),
            style: ElevatedButton.styleFrom(
              backgroundColor: MedUnityColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

class _RoleRow extends StatelessWidget {
  final String roleKey;
  final String label;
  final bool checked;
  final bool isPrimary;
  final bool canBePrimary;
  final ValueChanged<bool?> onToggle;
  final VoidCallback onSetPrimary;

  const _RoleRow({
    required this.roleKey,
    required this.label,
    required this.checked,
    required this.isPrimary,
    required this.canBePrimary,
    required this.onToggle,
    required this.onSetPrimary,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Checkbox(
            value: checked,
            onChanged: onToggle,
            activeColor: MedUnityColors.primary,
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => onToggle(!checked),
              child: Text(label, style: const TextStyle(fontSize: 14)),
            ),
          ),
          IconButton(
            onPressed: canBePrimary ? onSetPrimary : null,
            icon: Icon(
              isPrimary ? Icons.star : Icons.star_border,
              color: isPrimary
                  ? Colors.amber[700]
                  : (canBePrimary ? Colors.grey[500] : Colors.grey[300]),
              size: 22,
            ),
            tooltip: isPrimary
                ? 'Primary role'
                : (canBePrimary
                    ? 'Set as primary'
                    : 'Tick this role first'),
          ),
        ],
      ),
    );
  }
}
