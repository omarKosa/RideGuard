import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Label/value rows: muted key on the left, bold value end-aligned on the
/// right. Long values wrap instead of overflowing.
class KeyValueRows extends StatelessWidget {
  const KeyValueRows({super.key, required this.rows, this.valueSize = 16});

  final List<(String, String)> rows;
  final double valueSize;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (k, v) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    k,
                    style: AppText.body(15, color: AppColors.textMuted),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    v,
                    textAlign: TextAlign.end,
                    style: AppText.body(valueSize, weight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
