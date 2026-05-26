import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:love_vibe_pro/config/app_env.dart';

class LegalScreen extends StatefulWidget {
  final String type; // 'terms' or 'privacy'

  const LegalScreen({super.key, required this.type});

  @override
  State<LegalScreen> createState() => _LegalScreenState();
}

class _LegalScreenState extends State<LegalScreen> {
  bool _loading = true;
  String _title = '';
  String _content = '';
  String _updatedAt = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // Use async base URL so custom server URL from SharedPreferences is respected
      final apiBase =
          (await AppEnv.getBaseUrlAsync()).replaceAll(RegExp(r'/+$'), '');
      final url = Uri.parse('$apiBase/api_legal.php?action=${widget.type}');
      final resp = await http.get(url, headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 15));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;

      if (data['status'] == 'success') {
        final page = data['page'] as Map<String, dynamic>;
        if (mounted) {
          setState(() {
            _title = page['title'] ?? '';
            _content = page['content'] ?? '';
            _updatedAt = page['updated_at'] ?? '';
            _loading = false;
          });
        }
      } else {
        _setError('Content not available.');
      }
    } catch (e) {
      _setError('Failed to load content.');
    }
  }

  void _setError(String msg) {
    if (mounted)
      setState(() {
        _error = msg;
        _loading = false;
      });
  }

  @override
  Widget build(BuildContext context) {
    final isTerms = widget.type == 'terms';
    final Color accent =
        isTerms ? const Color(0xFFF97316) : const Color(0xFF22C55E);
    final List<Color> grad = isTerms
        ? [const Color(0xFFF97316), const Color(0xFFEF4444)]
        : [const Color(0xFF22C55E), const Color(0xFF16A34A)];

    return Scaffold(
      backgroundColor: const Color(0xFF060610),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics()),
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 100,
            backgroundColor: const Color(0xFF060610),
            surfaceTintColor: Colors.transparent,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      accent.withValues(alpha: 0.15),
                      const Color(0xFF060610)
                    ],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 56, 20, 12),
                  child: Row(
                    children: [
                      ShaderMask(
                        shaderCallback: (r) =>
                            LinearGradient(colors: grad).createShader(r),
                        child: Text(
                          isTerms ? 'Terms of Service' : 'Privacy Policy',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.8,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        isTerms
                            ? Icons.description_rounded
                            : Icons.privacy_tip_rounded,
                        color: accent,
                        size: 22,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_loading)
            const SliverFillRemaining(
              child: Center(
                child: CircularProgressIndicator(
                    color: Color(0xFFBF5AF2), strokeWidth: 2),
              ),
            )
          else if (_error != null)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline_rounded,
                        color: Color(0xFF8E8E93), size: 48),
                    const SizedBox(height: 12),
                    Text(_error!,
                        style: const TextStyle(
                            color: Color(0xFF8E8E93), fontSize: 15)),
                    const SizedBox(height: 20),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _loading = true;
                          _error = null;
                        });
                        _load();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: grad),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text('Retry',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_updatedAt.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border:
                              Border.all(color: accent.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          'Last updated: ${_updatedAt.split(' ').first}',
                          style: TextStyle(
                              color: accent,
                              fontSize: 12,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    _NativeHtmlRenderer(html: _content, accentColor: accent),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Lightweight HTML renderer (no external package needed) ───────────────────

class _NativeHtmlRenderer extends StatelessWidget {
  final String html;
  final Color accentColor;

  const _NativeHtmlRenderer({required this.html, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    final sections = _parse(html);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: sections.map(_buildWidget).toList(),
    );
  }

  List<_Block> _parse(String raw) {
    final out = <_Block>[];
    final cleaned =
        raw.replaceAll('\r\n', '\n').replaceAll(RegExp(r'<br\s*/?>'), '\n');

    final re = RegExp(
      r'<(h2|h3|h4|p|li)([\s\S]*?)>([\s\S]*?)<\/\1>',
      caseSensitive: false,
    );

    for (final m in re.allMatches(cleaned)) {
      final tag = m.group(1)!.toLowerCase();
      final text = _strip(m.group(3) ?? '');
      if (text.isNotEmpty) out.add(_Block(tag, text));
    }

    if (out.isEmpty) out.add(_Block('p', _strip(raw)));
    return out;
  }

  String _strip(String s) => s
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&nbsp;', ' ')
      .trim();

  Widget _buildWidget(_Block b) {
    switch (b.tag) {
      case 'h2':
        return Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 12),
          child: Text(b.text,
              style: TextStyle(
                  color: accentColor,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5)),
        );
      case 'h3':
        return Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 6),
          child: Row(
            children: [
              Container(
                  width: 3,
                  height: 18,
                  decoration: BoxDecoration(
                      color: accentColor,
                      borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 8),
              Expanded(
                child: Text(b.text,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        );
      case 'h4':
        return Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Text(b.text,
              style: TextStyle(
                  color: accentColor.withValues(alpha: 0.9),
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
        );
      case 'li':
        return Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 7),
                child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                        color: accentColor, shape: BoxShape.circle)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(b.text,
                    style: const TextStyle(
                        color: Color(0xCCFFFFFF), fontSize: 14, height: 1.6)),
              ),
            ],
          ),
        );
      default:
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(b.text,
              style: const TextStyle(
                  color: Color(0xCCFFFFFF), fontSize: 14, height: 1.7)),
        );
    }
  }
}

class _Block {
  final String tag;
  final String text;
  _Block(this.tag, this.text);
}
