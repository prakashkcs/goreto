import 'dart:async';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:love_vibe_pro/models/group_chat.dart';
import 'package:love_vibe_pro/services/group_chat_service.dart';

/// Shared look & feel for every group screen.
class GUI {
  static const bg = Color(0xFF0B0B10);
  static const surface = Color(0xFF15151C);
  static const surface2 = Color(0xFF1D1D27);
  static const border = Color(0x14FFFFFF);
  static const accent = Color(0xFFD946EF);
  static const accent2 = Color(0xFF8B5CF6);
  static const danger = Color(0xFFFF4D6D);
  static const success = Color(0xFF22C55E);
  static const warning = Color(0xFFF59E0B);
  static const info = Color(0xFF38BDF8);
  static const textHi = Colors.white;
  static const textMid = Color(0xB3FFFFFF);
  static const textLo = Color(0x73FFFFFF);

  static const gradient = LinearGradient(
    colors: [accent, accent2],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const avatarGradients = [
    [Color(0xFF7C3AED), Color(0xFFD946EF)],
    [Color(0xFF0EA5E9), Color(0xFF6366F1)],
    [Color(0xFFEC4899), Color(0xFFF97316)],
    [Color(0xFF10B981), Color(0xFF0EA5E9)],
    [Color(0xFFF59E0B), Color(0xFFEF4444)],
    [Color(0xFF8B5CF6), Color(0xFF06B6D4)],
  ];

  static List<Color> gradientFor(int seed) =>
      avatarGradients[seed.abs() % avatarGradients.length];
}

// ── Avatars ──────────────────────────────────────────────────────────────────

/// Group avatar: decodes at display size (fast), fades in quickly and shows a
/// coloured initial while loading instead of a spinner, so it never looks laggy.
class GroupAvatar extends StatelessWidget {
  final String? url;
  final String name;
  final int seed;
  final double size;
  final String? localPath;
  final double radius;

  const GroupAvatar({
    super.key,
    required this.url,
    required this.name,
    required this.seed,
    this.size = 48,
    this.localPath,
    this.radius = -1,
  });

  factory GroupAvatar.of(ChatGroup g, {double size = 48, String? localPath}) =>
      GroupAvatar(
        url: g.avatarUrl,
        name: g.name,
        seed: g.id,
        size: size,
        localPath: localPath,
      );

  @override
  Widget build(BuildContext context) {
    final r = radius < 0 ? size / 2 : radius;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final cachePx = (size * dpr).round();
    final fallback = _Initial(name: name, seed: seed, size: size);

    Widget child;
    if (localPath != null) {
      child = Image.file(File(localPath!),
          width: size,
          height: size,
          fit: BoxFit.cover,
          cacheWidth: cachePx,
          errorBuilder: (_, __, ___) => fallback);
    } else if (url != null && url!.isNotEmpty) {
      child = CachedNetworkImage(
        imageUrl: url!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        memCacheWidth: cachePx,
        fadeInDuration: const Duration(milliseconds: 120),
        fadeOutDuration: Duration.zero,
        placeholder: (_, __) => fallback,
        errorWidget: (_, __, ___) => fallback,
      );
    } else {
      child = fallback;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(r),
      child: SizedBox(width: size, height: size, child: child),
    );
  }
}

class _Initial extends StatelessWidget {
  final String name;
  final int seed;
  final double size;
  const _Initial({required this.name, required this.seed, required this.size});

  @override
  Widget build(BuildContext context) {
    final c = GUI.gradientFor(seed);
    final letter = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
            colors: c, begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      child: Text(letter,
          style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: size * 0.4)),
    );
  }
}

/// User avatar with the same fast-loading behaviour.
class UserAvatar extends StatelessWidget {
  final String? url;
  final String name;
  final int seed;
  final double size;
  const UserAvatar(
      {super.key,
      required this.url,
      required this.name,
      required this.seed,
      this.size = 40});

  @override
  Widget build(BuildContext context) =>
      GroupAvatar(url: url, name: name, seed: seed, size: size);
}

// ── Layout building blocks ───────────────────────────────────────────────────

class GSectionLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const GSectionLabel(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(text.toUpperCase(),
                style: const TextStyle(
                    color: GUI.textLo,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.9)),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Rounded card that groups tiles, iOS-settings style, with hairline dividers.
class GSection extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsets margin;
  const GSection(
      {super.key,
      required this.children,
      this.margin = const EdgeInsets.symmetric(horizontal: 16)});

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      items.add(children[i]);
      if (i < children.length - 1) {
        items.add(const Divider(
            height: 1, thickness: 1, indent: 62, color: Color(0x0FFFFFFF)));
      }
    }
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: GUI.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: GUI.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: items),
    );
  }
}

class GIconBox extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  const GIconBox(this.icon, {super.key, this.color = GUI.accent, this.size = 34});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(icon, color: color, size: size * 0.55),
    );
  }
}

class GTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool destructive;
  final int badge;

  const GTile({
    super.key,
    required this.icon,
    required this.title,
    this.iconColor = GUI.accent,
    this.subtitle,
    this.value,
    this.trailing,
    this.onTap,
    this.destructive = false,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) {
    final color = destructive ? GUI.danger : iconColor;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              GIconBox(icon, color: color),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            color: destructive ? GUI.danger : GUI.textHi,
                            fontSize: 15,
                            fontWeight: FontWeight.w500)),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: GUI.textLo, fontSize: 12.5, height: 1.3)),
                    ],
                  ],
                ),
              ),
              if (badge > 0)
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: GUI.danger,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('$badge',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700)),
                ),
              if (value != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 140),
                    child: Text(value!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            const TextStyle(color: GUI.textLo, fontSize: 14)),
                  ),
                ),
              if (trailing != null)
                Padding(
                    padding: const EdgeInsets.only(left: 8), child: trailing!)
              else if (onTap != null && !destructive)
                const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Icon(Icons.chevron_right_rounded,
                      color: GUI.textLo, size: 22),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class GSwitchTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const GSwitchTile({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    this.onChanged,
    this.subtitle,
    this.iconColor = GUI.accent,
  });

  @override
  Widget build(BuildContext context) {
    return GTile(
      icon: icon,
      iconColor: iconColor,
      title: title,
      subtitle: subtitle,
      onTap: onChanged == null ? null : () => onChanged!(!value),
      trailing: Switch.adaptive(
        value: value,
        onChanged: onChanged,
        activeTrackColor: GUI.accent,
        activeThumbColor: Colors.white,
      ),
    );
  }
}

class GPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;
  final bool destructive;
  final double height;

  const GPrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.loading = false,
    this.icon,
    this.destructive = false,
    this.height = 50,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    return Opacity(
      opacity: enabled || loading ? 1 : 0.45,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          gradient: destructive ? null : GUI.gradient,
          color: destructive ? GUI.danger : null,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: enabled ? onPressed : null,
            child: Center(
              child: loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.4))
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (icon != null) ...[
                          Icon(icon, color: Colors.white, size: 19),
                          const SizedBox(width: 8),
                        ],
                        Text(label,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15.5,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small pill button used for Accept / Decline / Invite etc.
class GPillButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool filled;
  final Color color;
  final bool loading;

  const GPillButton({
    super.key,
    required this.label,
    this.onTap,
    this.filled = true,
    this.color = GUI.accent,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          gradient: filled && color == GUI.accent ? GUI.gradient : null,
          color: filled
              ? (color == GUI.accent ? null : color)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: filled ? null : Border.all(color: GUI.border),
        ),
        child: loading
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : Text(label,
                style: TextStyle(
                    color: filled ? Colors.white : GUI.textMid,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700)),
      ),
    );
  }
}

// ── Sheets & dialogs ─────────────────────────────────────────────────────────

/// Standard bottom sheet: dark surface, rounded top, drag handle, keyboard-safe.
Future<T?> showGSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool scrollControlled = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: scrollControlled,
    // Keep tall sheets (or ones lifted by the keyboard) below the status bar
    // / notch; without it they slid under the top of the screen on iOS.
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: GUI.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2)),
              ),
              Flexible(child: builder(ctx)),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Header used at the top of a sheet.
class GSheetHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? leading;
  const GSheetHeader(
      {super.key, required this.title, this.subtitle, this.leading});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 12)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: GUI.textHi,
                        fontSize: 18,
                        fontWeight: FontWeight.w700)),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(subtitle!,
                      style: const TextStyle(
                          color: GUI.textLo, fontSize: 13, height: 1.35)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A row in an action sheet.
class GSheetAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;
  final bool destructive;
  final Color? color;

  const GSheetAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.destructive = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = destructive ? GUI.danger : (color ?? GUI.textHi);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        child: Row(
          children: [
            Icon(icon, color: c, size: 22),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          color: c, fontSize: 15, fontWeight: FontWeight.w500)),
                  if (subtitle != null)
                    Text(subtitle!,
                        style:
                            const TextStyle(color: GUI.textLo, fontSize: 12.5)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Confirmation dialog. Resolves to true when confirmed.
Future<bool> gConfirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
  IconData? icon,
}) async {
  final res = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.65),
    builder: (c) => Dialog(
      backgroundColor: GUI.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              GIconBox(icon,
                  color: destructive ? GUI.danger : GUI.accent, size: 48),
              const SizedBox(height: 14),
            ],
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: GUI.textHi,
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: GUI.textMid, fontSize: 14, height: 1.4)),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.06),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Cancel',
                        style: TextStyle(
                            color: GUI.textMid, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(c, true),
                    style: TextButton.styleFrom(
                      backgroundColor: destructive ? GUI.danger : GUI.accent,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(confirmLabel,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  return res == true;
}

// ── Text field ───────────────────────────────────────────────────────────────

class GTextField extends StatelessWidget {
  final TextEditingController controller;
  final String? hint;
  final String? label;
  final int maxLines;
  final int? maxLength;
  final Widget? prefix;
  final Widget? suffix;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final List<TextInputFormatter>? formatters;
  final TextInputType? keyboardType;
  final String? errorText;
  final FocusNode? focusNode;

  const GTextField({
    super.key,
    required this.controller,
    this.hint,
    this.label,
    this.maxLines = 1,
    this.maxLength,
    this.prefix,
    this.suffix,
    this.autofocus = false,
    this.onChanged,
    this.formatters,
    this.keyboardType,
    this.errorText,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(label!,
                style: const TextStyle(
                    color: GUI.textMid,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ),
        TextField(
          controller: controller,
          focusNode: focusNode,
          autofocus: autofocus,
          maxLines: maxLines,
          minLines: 1,
          maxLength: maxLength,
          onChanged: onChanged,
          inputFormatters: formatters,
          keyboardType: keyboardType,
          cursorColor: GUI.accent,
          style: const TextStyle(color: GUI.textHi, fontSize: 15.5),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: GUI.textLo),
            prefixIcon: prefix,
            suffixIcon: suffix,
            filled: true,
            fillColor: GUI.surface2,
            counterStyle: const TextStyle(color: GUI.textLo, fontSize: 11.5),
            errorText: errorText,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: GUI.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: GUI.accent, width: 1.4),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: GUI.danger),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: GUI.danger, width: 1.4),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Username handling ────────────────────────────────────────────────────────

/// Turns a group name into a username suggestion, e.g. "Travel Fans!" → travel_fans.
String slugifyGroupName(String name) {
  var s = name.trim().toLowerCase();
  s = s.replaceAll(RegExp(r'[\s\-]+'), '_');
  s = s.replaceAll(RegExp(r'[^a-z0-9_.]'), '');
  s = s.replaceAll(RegExp(r'[_.]{2,}'), '_');
  s = s.replaceAll(RegExp(r'^[_.]+|[_.]+$'), '');
  if (s.length > 24) s = s.substring(0, 24).replaceAll(RegExp(r'[_.]+$'), '');
  return s;
}

final usernameFormatter = <TextInputFormatter>[
  FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_.]')),
  LengthLimitingTextInputFormatter(30),
  TextInputFormatter.withFunction((o, n) => n.copyWith(text: n.text.toLowerCase())),
];

enum UsernameState { idle, checking, available, taken, invalid }

/// Debounced live availability check for a group username.
class UsernameChecker {
  final GroupChatService service;
  final int groupId;
  final void Function(UsernameState state, String? message, String? suggestion)
      onResult;
  Timer? _debounce;
  int _seq = 0;

  UsernameChecker(
      {required this.service, this.groupId = 0, required this.onResult});

  void check(String value, {String? original}) {
    _debounce?.cancel();
    final v = value.trim().toLowerCase();
    if (v.isEmpty) {
      onResult(UsernameState.idle, null, null);
      return;
    }
    if (original != null && v == original.toLowerCase()) {
      onResult(UsernameState.available, 'This is the current username', null);
      return;
    }
    if (!RegExp(r'^[a-z0-9](?:[a-z0-9_.]{1,28})[a-z0-9]$').hasMatch(v)) {
      onResult(UsernameState.invalid,
          '3-30 characters. Letters, numbers, _ and . only (not at the start or end).',
          null);
      return;
    }
    onResult(UsernameState.checking, 'Checking availability…', null);
    final seq = ++_seq;
    _debounce = Timer(const Duration(milliseconds: 450), () async {
      final r = await service.checkUsername(v, groupId: groupId);
      if (seq != _seq) return;
      if (!r.valid) {
        onResult(UsernameState.invalid, r.message, null);
      } else if (r.available) {
        onResult(UsernameState.available, 'Username is available', null);
      } else {
        onResult(UsernameState.taken, r.message ?? 'This username is taken',
            r.suggestion);
      }
    });
  }

  void dispose() => _debounce?.cancel();
}

/// Small status line under the username field.
class UsernameStatusLine extends StatelessWidget {
  final UsernameState state;
  final String? message;
  final String? suggestion;
  final ValueChanged<String>? onUseSuggestion;

  const UsernameStatusLine({
    super.key,
    required this.state,
    this.message,
    this.suggestion,
    this.onUseSuggestion,
  });

  @override
  Widget build(BuildContext context) {
    if (state == UsernameState.idle || message == null) {
      return const SizedBox(height: 4);
    }
    final (IconData icon, Color color) = switch (state) {
      UsernameState.available => (Icons.check_circle_rounded, GUI.success),
      UsernameState.checking => (Icons.more_horiz_rounded, GUI.textLo),
      UsernameState.taken => (Icons.cancel_rounded, GUI.danger),
      UsernameState.invalid => (Icons.info_rounded, GUI.warning),
      UsernameState.idle => (Icons.info_rounded, GUI.textLo),
    };
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              state == UsernameState.checking
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 1.6, color: GUI.textLo))
                  : Icon(icon, color: color, size: 15),
              const SizedBox(width: 6),
              Expanded(
                child: Text(message!,
                    style: TextStyle(color: color, fontSize: 12.5, height: 1.3)),
              ),
            ],
          ),
          if (state == UsernameState.taken &&
              suggestion != null &&
              onUseSuggestion != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: GestureDetector(
                onTap: () => onUseSuggestion!(suggestion!),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: GUI.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: GUI.accent.withValues(alpha: 0.35)),
                  ),
                  child: Text('Use @$suggestion',
                      style: const TextStyle(
                          color: GUI.accent,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Formatting ───────────────────────────────────────────────────────────────

String formatMemberCount(int n) {
  if (n == 1) return '1 member';
  if (n >= 1000) {
    return '${(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1)}k members';
  }
  return '$n members';
}

String timeAgo(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes}m ago';
  if (d.inDays < 1) return '${d.inHours}h ago';
  if (d.inDays < 7) return '${d.inDays}d ago';
  return '${t.day}/${t.month}/${t.year}';
}
