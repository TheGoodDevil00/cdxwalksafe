import 'package:flutter/material.dart';

class SafetyLegendCard extends StatelessWidget {
  const SafetyLegendCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      color: Colors.white.withValues(alpha: 0.94),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            _LegendItem(label: 'Risky', color: Colors.red),
            _LegendItem(label: 'Cautious', color: Colors.yellow),
            _LegendItem(label: 'Safe', color: Colors.green),
          ],
        ),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label),
      ],
    );
  }
}
