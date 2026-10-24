import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/bike_profile.dart';
import '../../theme/app_theme.dart';

/// "My bike isn't listed": make, model, optional year and top speed.
class OtherBikeForm extends StatelessWidget {
  const OtherBikeForm({
    super.key,
    required this.make,
    required this.model,
    required this.year,
    required this.topSpeed,
    required this.onSubmit,
  });

  final TextEditingController make;
  final TextEditingController model;
  final TextEditingController year;
  final TextEditingController topSpeed;
  final VoidCallback onSubmit;

  // Limits mirror the backend's bike record.
  static const maxMake = 40;
  static const maxModel = 60;
  static const maxName = 80;
  static const minYear = 1950;
  static const maxYear = 2030;

  static String? validateMake(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Enter the make';
    if (v.length > maxMake) return 'Up to $maxMake characters';
    return null;
  }

  /// The saved display name is "make model", at most [maxName] long.
  static String? validateModel(String? value, {String make = ''}) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Enter the model';
    if (v.length > maxModel) return 'Up to $maxModel characters';
    if (make.trim().length + 1 + v.length > maxName) {
      return 'Make and model together: up to ${maxName - 1} characters';
    }
    return null;
  }

  static String? validateYear(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return null;
    final year = int.tryParse(v);
    if (year == null || year < minYear || year > maxYear) {
      return 'A year between $minYear and $maxYear';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          key: const Key('other-make'),
          controller: make,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          inputFormatters: [LengthLimitingTextInputFormatter(maxMake)],
          style: AppText.body(18),
          decoration: const InputDecoration(
            labelText: 'Make',
            hintText: 'e.g. CFMoto',
            prefixIcon: Icon(Icons.factory_outlined),
          ),
          validator: validateMake,
        ),
        const SizedBox(height: 14),
        TextFormField(
          key: const Key('other-model'),
          controller: model,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          inputFormatters: [LengthLimitingTextInputFormatter(maxModel)],
          style: AppText.body(18),
          decoration: const InputDecoration(
            labelText: 'Model',
            hintText: 'e.g. 450NK',
            prefixIcon: Icon(Icons.two_wheeler),
          ),
          validator: (v) => validateModel(v, make: make.text),
        ),
        const SizedBox(height: 14),
        TextFormField(
          key: const Key('other-year'),
          controller: year,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.next,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(4),
          ],
          style: AppText.body(18),
          decoration: const InputDecoration(
            labelText: 'Year (optional)',
            hintText: 'e.g. 2024',
            prefixIcon: Icon(Icons.calendar_today_outlined),
          ),
          validator: validateYear,
        ),
        const SizedBox(height: 14),
        TopSpeedField(controller: topSpeed, onSubmit: onSubmit),
      ],
    );
  }
}

/// "Fastest possible speed", for Other and for catalogue models without a
/// sourced top speed.
class TopSpeedField extends StatelessWidget {
  const TopSpeedField({
    super.key,
    required this.controller,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final VoidCallback onSubmit;

  static String? validate(String? value) {
    final v = double.tryParse(value?.trim() ?? '');
    if (v == null) return 'Enter a speed in km/h';
    // Written so NaN fails too (every comparison with NaN is false).
    if (!(v >= BikeProfile.minTopSpeedKmh && v <= BikeProfile.maxTopSpeedKmh)) {
      return 'Between ${BikeProfile.minTopSpeedKmh.toInt()} and '
          '${BikeProfile.maxTopSpeedKmh.toInt()} km/h';
    }
    return null;
  }

  /// How a stored speed is shown back in the field.
  static String format(double kmh) =>
      kmh == kmh.roundToDouble() ? kmh.toStringAsFixed(0) : '$kmh';

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: const Key('top-speed-field'),
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: TextInputAction.done,
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
      style: AppText.body(18),
      decoration: const InputDecoration(
        labelText: 'Fastest possible speed',
        suffixText: 'km/h',
        prefixIcon: Icon(Icons.speed),
        helperText: 'Manufacturer top speed or the fastest your bike can go',
        helperMaxLines: 2,
      ),
      validator: validate,
      onFieldSubmitted: (_) => onSubmit(),
    );
  }
}
