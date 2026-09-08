import 'dart:async';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../protocol/fountain_coder.dart';
import '../theme/payflex_tokens.dart';
import 'pf_mark.dart';

/// Continuously animated optical QR code streaming loss-tolerant fountain packets.
///
/// Converts arbitrary payment payloads into an ongoing series of QR frames
/// regenerated every 150–220ms, allowing offline camera scanners to assemble
/// the payload even if frames are dropped or received out of sequence.
class AnimatedOpticalQr extends StatefulWidget {
  final FountainEncoder encoder;
  final double size;
  final Duration frameInterval;
  final bool showProgressInfo;

  const AnimatedOpticalQr({
    super.key,
    required this.encoder,
    this.size = 220,
    this.frameInterval = const Duration(milliseconds: 180),
    this.showProgressInfo = true,
  });

  @override
  State<AnimatedOpticalQr> createState() => _AnimatedOpticalQrState();
}

class _AnimatedOpticalQrState extends State<AnimatedOpticalQr>
    with SingleTickerProviderStateMixin {
  Timer? _timer;
  late String _currentFrame;
  int _frameIndex = 0;
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _currentFrame = widget.encoder.nextFrame();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);

    _startStreaming();
  }

  void _startStreaming() {
    _timer?.cancel();
    _timer = Timer.periodic(widget.frameInterval, (_) {
      if (!mounted) return;
      setState(() {
        _currentFrame = widget.encoder.nextFrame();
        _frameIndex++;
      });
    });
  }

  @override
  void didUpdateWidget(covariant AnimatedOpticalQr oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.encoder != widget.encoder ||
        oldWidget.frameInterval != widget.frameInterval) {
      _currentFrame = widget.encoder.nextFrame();
      _frameIndex = 0;
      _startStreaming();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final k = widget.encoder.k;
    final sid = widget.encoder.sessionId;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            // Outer subtle glow pulse on dark backgrounds
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, _) => Container(
                width: widget.size + 44,
                height: widget.size + 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(PfRadius.lg + 4),
                  boxShadow: [
                    BoxShadow(
                      color: PfColors.emerald.withValues(
                        alpha: 0.08 + 0.06 * _pulseController.value,
                      ),
                      blurRadius: 18,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
            ),

            // White QR container
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(PfRadius.md),
                boxShadow: PfShadow.onDark,
              ),
              child: QrImageView(
                data: _currentFrame,
                size: widget.size,
                backgroundColor: Colors.white,
                version: QrVersions.auto,
                errorCorrectionLevel: QrErrorCorrectLevel.M,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: Color(0xFF0A1330),
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: Color(0xFF0A1330),
                ),
              ),
            ),

            // Flat PayFlex QR corners signature frame
            IgnorePointer(
              child: SizedBox(
                width: widget.size + 36,
                height: widget.size + 36,
                child: const PfQrCorners(
                  color: Colors.white,
                  thickness: 3.5,
                  length: 0.14,
                ),
              ),
            ),
          ],
        ),

        if (widget.showProgressInfo) ...[
          const SizedBox(height: 14),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: PfColors.emerald,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'Fountain Stream · $k blocks · Frame #$_frameIndex',
                style: const TextStyle(
                  color: PfColors.onNavyMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: PfColors.navyRaised2,
                  borderRadius: BorderRadius.circular(PfRadius.xs),
                ),
                child: Text(
                  'SID $sid',
                  style: const TextStyle(
                    color: PfColors.onNavyFaint,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
