import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../theme.dart';

class LiveConsentScreen extends StatelessWidget {
  const LiveConsentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Before going live')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Column(
                  children: const [
                    Icon(Icons.gps_fixed,
                        color: MedUnityColors.primary, size: 44),
                    SizedBox(height: 8),
                    Text(
                      'How Go Live works',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 12),
                    _Bullet(
                      icon: Icons.location_on_outlined,
                      text:
                          'MedUnity reads your phone\'s GPS every 10 minutes (or 30 if Stationary mode is on) while Go Live is ON.',
                    ),
                    _Bullet(
                      icon: Icons.shield_outlined,
                      text:
                          'Your exact coordinates are stored on our server only. Other doctors never see them.',
                    ),
                    _Bullet(
                      icon: Icons.search_off,
                      text:
                          'Doctors searching for a consultant just see "Available now" and a distance bucket like "Within 2 km" — never your address or pin.',
                    ),
                    _Bullet(
                      icon: Icons.notifications_active_outlined,
                      text:
                          'Android shows a permanent notification while Go Live is on — you can stop sharing in one tap from there.',
                    ),
                    _Bullet(
                      icon: Icons.battery_alert_outlined,
                      text:
                          'Continuous location sharing uses extra battery. Switch off when you are off duty.',
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => context.pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: MedUnityColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text('I AGREE — CONTINUE',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () => context.pop(false),
                      child: const Text('Cancel'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Bullet({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: MedUnityColors.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 13, height: 1.35)),
          ),
        ],
      ),
    );
  }
}
