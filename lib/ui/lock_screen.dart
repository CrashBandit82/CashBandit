import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_lock.dart';
import 'theme.dart';

/// Shows the lock screen above the whole app while [lock] is locked; the app
/// below keeps its state but is not painted.
class LockGate extends StatelessWidget {
  const LockGate({super.key, required this.lock, required this.child});
  final AppLock lock;
  final Widget child;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: lock,
        builder: (context, _) => Stack(
          children: [
            Offstage(offstage: lock.locked, child: TickerMode(enabled: !lock.locked, child: child)),
            if (lock.locked) LockScreen(lock: lock),
          ],
        ),
      );
}

class LockScreen extends StatefulWidget {
  const LockScreen({super.key, required this.lock});
  final AppLock lock;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  String _pin = '';
  String? _error;
  bool _checking = false;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    if (widget.lock.biometricsEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.lock.unlockWithBiometrics());
    }
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.lock.blockedFor > Duration.zero) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _digit(String d) async {
    if (_checking || _pin.length >= 6 || widget.lock.blockedFor > Duration.zero) return;
    setState(() {
      _pin += d;
      _error = null;
    });
  }

  void _backspace() {
    if (_pin.isEmpty || _checking) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _submit() async {
    if (_pin.length < 4 || _checking) return;
    setState(() => _checking = true);
    final ok = await widget.lock.unlockWithPin(_pin);
    if (!mounted) return;
    if (!ok) {
      await HapticFeedback.heavyImpact();
      setState(() {
        _pin = '';
        _error = 'Falsche PIN';
      });
    }
    setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    final blocked = widget.lock.blockedFor;
    final text = Theme.of(context).textTheme;
    return Material(
      child: Container(
        decoration: const BoxDecoration(gradient: Brand.headerGradient),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: Image.asset('assets/branding/mascot.png', width: 112, height: 112),
                  ),
                  const SizedBox(height: 16),
                  Text('CashBandit ist gesperrt', style: text.titleLarge?.copyWith(color: Colors.white)),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < 6; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          margin: const EdgeInsets.symmetric(horizontal: 6),
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i < _pin.length ? Colors.white : Colors.white.withValues(alpha: 0.25),
                          ),
                        ),
                    ],
                  ),
                  SizedBox(
                    height: 32,
                    child: Center(
                      child: Text(
                        blocked > Duration.zero
                            ? 'Zu viele Versuche – bitte ${blocked.inSeconds + 1} s warten'
                            : (_error ?? ''),
                        style: text.bodyMedium?.copyWith(color: const Color(0xFFFFD8D2), fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  _PinPad(
                    onDigit: _digit,
                    onBackspace: _backspace,
                    onSubmit: _submit,
                    canSubmit: _pin.length >= 4,
                    onBiometric: widget.lock.biometricsEnabled ? widget.lock.unlockWithBiometrics : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PinPad extends StatelessWidget {
  const _PinPad({
    required this.onDigit,
    required this.onBackspace,
    required this.onSubmit,
    required this.canSubmit,
    this.onBiometric,
  });

  final void Function(String) onDigit;
  final VoidCallback onBackspace;
  final VoidCallback onSubmit;
  final bool canSubmit;
  final VoidCallback? onBiometric;

  Widget _key(Widget child, VoidCallback? onTap, {String? label}) => Padding(
        padding: const EdgeInsets.all(8),
        child: Semantics(
          button: true,
          label: label,
          child: InkResponse(
            onTap: onTap,
            radius: 40,
            child: Container(
              width: 72,
              height: 72,
              alignment: Alignment.center,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.12)),
              child: child,
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontSize: 28, color: Colors.white, fontWeight: FontWeight.w500);
    Widget digit(String d) => _key(Text(d, style: style), () => onDigit(d));
    return Column(
      children: [
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(mainAxisSize: MainAxisSize.min, children: [for (final d in row) digit(d)]),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            onBiometric != null
                ? _key(const Icon(Icons.fingerprint, color: Colors.white, size: 32), onBiometric, label: 'Fingerabdruck')
                : _key(const Icon(Icons.backspace_outlined, color: Colors.white), onBackspace, label: 'Löschen'),
            digit('0'),
            _key(
              Icon(Icons.check, color: canSubmit ? Colors.white : Colors.white38, size: 32),
              canSubmit ? onSubmit : null,
              label: 'Entsperren',
            ),
          ],
        ),
        if (onBiometric != null)
          TextButton.icon(
            onPressed: onBackspace,
            icon: const Icon(Icons.backspace_outlined, color: Colors.white),
            label: const Text('Löschen', style: TextStyle(color: Colors.white)),
          ),
      ],
    );
  }
}
