import 'dart:async';

import 'package:flutter/material.dart';

import '../link/link_providers.dart';
import '../link/phone_link.dart';
import 'md/md_theme.dart';
import 'widgets.dart';

/// The desktop's model upstreams and the jobs' default models
/// (`providers`, `saveProvider`, `deleteProvider`, `fetchModels`,
/// `modelDefaults` over the link).
class ProvidersPage extends StatefulWidget {
  const ProvidersPage({super.key, required this.link});

  final PhoneLink link;

  @override
  State<ProvidersPage> createState() => _ProvidersPageState();
}

class _ProvidersPageState extends State<ProvidersPage> {
  List<LinkProvider> _providers = const [];
  LinkModelDefaults _defaults = LinkModelDefaults();
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final result = await widget.link.providers();
      if (!mounted) return;
      setState(() {
        _providers = result.providers;
        _defaults = result.defaults;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  // --- Default models ---------------------------------------------------

  /// Every chat model of the upstreams on, as (ref, label) pairs for the
  /// pickers.
  List<(String, String)> get _modelOptions => [
    for (final provider in _providers)
      if (provider.enabled)
        for (final model in provider.chatModels)
          (provider.refOf(model), '${provider.name} · ${model.displayName}'),
  ];

  String _refLabel(String? ref) {
    if (ref == null || ref.isEmpty) return '自动';
    if (ref == 'claude-code') return 'Claude Code（本机）';
    if (ref == 'auxiliary') return '跟随辅助模型';
    for (final (value, label) in _modelOptions) {
      if (value == ref) return label;
    }
    return ref;
  }

  Future<void> _pickDefault(String key, String title) async {
    final options = <(String?, String)>[
      (null, '自动'),
      if (_defaults.builtinAvailable &&
          (key == 'auxiliary' || key == 'actions'))
        ('claude-code', 'Claude Code（本机）'),
      if (key == 'actions') ('auxiliary', '跟随辅助模型'),
      ..._modelOptions,
    ];
    final current = switch (key) {
      'model' => _defaults.model,
      'auxiliary' => _defaults.auxiliary,
      'actions' => _defaults.actions,
      'image' => _defaults.image,
      _ => null,
    };
    final picked = await showModalBottomSheet<String?>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(title, style: Theme.of(context).textTheme.titleSmall),
            ),
            for (final (value, label) in options)
              ListTile(
                title: Text(label),
                trailing: value == current
                    ? Icon(Icons.check, color: AppColors.accent, size: 18)
                    : null,
                onTap: () => Navigator.of(sheet).pop(value),
              ),
          ],
        ),
      ),
    );
    if (picked == null && current == null) return; // dismissed
    try {
      final defaults = await widget.link.modelDefaults({key: picked});
      if (!mounted) return;
      setState(() => _defaults = defaults);
    } catch (error) {
      if (mounted) showBToast(context, '保存失败：$error', isError: true);
    }
  }

  // --- Providers ----------------------------------------------------------

  Future<void> _toggle(LinkProvider provider, bool enabled) async {
    try {
      await widget.link.saveProvider({'id': provider.id, 'enabled': enabled});
      unawaited(_load());
    } catch (error) {
      if (mounted) showBToast(context, '保存失败：$error', isError: true);
    }
  }

  Future<void> _edit([LinkProvider? provider]) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ProviderEditPage(link: widget.link, provider: provider),
      ),
    );
    if (changed == true) unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('渠道与默认模型')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!, style: TextStyle(color: AppColors.textMuted)),
                  const SizedBox(height: 10),
                  BButton(label: '重试', onPressed: _load),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
              children: [
                BSection(
                  title: '默认模型',
                  children: [
                    BCell(
                      title: '新会话模型',
                      subtitle: _refLabel(_defaults.model),
                      onTap: () => _pickDefault('model', '新会话默认使用的模型'),
                    ),
                    const BDivider(),
                    BCell(
                      title: '辅助模型',
                      subtitle: _refLabel(_defaults.auxiliary),
                      onTap: () => _pickDefault('auxiliary', '小任务使用的辅助模型'),
                    ),
                    const BDivider(),
                    BCell(
                      title: 'AI 操作模型',
                      subtitle: _refLabel(_defaults.actions),
                      onTap: () => _pickDefault('actions', 'AI 操作使用的模型'),
                    ),
                    const BDivider(),
                    BCell(
                      title: '生图模型',
                      subtitle: _refLabel(_defaults.image),
                      onTap: () => _pickDefault('image', '生图任务使用的模型'),
                    ),
                  ],
                ),
                BSection(
                  title: '渠道',
                  children: [
                    for (var i = 0; i < _providers.length; i++) ...[
                      _providerCell(_providers[i]),
                      if (i < _providers.length - 1) const BDivider(),
                    ],
                    if (_providers.isNotEmpty) const BDivider(),
                    BCell(
                      icon: Icons.add,
                      iconColor: AppColors.accent,
                      title: '添加渠道',
                      titleColor: AppColors.accent,
                      showChevron: false,
                      onTap: () => _edit(),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _providerCell(LinkProvider provider) {
    final subtitle = StringBuffer(provider.baseUrl.isEmpty
        ? switch (provider.protocol) {
            'codex' => '${provider.accounts} 个账号',
            _ => '未配置地址',
          }
        : provider.baseUrl);
    final count = provider.chatModels.length;
    if (count > 0) subtitle.write(' · $count 个模型');
    if (provider.error case final error?) subtitle.write(' · $error');
    return BCell(
      title: provider.name,
      subtitle: subtitle.toString(),
      trailing: Switch.adaptive(
        value: provider.enabled,
        onChanged: (value) => _toggle(provider, value),
      ),
      onTap: () => _edit(provider),
    );
  }
}

/// An upstream's editor: its name, protocol, address, key, and which of
/// its models are offered.
class ProviderEditPage extends StatefulWidget {
  const ProviderEditPage({super.key, required this.link, this.provider});

  final PhoneLink link;
  final LinkProvider? provider;

  @override
  State<ProviderEditPage> createState() => _ProviderEditPageState();
}

class _ProviderEditPageState extends State<ProviderEditPage> {
  final _name = TextEditingController();
  final _baseUrl = TextEditingController();
  final _modelsUrl = TextEditingController();
  final _endpointUrl = TextEditingController();
  final _key = TextEditingController();
  final _custom = TextEditingController();
  final _rateMultiplier = TextEditingController();
  final _ratePerCall = TextEditingController();
  final _rateCurrency = TextEditingController();
  String _protocol = 'anthropic';
  String _auth = 'auto';
  bool _enabled = true;
  bool _saving = false;
  bool _fetching = false;
  List<LinkProviderModel> _models = [];

  bool get _isNew => widget.provider == null;
  bool get _usesAccounts => _protocol == 'codex';

  @override
  void initState() {
    super.initState();
    final provider = widget.provider;
    if (provider != null) {
      _name.text = provider.name;
      _protocol = provider.protocol;
      _baseUrl.text = provider.baseUrl;
      _modelsUrl.text = provider.modelsUrl ?? '';
      _endpointUrl.text = provider.endpointUrl ?? '';
      _auth = provider.auth;
      _enabled = provider.enabled;
      final rate = provider.rate;
      if (rate != null) {
        _rateMultiplier.text = '${rate.multiplier}';
        if (rate.perCall > 0) _ratePerCall.text = '${rate.perCall}';
        _rateCurrency.text = rate.currency ?? '';
      }
      _models = [for (final model in provider.models) model.copy()];
    }
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _baseUrl,
      _modelsUrl,
      _endpointUrl,
      _key,
      _custom,
      _rateMultiplier,
      _ratePerCall,
      _rateCurrency,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// The models the upstream lists merged into [_models]: fetched ones
  /// keep their switch, ones no longer listed are marked missing, a
  /// hand-added one stays.
  Future<void> _fetch() async {
    if (_fetching) return;
    setState(() => _fetching = true);
    try {
      final remote = await widget.link.fetchModels(
        id: widget.provider?.id,
        baseUrl: _baseUrl.text.trim(),
        protocol: _protocol,
        modelsUrl: _modelsUrl.text.trim().isEmpty
            ? null
            : _modelsUrl.text.trim(),
        auth: _auth,
        key: _key.text.trim().isEmpty ? null : _key.text.trim(),
      );
      if (!mounted) return;
      final listed = {for (final model in remote) model.id: model};
      final merged = <LinkProviderModel>[
        for (final model in _models)
          if (listed.remove(model.id) case final fresh?)
            (model
              ..label = model.label ?? fresh.label
              ..contextWindow = fresh.contextWindow
              ..missing = false)
          else if (model.custom)
            model
          else
            (model..missing = true),
        for (final model in listed.values)
          LinkProviderModel(
            id: model.id,
            label: model.label,
            enabled: true,
            images: model.images,
            kind: model.kind,
            contextWindow: model.contextWindow,
          ),
      ]..sort(
          (a, b) => a.displayName.toLowerCase().compareTo(
            b.displayName.toLowerCase(),
          ),
        );
      setState(() => _models = merged);
      showBToast(context, '拉取到 ${remote.length} 个模型');
    } catch (error) {
      if (mounted) showBToast(context, '拉取失败：$error', isError: true);
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }

  void _addCustom() {
    final id = _custom.text.trim();
    if (id.isEmpty) return;
    if (_models.any((model) => model.id == id)) {
      showBToast(context, '模型已存在');
      return;
    }
    setState(() {
      _models.add(LinkProviderModel(id: id, custom: true));
      _custom.clear();
      _models.sort(
        (a, b) => a.displayName.toLowerCase().compareTo(
          b.displayName.toLowerCase(),
        ),
      );
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_name.text.trim().isEmpty) {
      showBToast(context, '请填写名称');
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.link.saveProvider({
        'id': ?widget.provider?.id,
        'name': _name.text.trim(),
        'protocol': _protocol,
        'baseUrl': _baseUrl.text.trim(),
        'modelsUrl': _modelsUrl.text.trim(),
        'endpointUrl': _endpointUrl.text.trim(),
        'auth': _auth,
        'enabled': _enabled,
        'models': [for (final model in _models) model.toJson()],
        'rate': _rateJson(),
        if (_key.text.trim().isNotEmpty) 'key': _key.text.trim(),
      });
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showBToast(context, '保存失败：$error', isError: true);
    }
  }

  /// The rate fields as `saveProvider`'s `rate` (null clearing it);
  /// everything empty or ×1 alone unsets it.
  Map<String, Object?>? _rateJson() {
    double? number(TextEditingController field) =>
        double.tryParse(field.text.trim().replaceAll(',', ''));
    final currency = _rateCurrency.text.trim().toUpperCase();
    final multiplier = number(_rateMultiplier);
    final perCall = number(_ratePerCall);
    final empty =
        _rateMultiplier.text.trim().isEmpty &&
        _ratePerCall.text.trim().isEmpty &&
        currency.isEmpty;
    if (empty || ((multiplier ?? 1) == 1 && (perCall ?? 0) == 0 && currency.isEmpty)) {
      return null;
    }
    // `UpstreamRate.fromJson` needs a multiplier; it is 1 unstated.
    return {
      'multiplier': multiplier ?? 1,
      'perCall': perCall ?? 0,
      'currency': ?(currency.isEmpty ? null : currency),
    };
  }

  /// A model's price (a million tokens of each kind, in the currency):
  /// a sheet over its row; all cleared unsets it.
  Future<void> _editPrice(LinkProviderModel model) async {
    String number(double? value) {
      if (value == null) return '';
      final text = value.toStringAsFixed(4);
      return text.contains('.')
          ? text.replaceFirst(RegExp(r'\.?0+$'), '')
          : text;
    }

    final input = TextEditingController(text: number(model.price?.input));
    final cacheRead = TextEditingController(
      text: number(model.price?.cacheRead),
    );
    final cacheWrite = TextEditingController(
      text: number(model.price?.cacheWrite),
    );
    final output = TextEditingController(text: number(model.price?.output));
    final currency = TextEditingController(
      text: model.price?.currency ?? 'USD',
    );
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheet).viewInsets.bottom,
        ),
        child: SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            children: [
              Text(
                '「${model.displayName}」价格',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 10),
                child: Text(
                  '每百万 token 的价格，留空不计价',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: BTextField(controller: input, hint: '输入'),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: BTextField(controller: cacheRead, hint: '缓存读'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: BTextField(controller: cacheWrite, hint: '缓存写'),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: BTextField(controller: output, hint: '输出'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              BTextField(controller: currency, hint: '币种，例如 USD / CNY'),
              const SizedBox(height: 14),
              Row(
                children: [
                  if (model.price != null)
                    Expanded(
                      child: BButton(
                        label: '清除价格',
                        onPressed: () {
                          setState(() => model.price = null);
                          Navigator.of(sheet).pop();
                        },
                      ),
                    ),
                  if (model.price != null) const SizedBox(width: 10),
                  Expanded(
                    child: BButton(
                      primary: true,
                      label: '确定',
                      onPressed: () {
                        double? number(TextEditingController field) =>
                            double.tryParse(
                              field.text.trim().replaceAll(',', ''),
                            );
                        final inPrice = number(input);
                        final outPrice = number(output);
                        final allEmpty = [
                          input,
                          cacheRead,
                          cacheWrite,
                          output,
                        ].every((field) => field.text.trim().isEmpty);
                        if (allEmpty) {
                          setState(() => model.price = null);
                          Navigator.of(sheet).pop();
                          return;
                        }
                        if (inPrice == null || outPrice == null) {
                          showBToast(context, '输入和输出价格都要填', isError: true);
                          return;
                        }
                        setState(
                          () => model.price = LinkModelPrice(
                            input: inPrice,
                            output: outPrice,
                            cacheRead: number(cacheRead),
                            cacheWrite: number(cacheWrite),
                            currency:
                                currency.text.trim().isEmpty
                                    ? 'USD'
                                    : currency.text.trim().toUpperCase(),
                          ),
                        );
                        Navigator.of(sheet).pop();
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    for (final c in [input, cacheRead, cacheWrite, output, currency]) {
      c.dispose();
    }
  }

  Future<void> _delete() async {
    final ok = await showBConfirm(
      context,
      title: '删除渠道',
      body: '「${widget.provider!.name}」连同它的密钥一起删除，默认模型若指向它会被清空。确定？',
      confirm: '删除',
      danger: true,
    );
    if (!ok || !mounted) return;
    try {
      await widget.link.deleteProvider(widget.provider!.id);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) showBToast(context, '删除失败：$error', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? '添加渠道' : '编辑渠道'),
        actions: [
          if (!_isNew)
            IconButton(
              tooltip: '删除渠道',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
        children: [
          BSection(
            title: '基本信息',
            children: [
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    BTextField(controller: _name, hint: '名称，例如：DeepSeek'),
                    const SizedBox(height: 10),
                    BDropdown<String>(
                      value: _protocol,
                      hint: '协议',
                      items: const [
                        ('anthropic', 'Anthropic Messages'),
                        ('openai-chat', 'OpenAI Chat Completions'),
                        ('openai-responses', 'OpenAI Responses'),
                        ('codex', 'ChatGPT 账号（Codex）'),
                      ],
                      onChanged: (value) =>
                          setState(() => _protocol = value),
                    ),
                    if (!_usesAccounts) ...[
                      const SizedBox(height: 10),
                      BTextField(
                        controller: _baseUrl,
                        hint: 'Base URL，例如 https://api.deepseek.com',
                      ),
                      const SizedBox(height: 10),
                      BDropdown<String>(
                        value: _auth,
                        hint: '认证方式',
                        items: const [
                          ('auto', '自动（按上游要求）'),
                          ('bearer', 'Bearer Token'),
                          ('x-api-key', 'x-api-key 头'),
                        ],
                        onChanged: (value) => setState(() => _auth = value),
                      ),
                      const SizedBox(height: 10),
                      BTextField(
                        controller: _key,
                        hint: widget.provider?.hasKey == true
                            ? 'API Key（已保存，留空不修改）'
                            : 'API Key',
                      ),
                      const SizedBox(height: 10),
                      BTextField(
                        controller: _modelsUrl,
                        hint: '模型列表地址（可选，默认按 Base URL 推导）',
                      ),
                      const SizedBox(height: 10),
                      BTextField(
                        controller: _endpointUrl,
                        hint: '对话地址（可选，默认按 Base URL 推导）',
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '渠道倍率（未单独定价的模型按此折算费用）',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: BTextField(
                              controller: _rateMultiplier,
                              hint: '倍率 ×1',
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: BTextField(
                              controller: _ratePerCall,
                              hint: '每次调用费',
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 84,
                            child: BTextField(
                              controller: _rateCurrency,
                              hint: '币种',
                            ),
                          ),
                        ],
                      ),
                    ] else
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'Codex 渠道用 ChatGPT 账号登录，请在电脑上完成账号登录。',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '在模型选择器中提供',
                            style: TextStyle(
                              fontSize: 14,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        Switch.adaptive(
                          value: _enabled,
                          onChanged: (value) =>
                              setState(() => _enabled = value),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!_usesAccounts)
            BSection(
              title: '模型',
              children: [
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: BButton(
                              label: '拉取模型列表',
                              icon: Icons.download_outlined,
                              busy: _fetching,
                              expand: true,
                              onPressed: _fetch,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Row(
                              children: [
                                Expanded(
                                  child: BTextField(
                                    controller: _custom,
                                    hint: '手动添加模型 ID',
                                    onSubmitted: (_) => _addCustom(),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                BButton(label: '加', onPressed: _addCustom),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (_models.isNotEmpty) const SizedBox(height: 6),
                      for (final model in _models)
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    model.displayName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      color: model.missing
                                          ? AppColors.textFaint
                                          : AppColors.textPrimary,
                                    ),
                                  ),
                                  if (model.id != model.displayName)
                                    Text(
                                      model.id,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: AppColors.textFaint,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            if (model.missing)
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: Text(
                                  '已下架',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textFaint,
                                  ),
                                ),
                              ),
                            IconButton(
                              tooltip: model.price == null ? '设置价格' : '修改价格',
                              visualDensity: VisualDensity.compact,
                              icon: Icon(
                                model.price == null
                                    ? Icons.sell_outlined
                                    : Icons.sell,
                                size: 17,
                                color: model.price == null
                                    ? AppColors.textFaint
                                    : AppColors.accent,
                              ),
                              onPressed: () => _editPrice(model),
                            ),
                            Switch.adaptive(
                              value: model.enabled,
                              onChanged: (value) =>
                                  setState(() => model.enabled = value),
                            ),
                          ],
                        ),
                      if (_models.isEmpty)
                        Text(
                          '还没有模型，先拉取或手动添加',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: AppColors.textMuted,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: BButton(
              primary: true,
              expand: true,
              busy: _saving,
              label: '保存',
              onPressed: _save,
            ),
          ),
        ],
      ),
    );
  }
}
