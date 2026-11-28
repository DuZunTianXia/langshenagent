import 'dart:math' as math;

import 'package:bao_link/bao_link.dart';
import 'package:flutter/material.dart';

import '../link/phone_link.dart';
import '../phone_platform.dart';
import 'link_status.dart';
import 'md/md_theme.dart';
import 'widgets.dart';

/// Usage statistics page mirroring the desktop's Usage ledger: total tokens,
/// cost, call count, daily bar chart, and model / project breakdowns.
class UsageStatsPage extends StatefulWidget {
  const UsageStatsPage({super.key, required this.link});

  final PhoneLink link;

  @override
  State<UsageStatsPage> createState() => _UsageStatsPageState();
}

class _UsageStatsPageState extends State<UsageStatsPage> {
  static const _ranges = [
    (1, '今天'),
    (7, '近 7 天'),
    (30, '近 30 天'),
  ];

  int _days = 7;
  Map<String, Object?>? _data;
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.link.usage(days: _days);
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } on LinkRemoteException catch (failure) {
      if (!mounted) return;
      setState(() {
        _error = failure.code == LinkErrors.unknown
            ? '请先更新电脑端以支持同步用量统计。'
            : failure.message;
        _loading = false;
      });
    } on Object catch (failure) {
      if (!mounted) return;
      setState(() {
        _error = failure;
        _loading = false;
      });
    }
  }

  static String _tokens(num n) {
    if (n >= 1000000000) return '${(n / 1000000000).toStringAsFixed(2)}B';
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(2)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '${n.round()}';
  }

  static String _cost(num usd) {
    final v = usd.toDouble();
    if (v <= 0) return '\$0.00';
    if (v >= 1) return '\$${v.toStringAsFixed(2)}';
    if (v >= 0.01) return '\$${v.toStringAsFixed(3)}';
    return '\$${v.toStringAsFixed(4)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('用量统计')),
      body: Column(
        children: [
          BConnectionBanner(
            link: widget.link,
            onRetry: () => widget.link.retryNow(force: true),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
            child: Row(
              children: [
                for (final (days, label) in _ranges)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () {
                        if (_days == days) return;
                        PhonePlatform.haptic('selection');
                        setState(() => _days = days);
                        _load();
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: _days == days
                              ? AppColors.accent.withValues(
                                  alpha: MdTheme.dark ? 0.2 : 0.13,
                                )
                              : AppColors.surfaceRaised,
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(
                            color: _days == days
                                ? AppColors.accent
                                : AppColors.partBorder,
                            width: _days == days ? 1.2 : 0.75,
                          ),
                        ),
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: _days == days
                                ? FontWeight.w600
                                : FontWeight.w500,
                            color: _days == days
                                ? AppColors.accent
                                : AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? Center(
                    child: CircularProgressIndicator(color: AppColors.accent),
                  )
                : _error != null
                ? BEmptyState(
                    icon: Icons.bar_chart_rounded,
                    title: '无法加载用量统计',
                    subtitle: '$_error',
                    actionLabel: '重试',
                    onAction: _load,
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    color: AppColors.accent,
                    child: _body(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    final data = _data ?? const {};
    final total =
        (data['total'] as Map?)?.cast<String, Object?>() ?? const {};
    final calls = (total['calls'] as num?) ?? 0;
    final tokens = (total['tokens'] as num?) ?? 0;
    final input = (total['input'] as num?) ?? 0;
    final output = (total['output'] as num?) ?? 0;
    final cacheRead = (total['cacheRead'] as num?) ?? 0;
    final cost = (total['cost'] as num?) ?? 0;
    final daily = [
      for (final item in (data['daily'] as List?) ?? const [])
        if (item is Map) item.cast<String, Object?>(),
    ];
    final models = [
      for (final item in (data['models'] as List?) ?? const [])
        if (item is Map) item.cast<String, Object?>(),
    ];
    final projects = [
      for (final item in (data['projects'] as List?) ?? const [])
        if (item is Map) item.cast<String, Object?>(),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
      children: [
        // Top summary KPI grid
        BCard(
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _metric('总 Tokens', _tokens(tokens), highlight: true),
                  ),
                  Expanded(child: _metric('估算费用', _cost(cost))),
                  Expanded(child: _metric('请求次数', '$calls')),
                ],
              ),
              const SizedBox(height: 12),
              Divider(height: 0.5, color: AppColors.partBorder),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _subMetric('输入', _tokens(input))),
                  Expanded(child: _subMetric('输出', _tokens(output))),
                  Expanded(child: _subMetric('缓存读取', _tokens(cacheRead))),
                ],
              ),
            ],
          ),
        ),
        if (daily.length > 1) ...[
          const SizedBox(height: 16),
          BSection(
            title: '每日趋势',
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
                child: _DailyChart(daily: daily),
              ),
            ],
          ),
        ],
        if (models.isNotEmpty)
          BSection(
            title: '按模型分布',
            children: [
              for (var i = 0; i < models.length; i++) ...[
                _rankRow(
                  name: models[i]['name'] as String? ?? 'unknown',
                  calls: (models[i]['calls'] as num?) ?? 0,
                  tokens: (models[i]['tokens'] as num?) ?? 0,
                  cost: (models[i]['cost'] as num?) ?? 0,
                  maxTokens: (models.first['tokens'] as num?) ?? 1,
                ),
                if (i < models.length - 1)
                  Divider(height: 0.5, indent: 14, color: AppColors.partBorder),
              ],
            ],
          ),
        if (projects.isNotEmpty)
          BSection(
            title: '按工作区分布',
            children: [
              for (var i = 0; i < projects.length; i++) ...[
                _rankRow(
                  name: projects[i]['name'] as String? ?? '',
                  calls: (projects[i]['calls'] as num?) ?? 0,
                  tokens: (projects[i]['tokens'] as num?) ?? 0,
                  cost: (projects[i]['cost'] as num?) ?? 0,
                  maxTokens: (projects.first['tokens'] as num?) ?? 1,
                ),
                if (i < projects.length - 1)
                  Divider(height: 0.5, indent: 14, color: AppColors.partBorder),
              ],
            ],
          ),
        if (calls == 0)
          const Padding(
            padding: EdgeInsets.only(top: 24),
            child: BEmptyState(
              icon: Icons.bar_chart_rounded,
              title: '暂无用量记录',
              subtitle: '在当前时间范围内还没有模型调用记录。',
            ),
          ),
      ],
    );
  }

  Widget _metric(String label, String value, {bool highlight = false}) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: highlight ? AppColors.accent : AppColors.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      );

  Widget _subMetric(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: TextStyle(fontSize: 11, color: AppColors.textFaint)),
      const SizedBox(height: 2),
      Text(
        value,
        style: TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
          color: AppColors.text,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    ],
  );

  Widget _rankRow({
    required String name,
    required num calls,
    required num tokens,
    required num cost,
    required num maxTokens,
  }) {
    final ratio = maxTokens > 0 ? (tokens / maxTokens).clamp(0.0, 1.0) : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${_tokens(tokens)} · ${_cost(cost)}',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 5,
                    backgroundColor: AppColors.bubbleFill,
                    valueColor: AlwaysStoppedAnimation(AppColors.accent),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '$calls 次',
                style: TextStyle(fontSize: 11, color: AppColors.textFaint),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DailyChart extends StatelessWidget {
  const _DailyChart({required this.daily});

  final List<Map<String, Object?>> daily;

  @override
  Widget build(BuildContext context) {
    final maxTokens = daily.fold<num>(
      1,
      (m, e) => math.max(m, (e['tokens'] as num?) ?? 0),
    );
    final showEvery = daily.length > 10 ? 5 : 1;
    return SizedBox(
      height: 112,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < daily.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor: math.max(
                            0.04,
                            (((daily[i]['tokens'] as num?) ?? 0) / maxTokens)
                                .clamp(0.0, 1.0),
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              color: ((daily[i]['tokens'] as num?) ?? 0) > 0
                                  ? AppColors.accent
                                  : AppColors.bubbleFill,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      i % showEvery == 0 || i == daily.length - 1
                          ? _shortDay(daily[i]['day'] as String? ?? '')
                          : '',
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.textFaint,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _shortDay(String day) {
    final parts = day.split('-');
    if (parts.length == 3) return '${int.tryParse(parts[1]) ?? parts[1]}/${int.tryParse(parts[2]) ?? parts[2]}';
    return day;
  }
}
