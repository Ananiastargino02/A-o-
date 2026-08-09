import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';

class StarRating extends StatelessWidget {
  final int value;
  final ValueChanged<int>? onChanged;
  final double size;

  const StarRating({
    super.key,
    required this.value,
    this.onChanged,
    this.size = 32,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final preenchida = i < value;
        return GestureDetector(
          onTap: onChanged == null ? null : () => onChanged!(i + 1),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Icon(
              preenchida ? Icons.star_rounded : Icons.star_border_rounded,
              color: preenchida ? AppColors.amber : AppColors.grey,
              size: size,
            ),
          ),
        );
      }),
    );
  }
}
