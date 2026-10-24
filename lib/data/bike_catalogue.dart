import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/catalogue_model.dart';

export '../models/catalogue_model.dart';

/// The bundled bike catalogue (backend/app/catalogue/bikes.json).
class BikeCatalogue {
  BikeCatalogue._(this.version, this._makes, this._models)
    : _byId = {for (final m in _models) m.id: m};

  static const assetPath = 'backend/app/catalogue/bikes.json';

  static BikeCatalogue parse(String json) {
    final data = jsonDecode(json) as Map<String, dynamic>;
    return BikeCatalogue._(
      data['version'] as String,
      (data['make_order'] as List).cast<String>(),
      [
        for (final m in data['models'] as List)
          CatalogueModel.fromJson(m as Map<String, dynamic>),
      ],
    );
  }

  static Future<BikeCatalogue> load(AssetBundle bundle) async =>
      parse(await bundle.loadString(assetPath));

  final String version;
  final List<String> _makes;
  final List<CatalogueModel> _models;
  final Map<String, CatalogueModel> _byId;

  List<String> get makes => List.unmodifiable(_makes);

  /// Models of [make], by model name, newest generation first.
  List<CatalogueModel> modelsFor(String make) {
    final list = _models.where((m) => m.make == make).toList()
      ..sort((a, b) {
        final c = a.model.compareTo(b.model);
        return c != 0 ? c : b.yearFrom.compareTo(a.yearFrom);
      });
    return list;
  }

  CatalogueModel? byId(String id) => _byId[id];
}
