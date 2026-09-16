import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:khinsider_api/khinsider_api.dart';

import '../../../audio/music_export.dart';
import '../../../l10n/l10n.dart';
import '../../../state/track_cache_controller.dart';

/// Copies an album's cached tracks into the system `Music/` folder and shows
/// how far along it is.
///
/// A screen rather than a dialog on purpose:
///  * the album screen has no `Scaffold`, so a `SnackBar` raised from there
///    would only be queued and appear on some other screen;
///  * keeping the flow in its own file also keeps the album screen's code size
///    where the arm64 macOS AOT compiler is happy (see TODO.md I3: extra
///    dialog code in `album_screen.dart` made `gen_snapshot` die with
///    "Unexpected object (Class with illegal cid, full-aot)").
class ExportAlbumScreen extends ConsumerStatefulWidget {
  const ExportAlbumScreen({super.key, required this.album});

  final Album album;

  @override
  ConsumerState<ExportAlbumScreen> createState() => _ExportAlbumScreenState();
}

class _ExportAlbumScreenState extends ConsumerState<ExportAlbumScreen> {
  int _done = 0;
  int _total = 0;
  MusicExportReport? _report;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _run() async {
    final report =
        await MusicExporter(
          ref.read(audioCacheManagerProvider),
          storage: ref.read(androidStorageProvider),
        ).exportAlbum(
          widget.album,
          onProgress: (done, total) {
            if (!mounted) return;
            setState(() {
              _done = done;
              _total = total;
            });
          },
        );
    if (!mounted) return;
    setState(() => _report = report);
  }

  @override
  Widget build(BuildContext context) {
    final l = l10n(context);
    final report = _report;
    final total = _total;
    return Scaffold(
      appBar: AppBar(title: Text(l.albumExport)),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.album.summary.title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              l.exportCopyingExplain,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            if (report == null) ...[
              LinearProgressIndicator(value: total == 0 ? null : _done / total),
              const SizedBox(height: 12),
              Text(
                total == 0
                    ? l.exportLookingForCached
                    : l.exportProgress(_done, total),
              ),
            ] else ...[
              Text(
                report.summary,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  autofocus: true,
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l.actionDone),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
