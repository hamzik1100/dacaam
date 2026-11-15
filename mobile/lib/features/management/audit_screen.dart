import 'package:flutter/material.dart';

import '../../core/i18n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/utils/formatters.dart';
import '../../data/api/api_client.dart';
import '../../data/api/dacaam_api.dart';
import '../../redux/effects.dart';
import '../../widgets/app_card.dart';
import '../../widgets/common.dart';
import '../../widgets/entrance.dart';
import '../../widgets/skeletons.dart';
import '../../widgets/states.dart';

/// Who changed what, when, and why (§37).
///
/// One entry per changed field rather than per request, so a manager reading
/// this can answer "why did that total move" instead of "something was
/// edited".
class AuditScreen extends StatefulWidget {
  const AuditScreen({super.key});

  @override
  State<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends State<AuditScreen> {
  static const List<String> _modules = <String>[
    '',
    'orders',
    'menu',
    'expenses',
    'users',
    'settings',
    'security',
    'auth',
  ];

  List<Map<String, dynamic>> _entries = <Map<String, dynamic>>[];
  String _module = '';
  bool _loading = true;
  String? _error;

  DacaamApi? get _api => Effects.api;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final DacaamApi? api = _api;
    if (api == null) {
      setState(() => _loading = false);

      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final List<dynamic> rows = await api.auditLogs(
        module: _module.isEmpty ? null : _module,
      );
      if (!mounted) return;

      setState(() {
        _entries = rows
            .map((dynamic r) => (r as Map).cast<String, dynamic>())
            .toList();
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.t('auditLogs'))),
      body: _api == null
          ? EmptyState(
              icon: Icons.cloud_off_rounded,
              title: context.t('comingSoon'),
              message: context.t('auditNeedsApi'),
            )
          : Column(
              children: <Widget>[
                ChipSelector<String>(
                  values: _modules,
                  selected: _module,
                  labelOf: (String m) =>
                      m.isEmpty ? context.t('all') : _moduleLabel(context, m),
                  onSelected: (String m) {
                    setState(() => _module = m);
                    _load();
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                Expanded(child: _body()),
              ],
            ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
        child: ListSkeleton(hasThumb: false),
      );
    }
    if (_error != null) {
      return ErrorStateView(message: _error, onRetry: _load);
    }
    if (_entries.isEmpty) {
      return EmptyState(
        icon: Icons.history_rounded,
        title: context.t('noData'),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.primary,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          0,
          AppSpacing.gutter,
          AppSpacing.xxl,
        ),
        itemCount: _entries.length,
        itemBuilder: (BuildContext context, int i) => Entrance(
          index: i,
          child: Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: _AuditTile(entry: _entries[i]),
          ),
        ),
      ),
    );
  }

  static String _moduleLabel(BuildContext context, String module) =>
      switch (module) {
        'orders' => context.t('navOrders'),
        'menu' => context.t('navMenu'),
        'expenses' => context.t('expenses'),
        'users' => context.t('usersRoles'),
        'settings' => context.t('settings'),
        'security' => context.t('security'),
        'auth' => context.t('signIn'),
        _ => module,
      };
}

class _AuditTile extends StatelessWidget {
  const _AuditTile({required this.entry});

  final Map<String, dynamic> entry;

  static const Map<String, Color> _moduleColors = <String, Color>{
    'orders': AppColors.primary,
    'menu': AppColors.secondary,
    'expenses': AppColors.violet,
    'users': AppColors.info,
    'settings': AppColors.teal,
    'security': AppColors.success,
    'auth': AppColors.subtextLight,
  };

  @override
  Widget build(BuildContext context) {
    final String module = '${entry['module']}';
    final Color color = _moduleColors[module] ?? AppColors.subtextLight;
    final String? oldValue = entry['old_value'] as String?;
    final String? newValue = entry['new_value'] as String?;
    final String? reason = entry['reason'] as String?;
    final DateTime? at = DateTime.tryParse('${entry['created_at']}');

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Flexible(
                child: StatusChip(
                  label: _humanise('${entry['action']}'),
                  color: color,
                  dense: true,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              const Spacer(),
              Text(
                at == null ? '' : Fmt.relative(at.toLocal(), context.lang),
                style: context.texts.bodySmall?.copyWith(fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: <Widget>[
              Icon(
                Icons.person_outline_rounded,
                size: 14,
                color: context.palette.subtext,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '${entry['user_name']}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.titleSmall,
                ),
              ),
              if ('${entry['record_id']}' != 'null')
                Text(
                  '#${entry['record_id']}',
                  style: context.texts.bodySmall?.copyWith(fontSize: 11),
                ),
            ],
          ),
          if (oldValue != null || newValue != null) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: <Widget>[
                if ('${entry['field']}'.isNotEmpty) ...<Widget>[
                  Text('${entry['field']}:', style: context.texts.bodySmall),
                  const SizedBox(width: 6),
                ],
                if (oldValue != null) ...<Widget>[
                  Flexible(
                    child: _Pill(text: oldValue, color: AppColors.danger),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    child: Icon(
                      Icons.arrow_forward_rounded,
                      size: 13,
                      color: context.palette.subtext,
                    ),
                  ),
                ],
                if (newValue != null)
                  Flexible(
                    child: _Pill(text: newValue, color: AppColors.success),
                  ),
              ],
            ),
          ],
          if (reason != null && reason.isNotEmpty) ...<Widget>[
            const SizedBox(height: 5),
            Text(
              '${context.t('reason')}: $reason',
              style: context.texts.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
                fontSize: 11.5,
              ),
            ),
          ],
          if ('${entry['ip']}'.isNotEmpty) ...<Widget>[
            const SizedBox(height: 5),
            Text(
              '${entry['ip']} · ${entry['device']}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.texts.labelSmall?.copyWith(fontSize: 10),
            ),
          ],
        ],
      ),
    );
  }

  /// `order_status_changed` → `Order status changed`
  static String _humanise(String action) {
    final String spaced = action.replaceAll('_', ' ');

    return spaced.isEmpty
        ? spaced
        : spaced[0].toUpperCase() + spaced.substring(1);
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: context.isDark ? 0.20 : 0.10),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
