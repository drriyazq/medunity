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
          const SizedBox(height: 20),

          // Quick links
          const Text('Activity',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 10),
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
    final lat = widget.clinic?['lat']?.toString();
    final lng = widget.clinic?['lng']?.toString();
    final subtitle = hasLocation
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
            hasLocation ? Icons.location_on : Icons.location_off,
            color: hasLocation ? MedUnityColors.success : MedUnityColors.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasLocation ? 'Clinic Location' : 'Set Clinic Location',
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
