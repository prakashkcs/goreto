import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:love_vibe_pro/config/app_env.dart';

/// Shown once on first launch — user must accept T&C to proceed.
class TermsAcceptanceScreen extends StatefulWidget {
  final VoidCallback onAccepted;
  const TermsAcceptanceScreen({super.key, required this.onAccepted});

  @override
  State<TermsAcceptanceScreen> createState() => _TermsAcceptanceScreenState();
}

class _TermsAcceptanceScreenState extends State<TermsAcceptanceScreen> {
  bool _loading = true;
  String _termsContent = '';
  String _privacyContent = '';
  bool _accepted = false;
  int _tab = 0; // 0 = terms, 1 = privacy
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadContent();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadContent() async {
    try {
      final base = AppEnv.baseUrl.replaceAll(RegExp(r'/+$'), '');
      const headers = {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };
      final results = await Future.wait([
        http
            .get(Uri.parse('$base/api_legal.php?action=terms'),
                headers: headers)
            .timeout(const Duration(seconds: 15)),
        http
            .get(Uri.parse('$base/api_legal.php?action=privacy'),
                headers: headers)
            .timeout(const Duration(seconds: 15)),
      ]);
      final td = jsonDecode(results[0].body) as Map<String, dynamic>;
      final pd = jsonDecode(results[1].body) as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _termsContent = td['page']?['content'] ?? '';
          _privacyContent = pd['page']?['content'] ?? '';
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _accept() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('terms_accepted', true);
    await prefs.setString(
        'terms_accepted_at', DateTime.now().toIso8601String());
    widget.onAccepted();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060610),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
              child: Column(
                children: [
                  ShaderMask(
                    shaderCallback: (r) => const LinearGradient(
                      colors: [Color(0xFFBF5AF2), Color(0xFFFF2FB2)],
                    ).createShader(r),
                    child: const Text(
                      'Before You Continue',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Please read and accept our Terms & Conditions and Privacy Policy to use the app.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Color(0xFF8E8E93), fontSize: 13, height: 1.5),
                  ),
                  const SizedBox(height: 16),
                  // Tab switcher
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C1C2E),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      children: [
                        _TabBtn(
                            label: 'Terms & Conditions',
                            active: _tab == 0,
                            onTap: () => setState(() {
                                  _tab = 0;
                                  _scroll.jumpTo(0);
                                })),
                        _TabBtn(
                            label: 'Privacy Policy',
                            active: _tab == 1,
                            onTap: () => setState(() {
                                  _tab = 1;
                                  _scroll.jumpTo(0);
                                })),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Content
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: Color(0xFFBF5AF2), strokeWidth: 2))
                  : SingleChildScrollView(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: _HtmlBlock(
                        html: _tab == 0 ? _termsContent : _privacyContent,
                        accentColor: _tab == 0
                            ? const Color(0xFFF97316)
                            : const Color(0xFF22C55E),
                      ),
                    ),
            ),
            // Accept bar
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: const BoxDecoration(
                color: Color(0xFF0D0D1A),
                border: Border(top: BorderSide(color: Color(0xFF1C1C2E))),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () => setState(() => _accepted = !_accepted),
                    child: Row(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: _accepted
                                ? const Color(0xFFBF5AF2)
                                : Colors.transparent,
                            border: Border.all(
                              color: _accepted
                                  ? const Color(0xFFBF5AF2)
                                  : const Color(0xFF3A3A4A),
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: _accepted
                              ? const Icon(Icons.check,
                                  color: Colors.white, size: 14)
                              : null,
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'I have read and agree to the Terms & Conditions and Privacy Policy',
                            style: TextStyle(
                                color: Color(0xCCFFFFFF),
                                fontSize: 13,
                                height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: AnimatedOpacity(
                      opacity: _accepted ? 1.0 : 0.4,
                      duration: const Duration(milliseconds: 200),
                      child: GestureDetector(
                        onTap: _accepted ? _accept : null,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFBF5AF2), Color(0xFFFF2FB2)],
                            ),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Text(
                            'Accept & Continue',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
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

class _TabBtn extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _TabBtn(
      {required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF2C2C3E) : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: active ? Colors.white : const Color(0xFF8E8E93),
              fontSize: 12,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

// Minimal HTML renderer reused from legal_screen
class _HtmlBlock extends StatelessWidget {
  final String html;
  final Color accentColor;
  const _HtmlBlock({required this.html, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    if (html.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(
            child: Text('Content unavailable',
                style: TextStyle(color: Color(0xFF8E8E93)))),
      );
    }
    final blocks = _parse(html);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: blocks.map(_build).toList(),
    );
  }

  List<_B> _parse(String raw) {
    final out = <_B>[];
    final cleaned =
        raw.replaceAll('\r\n', '\n').replaceAll(RegExp(r'<br\s*/?>'), '\n');
    final re = RegExp(r'<(h2|h3|h4|p|li)([\s\S]*?)>([\s\S]*?)<\/\1>',
        caseSensitive: false);
    for (final m in re.allMatches(cleaned)) {
      final text = _strip(m.group(3) ?? '');
      if (text.isNotEmpty) out.add(_B(m.group(1)!.toLowerCase(), text));
    }
    if (out.isEmpty) out.add(_B('p', _strip(raw)));
    return out;
  }

  String _strip(String s) => s
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&nbsp;', ' ')
      .trim();

  Widget _build(_B b) {
    switch (b.tag) {
      case 'h2':
        return Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 10),
          child: Text(b.text,
              style: TextStyle(
                  color: accentColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w800)),
        );
      case 'h3':
        return Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 4),
          child: Row(children: [
            Container(
                width: 3,
                height: 16,
                decoration: BoxDecoration(
                    color: accentColor,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 8),
            Expanded(
                child: Text(b.text,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700))),
          ]),
        );
      case 'li':
        return Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 5),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
                padding: const EdgeInsets.only(top: 7),
                child: Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                        color: accentColor, shape: BoxShape.circle))),
            const SizedBox(width: 8),
            Expanded(
                child: Text(b.text,
                    style: const TextStyle(
                        color: Color(0xCCFFFFFF), fontSize: 13, height: 1.6))),
          ]),
        );
      default:
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(b.text,
              style: const TextStyle(
                  color: Color(0xCCFFFFFF), fontSize: 13, height: 1.6)),
        );
    }
  }
}

class _B {
  final String tag, text;
  _B(this.tag, this.text);
}
