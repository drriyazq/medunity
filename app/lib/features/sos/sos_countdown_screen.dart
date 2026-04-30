import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../theme.dart';
import 'sos_provider.dart';

class SosCountdownScreen extends ConsumerStatefulWidget {
  final String category;
  final String categoryDisplay;
  final Position position;
  final List<int>? recipientIds;

  const SosCountdownScreen({
    super.key,
    required this.category,
    required this.categoryDisplay,
    required this.position,
    this.recipientIds,
  });

  @override
  ConsumerState<SosCountdownScreen> createState() => _SosCountdownScreenState();
}

class _SosCountdownScreenState extends ConsumerState<SosCountdownScreen>
    with SingleTickerProviderStateMixin {
  static const _totalSeconds = 3;
  int _remaining = _totalSeconds;
  Timer? _timer;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);

    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _remaining--);
      if (_remaining <= 0) {
        t.cancel();
        _dispatchSos();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  void _cancel() {
    _timer?.cancel();
    ref.read(sosSendProvider.notifier).reset();
    if (mounted) context.pop();
  }

  Future<void> _dispatchSos() async {
    await ref.read(sosSendProvider.notifier).sendSos(
          category: widget.category,
          lat: widget.position.latitude,
          lng: widget.position.longitude,
          recipientIds: widget.recipientIds,
        );
    if (!mounted) return;
    final state = ref.read(sosSendProvider);
    if (state.status == SosSendStatus.success) {
      context.pushReplacement(
        '/sos/status/${state.alertId}',
        extra: {
          'recipientCount': state.recipientCount,
          'radiusKm': state.radiusKm,
          'category': widget.category,
          'categoryDisplay': widget.categoryDisplay,
        },
      );
    } else if (state.status == SosSendStatus.throttled) {
      _showError(state.errorMessage ?? 'SOS limit reached.');
    } else {
      _showError(state.errorMessage ?? 'Could not send SOS.');
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final sendState = ref.watch(sosSendProvider);
    final isSending = sendState.status == SosSendStatus.sending;

    return Scaffold(
      backgroundColor: const Color(0xFF1A0000),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const Spacer(flex: 2),
              AnimatedBuilder(
                animation: _pulseController,
                builder: (_, child) => Transform.scale(
                  scale: 1.0 + _pulseController.value * 0.08,
                  child: child,
                ),
                child: Container(
                  width: 160,
                  height: 160,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: MedUnityColors.sos.withOpacity(0.15),
                    border: Border.all(color: MedUnityColors.sos, width: 3),
                  ),
                  child: isSending
                      ? const CircularProgressIndicator(
                          color: MedUnityColors.sos, strokeWidth: 3)
                      : Center(
                          child: Text(
                            '$_remaining',
                            style: const TextStyle(
                              fontSize: 72,
                              fontWeight: FontWeight.bold,
                              color: MedUnityColors.sos,
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                'Sending SOS Alert',
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white),
              ),
              const SizedBox(height: 8),
              Text(
                widget.categoryDisplay,
                style: TextStyle(fontSize: 16, color: Colors.red[200]),
              ),
              const SizedBox(height: 8),
              Text(
                widget.recipientIds == null
                    ? 'Nearby doctors will be alerted immediately.'
                    : '${widget.recipientIds!.length} selected doctor${widget.recipientIds!.length == 1 ? '' : 's'} will be alerted immediately.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey[400]),
              ),
              const Spacer(flex: 3),
              if (!isSending)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _cancel,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white54),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Cancel', style: TextStyle(fontSize: 16)),
                  ),
                ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
