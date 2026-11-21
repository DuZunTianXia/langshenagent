/// The desktop's model upstreams, as `providers` / `saveProvider` /
/// `modelDefaults` move them (see `LinkMethods` in bao_link).
library;

/// What a model's calls cost: a million tokens of each kind, in
/// [currency] (`usage.prices`' `{"input", "output", "cacheRead"?,
/// "cacheWrite"?, "currency"?}`).
class LinkModelPrice {
  LinkModelPrice({
    required this.input,
    required this.output,
    this.cacheRead,
    this.cacheWrite,
    this.currency = 'USD',
  });

  factory LinkModelPrice.fromJson(Map<String, Object?> json) =>
      LinkModelPrice(
        input: (json['input'] as num?)?.toDouble() ?? 0,
        output: (json['output'] as num?)?.toDouble() ?? 0,
        cacheRead: (json['cacheRead'] as num?)?.toDouble(),
        cacheWrite: (json['cacheWrite'] as num?)?.toDouble(),
        currency: json['currency'] as String? ?? 'USD',
      );

  double input;
  double output;
  double? cacheRead;
  double? cacheWrite;
  String currency;

  Map<String, Object?> toJson() => {
    'input': input,
    'output': output,
    'cacheRead': ?cacheRead,
    'cacheWrite': ?cacheWrite,
    'currency': currency,
  };
}

/// What an upstream charges every model it has no price of: the model's
/// price times [multiplier], [perCall] more a call, in [currency].
class LinkUpstreamRate {
  LinkUpstreamRate({this.multiplier = 1, this.currency, this.perCall = 0});

  factory LinkUpstreamRate.fromJson(Map<String, Object?> json) =>
      LinkUpstreamRate(
        multiplier: (json['multiplier'] as num?)?.toDouble() ?? 1,
        currency: json['currency'] as String?,
        perCall: (json['perCall'] as num?)?.toDouble() ?? 0,
      );

  double multiplier;
  String? currency;
  double perCall;

  Map<String, Object?> toJson() => {
    'multiplier': multiplier,
    'currency': ?currency,
    'perCall': perCall,
  };
}

/// One model of an upstream.
class LinkProviderModel {
  LinkProviderModel({
    required this.id,
    this.label,
    this.enabled = true,
    this.custom = false,
    this.missing = false,
    this.images = true,
    this.kind,
    this.contextWindow,
    this.price,
  });

  factory LinkProviderModel.fromJson(Map<String, Object?> json) =>
      LinkProviderModel(
        id: json['id'] as String? ?? '',
        label: json['label'] as String?,
        enabled: json['enabled'] != false,
        custom: json['custom'] == true,
        missing: json['missing'] == true,
        images: json['images'] != false,
        kind: json['kind'] as String?,
        contextWindow: (json['contextWindow'] as num?)?.toInt(),
        price: switch (json['price']) {
          final Map<String, Object?> price => LinkModelPrice.fromJson(price),
          _ => null,
        },
      );

  String id;
  String? label;
  bool enabled;
  final bool custom;
  bool missing;
  bool images;
  String? kind;
  int? contextWindow;

  /// Its price for usage costs; null unpriced.
  LinkModelPrice? price;

  /// A copy of this model for editing before save.
  LinkProviderModel copy() => LinkProviderModel(
    id: id,
    label: label,
    enabled: enabled,
    custom: custom,
    missing: missing,
    images: images,
    kind: kind,
    contextWindow: contextWindow,
    price: switch (price) {
      final p? => LinkModelPrice(
        input: p.input,
        output: p.output,
        cacheRead: p.cacheRead,
        cacheWrite: p.cacheWrite,
        currency: p.currency,
      ),
      _ => null,
    },
  );

  String get displayName =>
      (label?.trim().isNotEmpty ?? false) ? label!.trim() : id;

  /// `price` is always in: null clearing it, what an entry leaves out
  /// kept (`saveProvider`'s contract).
  Map<String, Object?> toJson() => {
    'id': id,
    'label': ?label,
    'enabled': enabled,
    'images': images,
    'kind': ?kind,
    'price': price?.toJson(),
  };
}

/// An upstream (`{"id", "name", "protocol", "baseUrl", …}`).
class LinkProvider {
  LinkProvider({
    required this.id,
    required this.name,
    required this.protocol,
    this.baseUrl = '',
    this.modelsUrl,
    this.endpointUrl,
    this.auth = 'auto',
    this.enabled = true,
    this.hasKey = false,
    this.follows,
    this.accounts = 0,
    this.connected = false,
    this.error,
    this.models = const [],
    this.rate,
  });

  factory LinkProvider.fromJson(Map<String, Object?> json) => LinkProvider(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    protocol: json['protocol'] as String? ?? 'anthropic',
    baseUrl: json['baseUrl'] as String? ?? '',
    modelsUrl: json['modelsUrl'] as String?,
    endpointUrl: json['endpointUrl'] as String?,
    auth: json['auth'] as String? ?? 'auto',
    enabled: json['enabled'] != false,
    hasKey: json['hasKey'] == true,
    follows: json['follows'] as String?,
    accounts: (json['accounts'] as num?)?.toInt() ?? 0,
    connected: json['connected'] == true,
    error: json['error'] as String?,
    rate: switch (json['rate']) {
      final Map<String, Object?> rate => LinkUpstreamRate.fromJson(rate),
      _ => null,
    },
    models: [
      for (final model in json['models'] as List? ?? const [])
        if (model is Map<String, Object?>) LinkProviderModel.fromJson(model),
    ],
  );

  final String id;
  String name;
  String protocol;
  String baseUrl;
  String? modelsUrl;
  String? endpointUrl;
  String auth;
  bool enabled;

  /// Its key is kept on the desktop (the key itself is never sent).
  final bool hasKey;
  final String? follows;
  final int accounts;
  final bool connected;
  final String? error;
  List<LinkProviderModel> models;

  /// Its rate over unpriced models; null at the models' own prices.
  LinkUpstreamRate? rate;

  /// Signed in with ChatGPT accounts rather than a key (`codex`).
  bool get usesAccounts => protocol == 'codex';

  /// The conversation models the picker offers (`@id/model` refs).
  List<LinkProviderModel> get chatModels => [
    for (final model in models)
      if (model.enabled && model.kind != 'image') model,
  ];

  /// Its model [model]'s ref (`@<id>/<model>`), as defaults take it.
  String refOf(LinkProviderModel model) => '@$id/${model.id}';
}

/// The models the jobs pick ([LinkMethods.modelDefaults]).
class LinkModelDefaults {
  LinkModelDefaults({this.builtinAvailable = false, this.builtinHidden = false});

  factory LinkModelDefaults.fromJson(Map<String, Object?> json) =>
      LinkModelDefaults(
        builtinAvailable:
            json['builtin'] is Map &&
            (json['builtin'] as Map)['available'] == true,
        builtinHidden:
            json['builtin'] is Map &&
            (json['builtin'] as Map)['hidden'] == true,
      )..read(json);

  void read(Map<String, Object?> json) {
    model = json['model'] as String?;
    auxiliary = json['auxiliary'] as String?;
    actions = json['actions'] as String?;
    image = json['image'] as String?;
  }

  /// New sessions' model (`@provider/model`, a built-in's name, null:
  /// the last picked).
  String? model;

  /// What the app's small jobs ask (`@provider/model`, `claude-code`,
  /// null: automatic).
  String? auxiliary;

  /// What AI actions ask (`@provider/model`, `claude-code`, `auxiliary`,
  /// null: ask each time).
  String? actions;

  /// What the agents' generate_image asks (`@provider/model`, null: the
  /// first on).
  String? image;

  /// Claude Code as set up on the machine can be offered / is hidden.
  final bool builtinAvailable;
  final bool builtinHidden;
}
