import 'package:flutter/material.dart';
import 'package:optional_mail_client/ui/format.dart';

/// Centered spinner.
class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.label = 'Loading'});

  final String label;

  @override
  Widget build(BuildContext context) => Center(
    child: Semantics(label: label, child: const CircularProgressIndicator()),
  );
}

/// Icon, title, optional message and action, centred and scroll-safe.
class MessageView extends StatelessWidget {
  const MessageView({
    required this.icon,
    required this.title,
    super.key,
    this.message,
    this.action,
    this.iconColor,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ExcludeSemantics(
                      child: Icon(
                        icon,
                        size: 56,
                        color: iconColor ?? theme.colorScheme.outline,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      title,
                      style: theme.textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                    if (message != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        message!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    if (action != null) ...[
                      const SizedBox(height: 24),
                      action!,
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Error state with a retry button.
class ErrorView extends StatelessWidget {
  const ErrorView({required this.error, required this.onRetry, super.key});

  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => MessageView(
    icon: Icons.cloud_off_outlined,
    iconColor: Theme.of(context).colorScheme.error,
    title: "Couldn't load",
    message: describeError(error),
    action: FilledButton.tonalIcon(
      onPressed: onRetry,
      icon: const Icon(Icons.refresh),
      label: const Text('Try again'),
    ),
  );
}

/// Static placeholder rows shown while a list loads.
class ListSkeleton extends StatelessWidget {
  const ListSkeleton({super.key, this.rows = 8, this.avatar = true});

  final int rows;
  final bool avatar;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    Widget bar(double widthFactor, double height) => FractionallySizedBox(
      widthFactor: widthFactor,
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
    return Semantics(
      label: 'Loading',
      child: ExcludeSemantics(
        child: ListView.builder(
          physics: const NeverScrollableScrollPhysics(),
          itemCount: rows,
          itemBuilder: (context, i) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                if (avatar) ...[
                  CircleAvatar(radius: 20, backgroundColor: color),
                  const SizedBox(width: 16),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      bar(i.isEven ? 0.45 : 0.6, 12),
                      const SizedBox(height: 8),
                      bar(i.isEven ? 0.85 : 0.7, 10),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
