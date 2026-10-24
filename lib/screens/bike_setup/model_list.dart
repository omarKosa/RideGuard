import 'package:flutter/material.dart';

import '../../data/bike_catalogue.dart';
import '../../theme/app_theme.dart';

/// The MODEL rows of one make: name and year range.
class ModelList extends StatelessWidget {
  const ModelList({
    super.key,
    required this.models,
    required this.selected,
    required this.onSelected,
    this.selectedKey,
    this.revealKey,
    this.belowSelected,
  });

  final List<CatalogueModel> models;
  final CatalogueModel? selected;
  final ValueChanged<CatalogueModel> onSelected;

  /// Wraps the selected row (and [belowSelected]) so the page can scroll
  /// to it.
  final Key? selectedKey;

  /// Marks the end of the first few rows, so the page can bring the start
  /// of the list into view when a make is picked.
  final Key? revealKey;

  /// Shown right under the selected row (the top speed question).
  final Widget? belowSelected;

  static const _revealRows = 3;

  @override
  Widget build(BuildContext context) {
    final reveal = models.length < _revealRows ? models.length : _revealRows;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, m) in models.indexed) ...[
          if (i == reveal) SizedBox(key: revealKey),
          if (m.id == selected?.id)
            KeyedSubtree(
              key: selectedKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _row(m, true),
                  if (belowSelected != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: belowSelected,
                    ),
                ],
              ),
            )
          else
            _row(m, false),
        ],
        if (reveal == models.length) SizedBox(key: revealKey),
      ],
    );
  }

  Widget _row(CatalogueModel m, bool isSelected) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: ModelRow(
      key: Key('model-${m.id}'),
      model: m,
      selected: isSelected,
      onTap: () => onSelected(m),
    ),
  );
}

class ModelRow extends StatelessWidget {
  const ModelRow({
    super.key,
    required this.model,
    required this.selected,
    required this.onTap,
  });

  final CatalogueModel model;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(
        color: selected ? AppColors.cyan : AppColors.border,
        width: selected ? 2 : 1,
      ),
    );
    final to = model.yearTo;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected
            ? Color.alphaBlend(
                AppColors.cyan.withValues(alpha: 0.14),
                AppColors.surface,
              )
            : AppColors.surface,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      model.model,
                      style: AppText.body(18, weight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    model.yearsLabel,
                    semanticsLabel: to == null
                        ? 'from ${model.yearFrom}'
                        : '${model.yearFrom} to $to',
                    style: AppText.body(
                      15,
                      color: selected ? AppColors.cyan : AppColors.textMuted,
                    ),
                  ),
                  if (selected) ...[
                    const SizedBox(width: 10),
                    const Icon(
                      Icons.check_circle,
                      color: AppColors.cyan,
                      size: 22,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
