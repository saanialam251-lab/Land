import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/app_prefs.dart';
import '../../data/auth_service.dart';
import '../theme.dart';
import 'pop.dart';
import 'pressable.dart';

/// Round account button (person icon, or the user's initials once logged in).
class AccountIconButton extends StatelessWidget {
  const AccountIconButton({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AuthService.I,
      builder: (context, _) {
        final u = AuthService.I.user;
        return Pressable(
          radius: 24,
          glow: u == null ? AppColors.accentCyan : AppColors.successGreen,
          onTap: () => showAccountDialog(context),
          child: Tooltip(
            message: u == null ? 'Login / Sign up' : 'My account',
            child: Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: u == null
                      ? const [Color(0x333DD6F5), Color(0x1A3DD6F5)]
                      : const [AppColors.successGreen, AppColors.accentCyan],
                ),
                border: Border.all(color: u == null ? AppColors.accentCyan : Colors.white, width: 1.6),
              ),
              child: u == null
                  ? const Icon(Icons.person_outline_rounded, color: AppColors.accentCyan, size: 26)
                  : Text(u.initials,
                      style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 16)),
            ),
          ),
        );
      },
    );
  }
}

/// Opens the account box: login / sign up when logged out, profile + logout when logged in.
Future<void> showAccountDialog(BuildContext context) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'close',
    barrierColor: Colors.black54,
    transitionDuration: AppPrefs.I.animations ? const Duration(milliseconds: 420) : Duration.zero,
    pageBuilder: (ctx, a, b) => const SizedBox.shrink(),
    transitionBuilder: (ctx, anim, sec, _) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutBack, reverseCurve: Curves.easeIn);
      return FadeTransition(
        opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.25), end: Offset.zero).animate(curved),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.85, end: 1).animate(curved),
            child: Padding(
              padding: MediaQuery.of(ctx).viewInsets,
              child: const Center(
                child: Material(color: Colors.transparent, child: AccountDialog()),
              ),
            ),
          ),
        ),
      );
    },
  );
}

enum _Step { login, signup, created, loggedIn, failed, profile, loggedOut }

class AccountDialog extends StatefulWidget {
  const AccountDialog({super.key});

  @override
  State<AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<AccountDialog> {
  final AuthService auth = AuthService.I;

  final _lName = TextEditingController();
  final _lPhone = TextEditingController();
  final _sName = TextEditingController();
  final _sPhone = TextEditingController();
  final _sEmail = TextEditingController();

  _Step _step = _Step.login;
  bool _busy = false;
  String? _error;
  String _failMsg = '';
  bool _failCanSignUp = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _step = auth.user != null ? _Step.profile : _Step.login;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _lName.dispose();
    _lPhone.dispose();
    _sName.dispose();
    _sPhone.dispose();
    _sEmail.dispose();
    super.dispose();
  }

  void _go(_Step s) {
    _timer?.cancel();
    setState(() {
      _step = s;
      _error = null;
    });
  }

  void _closeAfter(int ms) {
    _timer?.cancel();
    _timer = Timer(Duration(milliseconds: ms), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  // ── Actions ─────────────────────────────────────────────────────────

  Future<void> _doLogin() async {
    if (_busy) return;
    final err = AuthService.validateName(_lName.text) ?? AuthService.validatePhone(_lPhone.text);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await auth.login(_lName.text, _lPhone.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.ok) {
      _go(_Step.loggedIn);
      _closeAfter(2200);
    } else {
      _failMsg = r.message;
      _failCanSignUp = r.status == AuthStatus.wrongDetails;
      _go(_Step.failed);
    }
  }

  Future<void> _doSignUp() async {
    if (_busy) return;
    final err = AuthService.validateName(_sName.text) ??
        AuthService.validatePhone(_sPhone.text) ??
        AuthService.validateEmail(_sEmail.text);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await auth.signUp(_sName.text, _sPhone.text, _sEmail.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.ok) {
      _lName.text = _sName.text;
      _lPhone.text = _sPhone.text;
      _go(_Step.created);
      _timer = Timer(const Duration(milliseconds: 2600), () {
        if (mounted) _go(_Step.login);
      });
    } else {
      setState(() => _error = r.message);
    }
  }

  Future<void> _doLogout() async {
    final messenger = ScaffoldMessenger.of(context);
    await auth.logout();
    if (!mounted) return;
    _go(_Step.loggedOut);
    _timer = Timer(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(const SnackBar(content: Text('You are logged out.')));
    });
  }

  // ── Layout ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final dur = AppPrefs.I.animations ? const Duration(milliseconds: 350) : Duration.zero;
    return PopGlow(
      builder: (g) => Container(
        constraints: BoxConstraints(
          maxWidth: 400,
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        margin: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF151A23),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: AppColors.accentCyan.withOpacity(0.25 + 0.30 * g)),
          boxShadow: [
            BoxShadow(
              color: AppColors.accentCyan.withOpacity(0.16 + 0.22 * g),
              blurRadius: 28 + 26 * g,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 28, 22, 22),
              child: AnimatedSize(
                duration: dur,
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: AnimatedSwitcher(
                  duration: dur,
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeIn,
                  layoutBuilder: (current, previous) => Stack(
                    alignment: Alignment.topCenter,
                    children: [...previous, if (current != null) current],
                  ),
                  transitionBuilder: (child, a) => FadeTransition(
                    opacity: a,
                    child: SlideTransition(
                      position: Tween<Offset>(begin: const Offset(0.08, 0), end: Offset.zero).animate(a),
                      child: child,
                    ),
                  ),
                  child: KeyedSubtree(key: ValueKey(_step), child: _content()),
                ),
              ),
            ),
            Positioned(
              top: 6,
              right: 6,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white54),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content() {
    switch (_step) {
      case _Step.login:
        return _loginView();
      case _Step.signup:
        return _signupView();
      case _Step.created:
        return _hero(
          art: const _ResultArt(ok: true, color: AppColors.successGreen),
          title: 'Account created!',
          subtitle: 'Welcome aboard, ${AuthService.prettyFirstName(_sName.text)}.\nTaking you to login…',
        );
      case _Step.loggedIn:
        return _hero(
          art: const _ResultArt(ok: true, color: AppColors.successGreen),
          title: 'Logged in successfully',
          subtitle: 'Welcome, ${auth.user?.firstName ?? ''}!',
        );
      case _Step.failed:
        return _failedView();
      case _Step.profile:
        return _profileView();
      case _Step.loggedOut:
        return _hero(
          art: const _RingArt(icon: Icons.waving_hand_rounded, color: AppColors.warningAmber),
          title: 'Logged out',
          subtitle: 'See you soon!',
        );
    }
  }

  Widget _loginView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _hero(
          art: const _RingArt(icon: Icons.person_rounded, color: AppColors.accentCyan),
          title: 'Welcome back',
          subtitle: 'Log in with your first name and phone number',
        ),
        const SizedBox(height: 18),
        _field(
          controller: _lName,
          label: 'Name',
          icon: Icons.badge_outlined,
          keyboard: TextInputType.name,
          caps: TextCapitalization.words,
        ),
        const SizedBox(height: 12),
        _field(
          controller: _lPhone,
          label: 'Phone number',
          icon: Icons.phone_outlined,
          keyboard: TextInputType.phone,
          phone: true,
          action: TextInputAction.done,
          onSubmit: _doLogin,
        ),
        if (_error != null) _errorText(),
        const SizedBox(height: 16),
        _primary('Login', Icons.login_rounded, _doLogin),
        const SizedBox(height: 10),
        TextButton(
          onPressed: _busy ? null : () => _go(_Step.signup),
          child: const Text.rich(
            TextSpan(
              children: [
                TextSpan(text: 'New here?  ', style: TextStyle(color: Colors.white70, fontSize: 14.5)),
                TextSpan(
                  text: 'Click here to make a new account',
                  style: TextStyle(
                    color: AppColors.accentCyan,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Widget _signupView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _hero(
          art: const _RingArt(icon: Icons.person_add_alt_1_rounded, color: AppColors.successGreen),
          title: 'Create account',
          subtitle: 'It takes less than a minute',
        ),
        const SizedBox(height: 18),
        _field(
          controller: _sName,
          label: 'Name',
          icon: Icons.badge_outlined,
          keyboard: TextInputType.name,
          caps: TextCapitalization.words,
        ),
        const SizedBox(height: 12),
        _field(
          controller: _sPhone,
          label: 'Phone number',
          icon: Icons.phone_outlined,
          keyboard: TextInputType.phone,
          phone: true,
        ),
        const SizedBox(height: 12),
        _field(
          controller: _sEmail,
          label: 'Email ID',
          icon: Icons.email_outlined,
          keyboard: TextInputType.emailAddress,
          action: TextInputAction.done,
          onSubmit: _doSignUp,
        ),
        if (_error != null) _errorText(),
        const SizedBox(height: 16),
        _primary('Create account', Icons.check_circle_outline, _doSignUp, color: AppColors.successGreen),
        const SizedBox(height: 10),
        TextButton(
          onPressed: _busy ? null : () => _go(_Step.login),
          child: const Text.rich(
            TextSpan(
              children: [
                TextSpan(text: 'Already have an account?  ', style: TextStyle(color: Colors.white70, fontSize: 14.5)),
                TextSpan(
                  text: 'Log in',
                  style: TextStyle(
                    color: AppColors.accentCyan,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Widget _failedView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _hero(
          art: const _ResultArt(ok: false, color: AppColors.errorRed),
          title: 'Try again',
          subtitle: _failMsg,
        ),
        const SizedBox(height: 18),
        _primary('Try again', Icons.refresh_rounded, () => _go(_Step.login)),
        if (_failCanSignUp) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                _sName.text = _lName.text;
                _sPhone.text = _lPhone.text;
                _go(_Step.signup);
              },
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Create account'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _profileView() {
    final u = auth.user;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _RingArt(text: u?.initials ?? '?', color: AppColors.successGreen),
        const SizedBox(height: 14),
        Text(u?.name ?? '',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.successGreen.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Text('● Signed in',
              style: TextStyle(color: AppColors.successGreen, fontSize: 12.5, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: 18),
        _infoRow(Icons.phone_outlined, u?.phone ?? ''),
        const SizedBox(height: 8),
        _infoRow(Icons.email_outlined, u?.email ?? ''),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.errorRed, foregroundColor: Colors.white),
            onPressed: _doLogout,
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Logout'),
          ),
        ),
      ],
    );
  }

  // ── Small pieces ────────────────────────────────────────────────────

  Widget _hero({required Widget art, required String title, String? subtitle}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        art,
        const SizedBox(height: 14),
        Text(title,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 23, fontWeight: FontWeight.w800)),
        if (subtitle != null && subtitle.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60, fontSize: 14.5, height: 1.35)),
        ],
      ],
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboard = TextInputType.text,
    TextCapitalization caps = TextCapitalization.none,
    TextInputAction action = TextInputAction.next,
    bool phone = false,
    VoidCallback? onSubmit,
  }) {
    OutlineInputBorder border(Color c, double w) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: c, width: w),
        );
    return TextField(
      controller: controller,
      enabled: !_busy,
      keyboardType: keyboard,
      textCapitalization: caps,
      textInputAction: action,
      inputFormatters: phone
          ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9+\- ]')), LengthLimitingTextInputFormatter(18)]
          : [LengthLimitingTextInputFormatter(60)],
      onSubmitted: onSubmit == null ? null : (_) => onSubmit(),
      style: const TextStyle(color: Colors.white, fontSize: 16),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white60),
        prefixIcon: Icon(icon, color: AppColors.accentCyan),
        filled: true,
        fillColor: Colors.white.withOpacity(0.06),
        border: border(Colors.white12, 1),
        enabledBorder: border(Colors.white12, 1),
        focusedBorder: border(AppColors.accentCyan, 1.6),
        disabledBorder: border(Colors.white10, 1),
      ),
    );
  }

  Widget _primary(String text, IconData icon, VoidCallback onTap, {Color? color}) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        style: color == null ? null : ElevatedButton.styleFrom(backgroundColor: color),
        onPressed: _busy ? null : onTap,
        icon: _busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.black87),
              )
            : Icon(icon),
        label: Text(_busy ? 'Please wait…' : text),
      ),
    );
  }

  Widget _errorText() {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: AppColors.errorRed, size: 18),
          const SizedBox(width: 6),
          Expanded(
            child: Text(_error ?? '', style: const TextStyle(color: AppColors.errorRed, fontSize: 13.5)),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.accentCyan, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 15)),
          ),
        ],
      ),
    );
  }
}

// ── Illustrations (drawn in code, no image files needed) ────────────────

/// Glowing circle with slowly expanding rings, holding an icon or initials.
class _RingArt extends StatefulWidget {
  final IconData? icon;
  final String? text;
  final Color color;
  const _RingArt({this.icon, this.text, required this.color});

  @override
  State<_RingArt> createState() => _RingArtState();
}

class _RingArtState extends State<_RingArt> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));

  @override
  void initState() {
    super.initState();
    if (AppPrefs.I.animations) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color;
    return SizedBox(
      width: 120,
      height: 120,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) => CustomPaint(
          painter: _RingPainter(t: _c.value, color: color),
          child: child,
        ),
        child: Center(
          child: Container(
            width: 74,
            height: 74,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [color, color.withOpacity(0.55)],
              ),
              boxShadow: [BoxShadow(color: color.withOpacity(0.5), blurRadius: 24)],
            ),
            child: widget.text != null
                ? Text(widget.text!,
                    style: const TextStyle(color: Colors.black, fontSize: 28, fontWeight: FontWeight.w900))
                : Icon(widget.icon, color: Colors.black87, size: 38),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double t;
  final Color color;
  _RingPainter({required this.t, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    for (var k = 0; k < 2; k++) {
      final p = (t + k * 0.5) % 1.0;
      canvas.drawCircle(
        c,
        38 + 22 * p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color.withOpacity(0.35 * (1 - p)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.t != t || old.color != color;
}

/// Animated tick (success) or cross (failure, with a small shake).
class _ResultArt extends StatelessWidget {
  final bool ok;
  final Color color;
  const _ResultArt({required this.ok, required this.color});

  @override
  Widget build(BuildContext context) {
    final anim = AppPrefs.I.animations;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: anim ? 0.0 : 1.0, end: 1.0),
      duration: anim ? const Duration(milliseconds: 1200) : Duration.zero,
      curve: Curves.easeOutCubic,
      builder: (context, t, _) {
        final shake = ok ? 0.0 : math.sin(t * math.pi * 7) * 9 * (1 - t);
        return Transform.translate(
          offset: Offset(shake, 0),
          child: SizedBox(
            width: 120,
            height: 120,
            child: CustomPaint(painter: _ResultPainter(t: t, ok: ok, color: color)),
          ),
        );
      },
    );
  }
}

class _ResultPainter extends CustomPainter {
  final double t;
  final bool ok;
  final Color color;
  _ResultPainter({required this.t, required this.ok, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width * 0.34;

    canvas.drawCircle(
      c,
      r + 10,
      Paint()
        ..color = color.withOpacity(0.22 * t)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );
    canvas.drawCircle(c, r, Paint()..color = color.withOpacity(0.14));

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final ringT = (t / 0.6).clamp(0.0, 1.0).toDouble();
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), -math.pi / 2, 2 * math.pi * ringT, false, stroke);

    final markT = ((t - 0.5) / 0.5).clamp(0.0, 1.0).toDouble();
    final path = Path();
    if (ok) {
      path.moveTo(c.dx - r * 0.42, c.dy + r * 0.02);
      path.lineTo(c.dx - r * 0.10, c.dy + r * 0.34);
      path.lineTo(c.dx + r * 0.45, c.dy - r * 0.28);
    } else {
      path.moveTo(c.dx - r * 0.30, c.dy - r * 0.30);
      path.lineTo(c.dx + r * 0.30, c.dy + r * 0.30);
      path.moveTo(c.dx + r * 0.30, c.dy - r * 0.30);
      path.lineTo(c.dx - r * 0.30, c.dy + r * 0.30);
    }
    stroke.strokeWidth = 6.5;
    for (final metric in path.computeMetrics()) {
      canvas.drawPath(metric.extractPath(0, metric.length * markT), stroke);
    }

    // celebration sparkles
    final sp = ((t - 0.55) / 0.45).clamp(0.0, 1.0).toDouble();
    if (ok && sp > 0) {
      final dot = Paint()..color = color.withOpacity(1 - sp);
      for (var i = 0; i < 12; i++) {
        final a = i * math.pi * 2 / 12;
        final d = r + 8 + 24 * sp;
        canvas.drawCircle(c + Offset(math.cos(a) * d, math.sin(a) * d), 3.2 * (1 - sp * 0.5), dot);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ResultPainter old) => old.t != t || old.ok != ok || old.color != color;
}
