import 'package:flutter/material.dart';
import '../../theme/payflex_tokens.dart';
import '../../theme/payflex_theme.dart';
import '../../utils/money.dart';
import '../../models/safebox.dart';
import '../../services/api_client.dart';
import '../../widgets/pf_balance_card.dart';
import '../../widgets/pf_motion.dart';
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

  Future<void> _openCreate() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const SafeboxCreateScreen()),
    );
    if (ok == true) _loadData();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: PayFlexTheme.light,
      child: Scaffold(
        backgroundColor: PfColors.offWhite,
        appBar: AppBar(
          title: const Text('Safebox Group Savings'),
          backgroundColor: PfColors.offWhite,
        ),
        body: RefreshIndicator(
          onRefresh: _loadData,
          color: PfColors.royalBlue,
          child: _isLoading
              ? const Center(child: PfBrandedLoader(size: 52))
              : _error != null
                  ? Center(child: PfInlineError(message: _error!, onRetry: _loadData))
                  : _items.isEmpty
                      ? _buildEmptyState()
                      : ListView.separated(
                          padding: const EdgeInsets.all(PfSpace.lg),
                          itemCount: _items.length,
                          separatorBuilder: (_, __) => const SizedBox(height: PfSpace.md),
                          itemBuilder: (context, index) {
                            final item = _items[index];
                            return _buildCard(item.safebox, item.role);
                          },
                        ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _openCreate,
          icon: const Icon(Icons.add_rounded),
          label: const Text('New Safebox'),
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
        padding: const EdgeInsets.symmetric(horizontal: PfSpace.xl),
        child: const PfEmptyState(
          icon: Icons.savings_outlined,
          title: 'No safeboxes yet',
          message: 'Create a transparent group savings pool to save toward '
              'something with people you trust.',
        ),
      ),
    );
  }

  Widget _buildCard(Safebox sb, String roleStr) {
    SafeboxRole role = SafeboxRole.member;
    if (roleStr.toUpperCase() == 'OWNER') role = SafeboxRole.owner;
    if (roleStr.toUpperCase() == 'ADMIN') role = SafeboxRole.admin;

    return PfPanel(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => SafeboxDetailScreen(safeboxId: sb.id)),
        );
        _loadData();
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  sb.name,
                  style: const TextStyle(color: PfColors.ink, fontSize: 15.5, fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _roleBadge(role),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            sb.description,
            style: const TextStyle(color: PfColors.inkMuted, fontSize: 12.5),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: PfSpace.md),
          const Divider(height: 1),
          const SizedBox(height: PfSpace.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Pool balance', style: TextStyle(color: PfColors.inkFaint, fontSize: 11.5)),
                  const SizedBox(height: 2),
                  Text(
                    formatMoneyValue(sb.currentBalance, 'NGN'),
                    style: PfMoneyType.small.copyWith(color: PfColors.ink),
                  ),
                ],
              ),
              if (sb.targetAmount != null && sb.targetAmount! > 0)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('Target goal', style: TextStyle(color: PfColors.inkFaint, fontSize: 11.5)),
                    const SizedBox(height: 2),
                    Text(
                      formatMoneyValue(sb.targetAmount!, 'NGN'),
                      style: const TextStyle(color: PfColors.inkMuted, fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
            ],
          ),
          if (sb.targetAmount != null && sb.targetAmount! > 0) ...[
            const SizedBox(height: PfSpace.md),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: sb.progressPercentage,
                minHeight: 6,
                backgroundColor: PfColors.surfaceAlt,
                valueColor: const AlwaysStoppedAnimation<Color>(PfColors.emerald),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${(sb.progressPercentage * 100).toStringAsFixed(1)}% achieved',
              style: const TextStyle(color: PfColors.inkFaint, fontSize: 11.5),
            ),
          ],
        ],
      ),
    );
  }

  Widget _roleBadge(SafeboxRole role) {
    return PfStatusChip(
      label: role.label,
      tone: switch (role) {
        SafeboxRole.owner => PfTone.info,
        SafeboxRole.admin => PfTone.warn,
        SafeboxRole.member => PfTone.muted,
      },
    );
  }
}
