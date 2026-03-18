import 'package:flutter/material.dart';

import '../models/scored_route.dart';
import 'gradient_button.dart';

class RouteInfoCard extends StatelessWidget {
  const RouteInfoCard({
    super.key,
    required this.route,
    required this.isLoading,
    required this.buttonLabel,
    required this.onPrimaryPressed,
    this.destinationLabel,
  });

  final ScoredRoute? route;
  final bool isLoading;
  final String buttonLabel;
  final VoidCallback? onPrimaryPressed;
  final String? destinationLabel;

  @override
  Widget build(BuildContext context) {
    if (!isLoading && route == null) {
      return const SizedBox.shrink();
    }

    final BorderRadius borderRadius = BorderRadius.circular(32);
    final ThemeData theme = Theme.of(context);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.96),
          borderRadius: borderRadius,
          border: Border.all(color: const Color(0xFFF0F4FA)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: const Color(0xFF12366E).withValues(alpha: 0.10),
              blurRadius: 36,
              offset: const Offset(0, 18),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: isLoading
                ? _LoadingState(theme: theme)
                : _ReadyState(
                    route: route!,
                    destinationLabel: destinationLabel,
                    buttonLabel: buttonLabel,
                    onPrimaryPressed: onPrimaryPressed,
                    theme: theme,
                  ),
          ),
        ),
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const ValueKey<String>('loading'),
      children: <Widget>[
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: const Color(0xFFF3F7FF),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Padding(
            padding: EdgeInsets.all(14),
            child: CircularProgressIndicator(
              strokeWidth: 2.8,
              color: Color(0xFF2F6EF6),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                'Finding the safest route',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: const Color(0xFF0E1B2A),
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Checking nearby streets and safety signals around your path.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF5E6D80),
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReadyState extends StatelessWidget {
  const _ReadyState({
    required this.route,
    required this.destinationLabel,
    required this.buttonLabel,
    required this.onPrimaryPressed,
    required this.theme,
  });

  final ScoredRoute route;
  final String? destinationLabel;
  final String buttonLabel;
  final VoidCallback? onPrimaryPressed;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final int safetyScore = route.averageSafetyScore.round().clamp(0, 100);
    final int etaMinutes = (route.totalDistanceMeters / 75)
        .clamp(1, 180)
        .round();

    return Column(
      key: const ValueKey<String>('ready'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (destinationLabel != null &&
            destinationLabel!.trim().isNotEmpty) ...<Widget>[
          Text(
            destinationLabel!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF66768D),
              fontWeight: FontWeight.w600,
              letterSpacing: 0.1,
            ),
          ),
          const SizedBox(height: 16),
        ],
        Row(
          children: <Widget>[
            Expanded(
              child: _MetricBlock(
                label: 'ROUTE SAFETY SCORE',
                value: '$safetyScore%',
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: _MetricBlock(
                label: 'EST. TIME',
                value: '$etaMinutes MIN',
                alignEnd: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        GradientButton(
          label: buttonLabel,
          onPressed: onPrimaryPressed,
          height: 62,
          borderRadius: 24,
          textStyle: theme.textTheme.titleMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }
}

class _MetricBlock extends StatelessWidget {
  const _MetricBlock({
    required this.label,
    required this.value,
    this.alignEnd = false,
  });

  final String label;
  final String value;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final CrossAxisAlignment alignment = alignEnd
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;

    return Column(
      crossAxisAlignment: alignment,
      children: <Widget>[
        Text(
          label,
          textAlign: alignEnd ? TextAlign.end : TextAlign.start,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: const Color(0xFF617286),
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 10),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
          child: Text(
            value,
            textAlign: alignEnd ? TextAlign.end : TextAlign.start,
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
              color: const Color(0xFF0C1522),
              fontWeight: FontWeight.w900,
              height: 0.96,
            ),
          ),
        ),
      ],
    );
  }
}
