import 'package:flutter/material.dart';

import '../../models/bike_choice.dart';
import '../../models/bike_profile.dart';
import '../../theme/app_theme.dart';

enum ModelChange { fixModel, differentBike }

/// Whether [choice] names another model than [bike]: another catalogue
/// entry, a switch between catalogue and Other, or other Other text
/// (ignoring case and spacing; the year alone is a correction).
bool modelChanged(BikeProfile bike, BikeChoice choice) => switch (choice) {
  CatalogueChoice(:final model) => bike.catalogueModelId != model.id,
  OtherChoice(:final make, :final model) =>
    !bike.isOther ||
        _norm('${bike.otherMake ?? ''} ${bike.otherModel ?? bike.model}') !=
            _norm('$make $model'),
};

String _norm(String s) =>
    s.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

/// Asks whether a new model corrects this bike or names another one. Null
/// when the rider dismisses the question (nothing is saved).
Future<ModelChange?> askModelChange(BuildContext context) =>
    showDialog<ModelChange>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        scrollable: true,
        title: Text(
          'Fixing the model, or a different bike?',
          style: AppText.display(16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Fixing the model keeps your calibration and what RideGuard '
              'has learned. A different bike starts fresh with a new init '
              'ride.',
              style: AppText.body(16, color: AppColors.textMuted),
            ),
            const SizedBox(height: 20),
            FilledButton(
              key: const Key('fix-model'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.cyan,
                foregroundColor: AppColors.background,
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed: () => Navigator.of(context).pop(ModelChange.fixModel),
              child: Text(
                'FIXING THE MODEL',
                style: AppText.display(
                  13,
                  color: AppColors.background,
                ).copyWith(letterSpacing: 1.5),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              key: const Key('different-bike'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white38),
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed: () =>
                  Navigator.of(context).pop(ModelChange.differentBike),
              child: Text(
                'DIFFERENT BIKE',
                style: AppText.display(13).copyWith(letterSpacing: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
