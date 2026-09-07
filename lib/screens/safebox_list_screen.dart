import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import '../theme/money_formatter.dart';
import '../models/safebox_model.dart';
import '../services/safebox_service.dart';
import '../components/branded_loader.dart';
import 'safebox_create_screen.dart';
import 'safebox_detail_screen.dart';

/// Safebox Group Savings overview screen listing all pools user belongs to.
class SafeboxListScreen extends StatefulWidget {
  const SafeboxListScreen({super.key});

  @override
  State<SafeboxListScreen> createState() => _SafeboxListScreenState();
}

class _SafeboxListScreenState extends State<SafeboxListScreen> {
  final SafeboxService _service = SafeboxService();
  bool _isLoading = true;
  List<SafeboxModel> _boxes = [];

  @override
  void initState() {
    super.initState();
    _loadSafeboxes();
  }

  Future<void> _loadSafeboxes() async {
    setState(() => _isLoading = true);
    final list = await _service.getSafeboxes();
    if (mounted) {
      setState(() {
        _boxes = list;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Safebox Group Savings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'Create Safebox',
            onPressed: () async {
              final created = await Navigator.push<bool>(
                context,
                MaterialPageRoute(builder: (context) => const SafeboxCreateScreen()),
              );
              if (created == true) {
                _loadSafeboxes();
              }
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadSafeboxes,
        color: AppColors.primaryGreen,
        child: _isLoading
            ? const Center(child: BrandedLoader(size: 48))
            : _boxes.isEmpty
                ? _buildEmptyState(isDark)
                : ListView.separated(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    itemCount: _boxes.length,
                    separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
                    itemBuilder: (context, index) {
                      final box = _boxes[index];
                      return _buildSafeboxCard(box, isDark, index);
                    },
                  ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await Navigator.push<bool>(
            context,
            MaterialPageRoute(builder: (context) => const SafeboxCreateScreen()),
          );
          if (created == true) {
            _loadSafeboxes();
          }
        },
        backgroundColor: AppColors.primaryBlue,
        icon: const Icon(Icons.shield_outlined, color: Colors.white),
        label: const Text(
          'New Safebox',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.7,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.xl),
              decoration: BoxDecoration(
                color: (isDark ? AppColors.primaryBlue : AppColors.primaryGreen)
                    .withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.lock_clock_outlined,
                size: 64,
                color: isDark ? AppColors.primaryGreen : AppColors.primaryBlue,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'No Active Safeboxes',
              style: AppTypography.heading1,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Create a transparent group savings pool to pool funds with friends, family, or partners securely.',
              style: AppTypography.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSafeboxCard(SafeboxModel box, bool isDark, int index) {
    return InkWell(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => SafeboxDetailScreen(safeboxId: box.id),
          ),
        );
        _loadSafeboxes();
      },
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: isDark ? AppColors.darkSurfaceAlt : const Color(0xFFE5E5E0),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    box.name,
                    style: AppTypography.heading2,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _roleBadge(box.userRole, isDark),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              box.description,
              style: AppTypography.bodySmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AppSpacing.md),
            const Divider(),
            const SizedBox(height: AppSpacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pool Balance',
                      style: AppTypography.caption,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      MoneyFormatter.format(box.currentBalance),
                      style: AppTypography.heading1.copyWith(
                        color: AppColors.primaryGreen,
                      ),
                    ),
                  ],
                ),
                if (box.targetAmount != null && box.targetAmount! > 0)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Target Goal',
                        style: AppTypography.caption,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        MoneyFormatter.format(box.targetAmount!),
                        style: AppTypography.heading2,
                      ),
                    ],
                  ),
              ],
            ),
            if (box.targetAmount != null && box.targetAmount! > 0) ...[
              const SizedBox(height: AppSpacing.md),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: box.progressPercentage,
                  minHeight: 6,
                  backgroundColor: (isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt),
                  valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primaryGreen),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '${(box.progressPercentage * 100).toStringAsFixed(1)}% achieved',
                style: AppTypography.caption,
              ),
            ],
          ],
        ),
      ),
    )
        .animate()
        .fadeIn(duration: (200 + (index * 50)).ms)
        .slideY(begin: 0.04, end: 0.0, duration: 200.ms);
  }

  Widget _roleBadge(SafeboxRole role, bool isDark) {
    Color bg;
    Color fg;
    switch (role) {
      case SafeboxRole.owner:
        bg = AppColors.primaryBlue.withOpacity(0.2);
        fg = AppColors.primaryBlue;
        break;
      case SafeboxRole.admin:
        bg = AppColors.warning.withOpacity(0.2);
        fg = AppColors.warning;
        break;
      case SafeboxRole.member:
        bg = (isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt);
        fg = isDark ? AppColors.textOffWhite : AppColors.textDark;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Text(
        role.label.toUpperCase(),
        style: AppTypography.caption.copyWith(
          color: fg,
          fontWeight: FontWeight.w700,
          fontSize: 10,
        ),
      ),
    );
  }
}
