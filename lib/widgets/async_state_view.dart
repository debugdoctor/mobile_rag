import 'package:flutter/material.dart';

class AsyncStateView extends StatelessWidget {
  const AsyncStateView({
    super.key,
    required this.isLoading,
    required this.isEmpty,
    required this.emptyMessage,
    required this.child,
    this.errorMessage,
    this.onRetry,
    this.retryLabel = 'Retry',
    this.padding = const EdgeInsets.symmetric(vertical: 24),
  });

  final bool isLoading;
  final bool isEmpty;
  final String emptyMessage;
  final String? errorMessage;
  final VoidCallback? onRetry;
  final String retryLabel;
  final EdgeInsetsGeometry padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (errorMessage != null) {
      return Center(
        child: Padding(
          padding: padding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 28),
              const SizedBox(height: 8),
              Text(errorMessage!, textAlign: TextAlign.center),
              if (onRetry != null) ...[
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: onRetry,
                  child: Text(retryLabel),
                ),
              ],
            ],
          ),
        ),
      );
    }
    if (isEmpty) {
      return Center(
        child: Padding(
          padding: padding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.inbox_outlined, size: 28),
              const SizedBox(height: 8),
              Text(emptyMessage, textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }
    return child;
  }
}
