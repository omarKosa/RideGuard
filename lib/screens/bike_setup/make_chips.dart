import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// The MAKE chips: the top makes first, "+ more" for the rest.
class MakeChips extends StatelessWidget {
  const MakeChips({
    super.key,
    required this.makes,
    required this.selected,
    required this.expanded,
    required this.onSelected,
    required this.onExpand,
  });

  /// Makes shown before "+ more".
  static const collapsedCount = 8;

  final List<String> makes;
  final String? selected;
  final bool expanded;
  final ValueChanged<String> onSelected;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    final collapsed = !expanded && makes.length > collapsedCount;
    final shown = collapsed ? makes.take(collapsedCount) : makes;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final make in shown)
          MakeChip(
            key: Key('make-$make'),
            make: make,
            selected: make == selected,
            onTap: () => onSelected(make),
          ),
        if (collapsed)
          _Pill(
            key: const Key('more-makes'),
            label: '+ more',
            selected: false,
            onTap: onExpand,
          ),
      ],
    );
  }
}

class MakeChip extends StatelessWidget {
  const MakeChip({
    super.key,
    required this.make,
    required this.selected,
    required this.onTap,
  });

  final String make;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) =>
      _Pill(label: make, selected: selected, onTap: onTap);
}

/// A glove-sized (48 dp) rounded chip; selected is filled cyan with a tick.
class _Pill extends StatelessWidget {
  const _Pill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final shape = StadiumBorder(
      side: BorderSide(
        color: selected ? AppColors.cyan : Colors.white24,
        width: selected ? 2 : 1,
      ),
    );
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? AppColors.cyan : AppColors.surface,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48, minWidth: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (selected) ...[
                    const Icon(
                      Icons.check,
                      size: 18,
                      color: AppColors.background,
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    label,
                    style: AppText.body(
                      17,
                      color: selected ? AppColors.background : Colors.white,
                      weight: selected ? FontWeight.w700 : FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
