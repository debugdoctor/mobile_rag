import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../services/rag_service.dart';

class RagVisualization extends StatelessWidget {
  const RagVisualization({
    super.key,
    required this.data,
    required this.currentStep,
    required this.onClose,
    required this.locale,
  });

  final RagVisualizationData data;
  final RagVisualizationStep currentStep;
  final VoidCallback onClose;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Positioned.fill(
      child: Material(
        color: theme.colorScheme.surface,
        child: SafeArea(
          child: Column(
            children: [
              _Header(onClose: onClose, title: translate(locale, 'rag.flow.title')),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  children: [
                    _StepCard(
                      index: 1,
                      title: translate(locale, 'rag.step.query'),
                      status: _stepStatus(RagVisualizationStep.query),
                      child: data.query.trim().isEmpty
                          ? Text(translate(locale, 'rag.hint.waitQuery'))
                          : _ContentBox(text: data.query),
                    ),
                    _StepCard(
                      index: 2,
                      title: translate(locale, 'rag.step.embedding'),
                      status: data.embedding.enabled ? _stepStatus(RagVisualizationStep.embedding) : StepStatus.error,
                      child: data.embedding.enabled
                          ? Text(
                              data.embedding.model != null
                                  ? translate(locale, 'rag.embedding.doneWithModel', {'model': data.embedding.model!})
                                  : translate(locale, 'rag.embedding.processing'),
                            )
                          : Text(translate(locale, 'rag.embedding.skip')),
                    ),
                    _StepCard(
                      index: 3,
                      title: translate(locale, 'rag.step.retrieval'),
                      status: _stepStatus(RagVisualizationStep.retrieval),
                      child: data.candidates.isEmpty
                          ? Text(translate(locale, 'rag.retrieval.empty'))
                          : Column(
                              children: data.candidates.take(4).map((candidate) {
                                final similarity = candidate.similarity != null
                                    ? '${(candidate.similarity! * 100).round()}%'
                                    : translate(locale, 'common.placeholder');
                                final hitRate = candidate.hitRate != null
                                    ? '${(candidate.hitRate! * 100).round()}%'
                                    : translate(locale, 'common.placeholder');
                                return _CandidateCard(
                                  title: candidate.documentTitle ?? translate(locale, 'context.untitled'),
                                  subtitle: candidate.chunkIndex != null ? '#${candidate.chunkIndex}' : '',
                                  content: candidate.content,
                                  similarity: similarity,
                                  hitRate: hitRate,
                                  locale: locale,
                                );
                              }).toList(),
                            ),
                    ),
                    _StepCard(
                      index: 4,
                      title: translate(locale, 'rag.step.prompt'),
                      status: _stepStatus(RagVisualizationStep.prompt),
                      child: data.prompt.isEmpty ? Text(translate(locale, 'rag.prompt.empty')) : _ContentBox(text: data.prompt),
                    ),
                    _StepCard(
                      index: 5,
                      title: translate(locale, 'rag.step.generating'),
                      status: _stepStatus(RagVisualizationStep.generating),
                      child: data.answer.isEmpty
                          ? Text(translate(locale, 'rag.generating.processing'))
                          : _ContentBox(text: data.answer),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  StepStatus _stepStatus(RagVisualizationStep step) {
    if (currentStep == RagVisualizationStep.completed) {
      return StepStatus.done;
    }
    final currentIndex = RagVisualizationStep.values.indexOf(currentStep);
    final stepIndex = RagVisualizationStep.values.indexOf(step);
    if (stepIndex < currentIndex) {
      return StepStatus.done;
    }
    if (stepIndex == currentIndex) {
      return StepStatus.processing;
    }
    return StepStatus.pending;
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onClose, required this.title});

  final VoidCallback onClose;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

enum StepStatus { pending, processing, done, error }

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.index,
    required this.title,
    required this.status,
    this.child,
  });

  final int index;
  final String title;
  final StepStatus status;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = switch (status) {
      StepStatus.processing => theme.colorScheme.primary,
      StepStatus.done => Colors.green,
      StepStatus.error => theme.colorScheme.error,
      StepStatus.pending => theme.colorScheme.outline,
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: color,
                  child: status == StepStatus.processing
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text('$index', style: const TextStyle(fontSize: 12, color: Colors.white)),
                ),
                const SizedBox(width: 8),
                Text(title, style: theme.textTheme.titleSmall),
              ],
            ),
            if (child != null) ...[
              const SizedBox(height: 8),
              DefaultTextStyle(
                style: theme.textTheme.bodySmall ?? const TextStyle(),
                child: child!,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ContentBox extends StatelessWidget {
  const _ContentBox({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Text(text),
    );
  }
}

class _CandidateCard extends StatelessWidget {
  const _CandidateCard({
    required this.title,
    required this.subtitle,
    required this.content,
    required this.similarity,
    required this.hitRate,
    required this.locale,
  });

  final String title;
  final String subtitle;
  final String content;
  final String similarity;
  final String hitRate;
  final String locale;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('$title $subtitle')),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${translate(locale, 'rag.candidate.similarity', {'value': similarity})} · '
              '${translate(locale, 'rag.candidate.hitRate', {'value': hitRate})}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            Text(content, maxLines: 4, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}
