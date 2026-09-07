import 'package:flutter/material.dart';
import '../../theme/payflex_tokens.dart';
import '../../utils/money.dart';
import '../../models/safebox.dart';
import '../../services/api_client.dart';
import '../../widgets/pf_mark.dart';
import '../../widgets/pf_buttons.dart';
import '../../widgets/pf_states.dart';
import 'safebox_create_screen.dart';
import 'safebox_detail_screen.dart';

class SafeboxListScreen extends StatefulWidget {
  const SafeboxListScreen({super.key});

  @override
  State<SafeboxListScreen> createState() => _SafeboxListScreenState();
}

class _SafeboxListScreenState extends State<SafeboxListScreen> {
  final ApiClient _api = ApiClient();
  bool _isLoading = true;
  String? _error;
  List<({Safebox safebox, String role})> _items = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final data = await _api.listSafeboxes();
      if (mounted) {
        setState(() {
          _items = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Safebox Group Savings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'Create Safebox',
            onPressed: () async {
              final ok = await Navigator.push<bool>(
                context,
                MaterialPageRoute(builder: (_) => const SafeboxCreateScreen()),
              );
              if (ok == true) _loadData();
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: _isLoading
            ? const Center(child: PfLoader())
            : _error != null
                ? PfErrorState(message: _error!, onRetry: _loadData)
                : _items.isEmpty
                    ? _buildEmptyState()
                    : ListView.separated(
                        padding: const EdgeInsets.all(PayFlexSpacing.lg),
                        itemCount: _items.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: PayFlexSpacing.md),
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          return _buildCard(item.safebox, item.role);
                        },
                      ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final ok = await Navigator.push<bool>(
            context,
            MaterialPageRoute(builder: (_) => const SafeboxCreateScreen()),
          );
          if (ok == true) _loadData();
        },
        backgroundColor: PayFlexColors.primaryBlue,
        icon: const Icon(Icons.shield_outlined, color: Colors.white),
        label: const Text(
          'New Safebox',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.7,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: PayFlexSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(PayFlexSpacing.xl),
              decoration: BoxDecoration(
                color: PayFlexColors.primaryBlue.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.lock_clock_outlined,
                size: 56,
                color: PayFlexColors.primaryBlue,
              ),
            ),
            const SizedBox(height: PayFlexSpacing.lg),
            Text(
              'No Active Safeboxes',
              style: PayFlexTypography.heading1,
            ),
            const SizedBox(height: PayFlexSpacing.sm),
            Text(
              'Create a transparent group savings pool to pool funds securely with friends, family, or partners.',
              style: PayFlexTypography.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(Safebox sb, String roleStr) {
    SafeboxRole role = SafeboxRole.member;
    if (roleStr.toUpperCase() == 'OWNER') role = SafeboxRole.owner;
    if (roleStr.toUpperCase() == 'ADMIN') role = SafeboxRole.admin;

    return Card(
      child: InkWell(
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SafeboxDetailScreen(safeboxId: sb.id),
            ),
          );
          _loadData();
        },
        borderRadius: BorderRadius.circular(PayFlexRadius.md),
        child: Padding(
          padding: const EdgeInsets.all(PayFlexSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      sb.name,
                      style: PayFlexTypography.heading2,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _roleBadge(role),
                ],
              ),
              const SizedBox(height: PayFlexSpacing.xs),
              Text(
                sb.description,
                style: PayFlexTypography.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: PayFlexSpacing.md),
              const Divider(),
              const SizedBox(height: PayFlexSpacing.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Pool Balance', style: PayFlexTypography.caption),
                      const SizedBox(height: 2),
                      Text(
                        formatMoney(sb.currentBalance),
                        style: PayFlexTypography.heading1.copyWith(
                          color: PayFlexColors.primaryGreen,
                        ),
                      ),
                    ],
                  ),
                  if (sb.targetAmount != null && sb.targetAmount! > 0)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('Target Goal', style: PayFlexTypography.caption),
                        const SizedBox(height: 2),
                        Text(
                          formatMoney(sb.targetAmount!),
                          style: PayFlexTypography.heading2,
                        ),
                      ],
                    ),
                ],
              ),
              if (sb.targetAmount != null && sb.targetAmount! > 0) ...[
                const SizedBox(height: PayFlexSpacing.md),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: sb.progressPercentage,
                    minHeight: 6,
                    backgroundColor: PayFlexColors.darkSurfaceAlt,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                        PayFlexColors.primaryGreen),
                  ),
                ),
                const SizedBox(height: PayFlexSpacing.xs),
                Text(
                  '${(sb.progressPercentage * 100).toStringAsFixed(1)}% achieved',
                  style: PayFlexTypography.caption,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _roleBadge(SafeboxRole role) {
    Color bg;
    Color fg;
    switch (role) {
      case SafeboxRole.owner:
        bg = PayFlexColors.primaryBlue.withOpacity(0.2);
        fg = PayFlexColors.primaryBlue;
        break;
      case SafeboxRole.admin:
        bg = PayFlexColors.warning.withOpacity(0.2);
        fg = PayFlexColors.warning;
        break;
      case SafeboxRole.member:
        bg = PayFlexColors.darkSurfaceAlt;
        fg = PayFlexColors.textMutedDark;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(PayFlexRadius.xs),
      ),
      child: Text(
        role.label.toUpperCase(),
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.bold,
          fontSize: 10,
        ),
      ),
    );
  }
}
