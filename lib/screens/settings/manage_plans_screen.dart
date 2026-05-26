import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:love_vibe_pro/services/subscription_plan_service.dart';
import 'package:love_vibe_pro/widgets/neon_toast.dart';
import 'package:love_vibe_pro/widgets/coin_icon.dart';

/// Screen for creators to manage their subscription plans (max 2)
class ManagePlansScreen extends StatefulWidget {
  const ManagePlansScreen({super.key});

  @override
  State<ManagePlansScreen> createState() => _ManagePlansScreenState();
}

class _ManagePlansScreenState extends State<ManagePlansScreen> {
  final SubscriptionPlanService _service = SubscriptionPlanService();
  List<Map<String, dynamic>> _plans = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPlans();
  }

  Future<void> _loadPlans() async {
    setState(() => _isLoading = true);
    final plans = await _service.getMyPlans();
    if (mounted) {
      setState(() {
        _plans = plans;
        _isLoading = false;
      });
    }
  }

  Future<void> _showPlanDialog({Map<String, dynamic>? existing}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) =>
          _PlanEditorDialog(existing: existing, service: _service),
    );
    if (result == true) {
      _loadPlans();
    }
  }

  Future<void> _deletePlan(Map<String, dynamic> plan) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111118),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Delete Plan?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Delete "${plan['name']}"? Existing subscribers will keep access until their subscription expires.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final result = await _service.deletePlan(int.parse(plan['id'].toString()));
    if (!mounted) return;
    if (result['status'] == 'success') {
      NeonToast.success(context, 'Plan deleted');
      _loadPlans();
    } else {
      NeonToast.error(context, result['message'] ?? 'Failed');
    }
  }

  Widget _buildField(
    TextEditingController ctrl,
    String hint,
    IconData icon, {
    bool isNumber = false,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
        prefixIcon: Icon(icon, color: const Color(0xFFFF007F), size: 20),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.06),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF05030A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF05030A),
        leading: const BackButton(color: Colors.white),
        title: const Text(
          'Subscription Plans',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFFFF007F)),
              )
            : RefreshIndicator(
                color: const Color(0xFFFF007F),
                onRefresh: _loadPlans,
                child: Builder(
                  builder: (context) {
                    final listItems = <Widget>[
                      // Info banner
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              const Color(0xFFFF007F).withValues(alpha: 0.12),
                              const Color(0xFF9C27B0).withValues(alpha: 0.06),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFFFF007F).withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.star_rounded,
                              color: Color(0xFFFF007F),
                              size: 28,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Create up to 2 subscription plans. Subscribers unlock your exclusive "Subscriber Only" posts.',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.8),
                                  fontSize: 13,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Plans list
                      ..._plans.map((plan) => _buildPlanCard(plan)),

                      // Add plan button (only if < 2)
                      if (_plans.length < 2) ...[
                        const SizedBox(height: 16),
                        GestureDetector(
                          onTap: () => _showPlanDialog(),
                          child: Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.04),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.15),
                                style: BorderStyle.solid,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(
                                      colors: [
                                        Color(0xFFFF007F),
                                        Color(0xFF9C27B0),
                                      ],
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.add,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Text(
                                  'Add New Plan',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],

                      if (_plans.length >= 2) ...[
                        const SizedBox(height: 16),
                        Center(
                          child: Text(
                            'Maximum 2 plans reached',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.4),
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ];
                    return ListView.builder(
                      padding: const EdgeInsets.all(20),
                      itemCount: listItems.length,
                      itemBuilder: (context, index) => listItems[index],
                    );
                  },
                ),
              ),
      ),
    );
  }

  Widget _buildPlanCard(Map<String, dynamic> plan) {
    final name = plan['name'] ?? 'Plan';
    final price = int.tryParse(plan['price_coins'].toString()) ?? 0;
    final duration = int.tryParse(plan['duration_days'].toString()) ?? 30;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0.06),
            Colors.white.withValues(alpha: 0.02),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFFF007F).withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF007F).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.workspace_premium,
                  color: Color(0xFFFF007F),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const CoinIcon(size: 14, color: Color(0xFFFF007F)),
                        const SizedBox(width: 4),
                        Text(
                          '$price / $duration days',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Edit
              IconButton(
                icon: Icon(
                  Icons.edit_outlined,
                  color: Colors.white.withValues(alpha: 0.6),
                  size: 20,
                ),
                onPressed: () => _showPlanDialog(existing: plan),
              ),
              // Delete
              IconButton(
                icon: Icon(
                  Icons.delete_outline,
                  color: Colors.redAccent.withValues(alpha: 0.7),
                  size: 20,
                ),
                onPressed: () => _deletePlan(plan),
              ),
            ],
          ),
          if (plan['can_message_first'] == 1 ||
              plan['can_message_first'] == true) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF9C27B0).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_outline, color: Color(0xFF9C27B0), size: 14),
                  SizedBox(width: 6),
                  Text(
                    'Only Subscribers can message you first',
                    style: TextStyle(
                      color: Color(0xFF9C27B0),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (plan['custom_features'] != null)
            ...(() {
              try {
                final List<dynamic> features = plan['custom_features'] is String
                    ? jsonDecode(plan['custom_features'])
                    : plan['custom_features'];

                if (features.isEmpty) return <Widget>[];

                return [
                  const SizedBox(height: 14),
                  const Divider(color: Colors.white10, height: 1),
                  const SizedBox(height: 12),
                  ...features.map(
                    (f) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.check_circle,
                            color: Color(0xFFFF007F),
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              f.toString(),
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.8),
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ];
              } catch (e) {
                return <Widget>[];
              }
            })(),
        ],
      ),
    );
  }
}

class _PlanEditorDialog extends StatefulWidget {
  final Map<String, dynamic>? existing;
  final SubscriptionPlanService service;

  const _PlanEditorDialog({this.existing, required this.service});

  @override
  State<_PlanEditorDialog> createState() => _PlanEditorDialogState();
}

class _PlanEditorDialogState extends State<_PlanEditorDialog> {
  late TextEditingController _nameCtrl;
  late TextEditingController _priceCtrl;
  late TextEditingController _durationCtrl;

  final List<TextEditingController> _featureCtrls = [];
  bool _canMessageFirst = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.existing?['name'] ?? '');
    _priceCtrl = TextEditingController(
      text: (widget.existing?['price_coins'] ?? '').toString(),
    );
    _durationCtrl = TextEditingController(
      text: (widget.existing?['duration_days'] ?? '30').toString(),
    );

    _canMessageFirst = widget.existing?['can_message_first'] == 1 ||
        widget.existing?['can_message_first'] == true;

    if (widget.existing?['custom_features'] != null) {
      try {
        final List<dynamic> features =
            widget.existing?['custom_features'] is String
                ? jsonDecode(widget.existing!['custom_features'])
                : widget.existing!['custom_features'];
        for (var f in features) {
          _featureCtrls.add(TextEditingController(text: f.toString()));
        }
      } catch (e) {
        // ignore parsing error
      }
    }

    if (_featureCtrls.isEmpty) {
      _featureCtrls.add(TextEditingController());
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _durationCtrl.dispose();
    for (var c in _featureCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _buildField(
    TextEditingController ctrl,
    String hint,
    IconData? icon, {
    bool isNumber = false,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
        prefixIcon: icon == null
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: CoinIcon(size: 20, color: Color(0xFFFF007F)),
              )
            : Icon(icon, color: const Color(0xFFFF007F), size: 20),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.06),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxHeight: 600),
        decoration: BoxDecoration(
          color: const Color(0xFF111118),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF007F).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.star,
                      color: Color(0xFFFF007F),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Text(
                    isEdit ? 'Edit Plan' : 'Create Premium Plan',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            // Scrollable Content
            Flexible(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                shrinkWrap: true,
                children: [
                  _buildField(
                    _nameCtrl,
                    'Plan Name (e.g. VIP Access)',
                    Icons.label_outline,
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _buildField(
                          _priceCtrl,
                          'Price',
                          null, // Signals _buildField to use CoinIcon
                          isNumber: true,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: _buildField(
                          _durationCtrl,
                          'Days',
                          Icons.calendar_today_outlined,
                          isNumber: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Plan Features',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ..._featureCtrls.asMap().entries.map((entry) {
                    final index = entry.key;
                    final c = entry.value;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: c,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                              decoration: InputDecoration(
                                hintText: 'Feature',
                                hintStyle: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.3),
                                ),
                                prefixIcon: const Icon(
                                  Icons.check_circle_outline,
                                  color: Color(0xFF9C27B0),
                                  size: 18,
                                ),
                                filled: true,
                                fillColor: Colors.white.withValues(alpha: 0.04),
                                isDense: true,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                          ),
                          if (_featureCtrls.length > 1)
                            IconButton(
                              icon: const Icon(
                                Icons.remove_circle_outline,
                                color: Colors.white54,
                                size: 20,
                              ),
                              onPressed: () =>
                                  setState(() => _featureCtrls.removeAt(index)),
                            ),
                        ],
                      ),
                    );
                  }),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => setState(
                        () => _featureCtrls.add(TextEditingController()),
                      ),
                      icon: const Icon(
                        Icons.add,
                        color: Color(0xFFFF007F),
                        size: 18,
                      ),
                      label: const Text(
                        'Add Feature',
                        style: TextStyle(color: Color(0xFFFF007F)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Only Subscribers can message you?',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      activeThumbColor: const Color(0xFFFF007F),
                      value: _canMessageFirst,
                      onChanged: (val) =>
                          setState(() => _canMessageFirst = val),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),

            // Footer Actions
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.2),
                        ),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: const Color(0xFFFF007F),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () async {
                        final name = _nameCtrl.text.trim();
                        final price = int.tryParse(_priceCtrl.text.trim()) ?? 0;
                        final duration =
                            int.tryParse(_durationCtrl.text.trim()) ?? 30;

                        final List<String> features = _featureCtrls
                            .map((c) => c.text.trim())
                            .where((s) => s.isNotEmpty)
                            .toList();

                        if (name.isEmpty) {
                          NeonToast.error(context, 'Plan name is required');
                          return;
                        }
                        if (price <= 0) {
                          NeonToast.error(
                            context,
                            'Price must be greater than 0',
                          );
                          return;
                        }

                        Map<String, dynamic> result;
                        if (isEdit) {
                          result = await widget.service.updatePlan(
                            planId: int.parse(
                              widget.existing!['id'].toString(),
                            ),
                            name: name,
                            priceCoins: price,
                            durationDays: duration,
                            customFeatures: features,
                            canMessageFirst: _canMessageFirst,
                          );
                        } else {
                          result = await widget.service.createPlan(
                            name: name,
                            priceCoins: price,
                            durationDays: duration,
                            customFeatures: features,
                            canMessageFirst: _canMessageFirst,
                          );
                        }

                        if (!context.mounted) return;
                        Navigator.pop(context, result['status'] == 'success');

                        if (result['status'] == 'success') {
                          NeonToast.success(
                            context,
                            result['message'] ?? 'Done',
                          );
                        } else {
                          NeonToast.error(
                            context,
                            result['message'] ?? 'Failed',
                          );
                        }
                      },
                      child: Text(
                        isEdit ? 'Save Changes' : 'Create Plan',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
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
