import 'package:flutter/material.dart';
import 'package:khinsider_api/khinsider_api.dart';

/// Compact key/value details block for the album side panel.
class AlbumMetadataPanel extends StatelessWidget {
  const AlbumMetadataPanel({super.key, required this.metadata});

  final AlbumMetadata metadata;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = <(String, String)>[
      if (metadata.platforms.isNotEmpty)
        ('Platforms', metadata.platforms.join(', ')),
      if (metadata.year != null) ('Year', metadata.year!),
      if (metadata.developedBy != null) ('Developed by', metadata.developedBy!),
      if (metadata.publishedBy != null) ('Published by', metadata.publishedBy!),
      if (metadata.fileCount != null) ('Files', '${metadata.fileCount}'),
      if (metadata.totalFilesize != null)
        ('Total size', metadata.totalFilesize!),
      if (metadata.dateAdded != null) ('Added', metadata.dateAdded!),
      if (metadata.albumType != null) ('Album type', metadata.albumType!),
      if (metadata.uploadedBy != null) ('Uploaded by', metadata.uploadedBy!),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (metadata.alternativeTitles.isNotEmpty) ...[
          Text(
            'Alternative titles',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            metadata.alternativeTitles.join(' · '),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
        ],
        for (final (label, value) in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 92,
                  child: Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Expanded(child: Text(value, style: theme.textTheme.bodySmall)),
              ],
            ),
          ),
      ],
    );
  }
}
