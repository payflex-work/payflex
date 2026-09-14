import 'package:flutter/material.dart';
import '../../models/app_user.dart';
import '../../models/safebox.dart';
import '../../services/api_client.dart';
import '../../widgets/pf_balance_card.dart';
import '../../widgets/pf_motion.dart';
import '../../widgets/pf_states.dart';
import '../../theme/payflex_tokens.dart';
import '../../theme/payflex_theme.dart';
import 'safebox_create_screen.dart';
import 'safebox_detail_screen.dart';

/// Lists the Safebox contracts this user owns, with live on-chain state
/// (owner, admins, closed, balance) re-read on every view — the backend
/// only indexes; the chain is the source of truth.
class SafeboxListScreen extends StatefulWidget {
  final AppUser user;
  const SafeboxListScreen({super.key, required this.user});

  @override
  State<SafeboxListScreen> createState() => _SafeboxListScreenState();
}

class _SafeboxListScreenState extends State<SafeboxListScreen> {
  final ApiClient _api = ApiClient();
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];

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
      final data = await _api.listSafeboxes(widget.user.id);
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
      MaterialPageRoute(builder: (_) => SafeboxCreateScreen(user: widget.user)),
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
                          itemBuilder: (context, index) => _buildCard(_items[index]),
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
          message: 'Start a group safebox and save toward something '
              'together — the money sits in a contract on Stellar, and '
              'only people you designate can withdraw it.',
        ),
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> row) {
    final contractId = row['contractId'] as String? ?? '';
    final chain = (row['chain'] as Map<String, dynamic>?) ?? const {};
    final owner = chain['owner'] as String?;
    final admins = (chain['admins'] as List<dynamic>?)?.cast<String>() ?? const [];
    final myKey = widget.user.stellarPublicKey;

    var role = SafeboxRole.member;
    if (myKey != null && owner == myKey) {
      role = SafeboxRole.owner;
    } else if (myKey != null && admins.contains(myKey)) {
      role = SafeboxRole.admin;
    }

    return PfPanel(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SafeboxDetailScreen(
              user: widget.user,
              safeboxId: contractId,
            ),
          ),
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
                  row['name'] as String? ?? 'Safebox',
                  style: const TextStyle(
                      color: PfColors.ink, fontSize: 15.5, fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _roleBadge(role),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            row['description'] as String? ?? '',
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
                  const Text('Contract balance', style: TextStyle(color: PfColors.inkFaint, fontSize: 11.5)),
                  const SizedBox(height: 2),
                  Text(
                    '${chain['balance'] ?? '0'} XLM',
                    style: const TextStyle(color: PfColors.ink, fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('Contract', style: TextStyle(color: PfColors.inkFaint, fontSize: 11.5)),
                  const SizedBox(height: 2),
                  Text(
                    shortPublicKey(contractId),
                    style: const TextStyle(color: PfColors.inkMuted, fontSize: 11.5, fontFamily: 'monospace'),
                  ),
                ],
              ),
            ],
          ),
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
