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
///
/// Presentation rules (design brief): the frame must read as ALIVE — the
/// data genuinely re-streams every tick and a flat scan-line sweeps the
/// code — but it never glows. Every caption is honest in both directions:
/// the stream is really happening, and it is NOT settled until redemption.
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
  late final AnimationController _sweepController;

  @override
  void initState() {
    super.initState();
    _currentFrame = widget.encoder.nextFrame();
    // The scan-line sweep: one flat band travelling down the code, ~1.6s
    // per pass. Cheap (a single gradient translation) and synced to the
    // vsync so it never fights the QR repaints.
    _sweepController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();

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
    _sweepController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final k = widget.encoder.k;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            // White QR container (flat shadow only — no coloured glow).
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

            // The stream, made visible: a flat emerald-tinted band sweeps
            // down the code once per cycle. Low opacity, hard edges — a
            // scanner read-out, not a glow.
            if (widget.size >= 120)
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(PfRadius.md),
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _sweepController,
                      builder: (context, _) => Align(
                        alignment: Alignment(0, _sweepController.value * 2 - 1),
                        child: Container(
                          width: double.infinity,
                          height: widget.size * 0.16,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              stops: const [0, 0.5, 1],
                              colors: [
                                PfColors.emerald.withValues(alpha: 0.0),
                                PfColors.emerald.withValues(alpha: 0.14),
                                PfColors.emerald.withValues(alpha: 0.0),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
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
              const _LiveDotStatefulWidget(),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  'Streaming live · frame #$_frameIndex',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: PfColors.onNavyMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: PfColors.navyRaised2,
                  borderRadius: BorderRadius.circular(PfRadius.xs),
                ),
                child: Text(
                  '$k-part code',
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

/// The "this is really streaming" pulse: a flat emerald dot that breathes
/// between two solid states. No glow — just a dot fading.
class _LiveDotStatefulWidget extends StatefulWidget {
  const _LiveDotStatefulWidget();

  @override
  State<_LiveDotStatefulWidget> createState() => _LiveDotStatefulWidgetState();
}

class _LiveDotStatefulWidgetState extends State<_LiveDotStatefulWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          color: PfColors.emerald
              .withValues(alpha: 0.55 + 0.45 * _controller.value),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
