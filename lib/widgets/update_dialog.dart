import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/update_service.dart';
import 'app_overlays.dart';

Future<void> showUpdateBottomSheet(BuildContext context, UpdateInfo info) {
  return showAppModalSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    // _SheetFrame applies its own 0.85 height cap and its children rely on a
    // bounded constraint (Flexible around a scroll view / ListView), which the
    // helper's default scroll wrapper would remove.
    selfSizing: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _UpdateSheet(info: info),
  );
}

Future<void> showPatchNotesSheet(
  BuildContext context,
  ReleaseNotes notes, {
  bool markViewed = false,
}) async {
  await showAppModalSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    selfSizing: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PatchNotesSheet(notes: notes),
  );
  if (markViewed) await UpdateService.instance.markPatchNotesViewed(notes.version);
}

Future<void> showPatchNotesHistory(BuildContext context) async {
  final history = await UpdateService.instance.patchNotesHistory();
  if (!context.mounted) return;
  await showAppModalSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    selfSizing: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PatchNotesHistorySheet(history: history),
  );
}

class _UpdateSheet extends StatefulWidget {
  final UpdateInfo info;
  const _UpdateSheet({required this.info});

  @override
  State<_UpdateSheet> createState() => _UpdateSheetState();
}

class _UpdateSheetState extends State<_UpdateSheet> {
  UpdateDownload? _download;
  StreamSubscription<double>? _progressSubscription;
  double _progress = 0;
  bool _working = false;
  String? _error;

  @override
  void dispose() {
    _progressSubscription?.cancel();
    _download?.cancel();
    super.dispose();
  }

  Future<void> _update() async {
    setState(() {
      _working = true;
      _error = null;
      _progress = 0;
    });
    final download = UpdateService.instance.download(widget.info);
    _download = download;
    _progressSubscription = download.progress.listen((value) {
      if (mounted) setState(() => _progress = value);
    });
    try {
      final apkPath = await download.completedPath;
      if (!mounted) return;
      setState(() => _progress = 1);
      await UpdateService.instance.launchInstaller(apkPath, widget.info);
      if (mounted) Navigator.pop(context);
    } on UpdatePlatformCancelledException {
      // User cancelled — not an error, just reset the sheet quietly.
      if (mounted) setState(() => _error = null);
    } on UpdateException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'The update could not be completed.');
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
          _progress = 0;
        });
      }
      _download = null;
      await _progressSubscription?.cancel();
      _progressSubscription = null;
    }
  }

  void _cancel() {
    _download?.cancel();
    // Leave `_working` true until the download future completes and the
    // `finally` block resets state, so the button can't be double-triggered.
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _SheetFrame(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: CircleAvatar(
                radius: 30,
                backgroundColor: theme.colorScheme.primary.withAlpha(24),
                child: Icon(Icons.system_update_rounded, size: 30, color: theme.colorScheme.primary),
              ),
            ),
            const SizedBox(height: 16),
            const Center(
              child: Text('Update Available', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(height: 6),
            Center(
              child: Text(
                'Version ${widget.info.latestVersion}',
                style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 18),
            Text(widget.info.notes.summary, style: const TextStyle(height: 1.45), maxLines: 6, overflow: TextOverflow.ellipsis),
            if (_working) ...[
              const SizedBox(height: 20),
              Semantics(
                label: _progress > 0
                    ? 'Downloading update, ${(_progress * 100).round()} percent'
                    : 'Preparing update download',
                value: _progress > 0 ? '${(_progress * 100).round()}%' : null,
                child: LinearProgressIndicator(
                  value: _progress > 0 ? _progress : null,
                  minHeight: 7,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _progress > 0 ? 'Downloading ${(_progress * 100).round()}%' : 'Preparing download...',
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.w600),
                semanticsLabel: 'Update error: ${_error!}',
              ),
            ],
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _working ? _cancel : _update,
                icon: Icon(_working ? Icons.close_rounded : Icons.download_rounded),
                label: Text(_working ? 'Cancel Download' : 'Update'),
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: _working ? null : () => Navigator.pop(context),
                child: const Text('Later'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PatchNotesSheet extends StatelessWidget {
  final ReleaseNotes notes;
  const _PatchNotesSheet({required this.notes});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _SheetFrame(
      child: Flexible(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.new_releases_rounded, color: theme.colorScheme.primary, size: 30),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "What's New",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'Version ${notes.version} • ${DateFormat.yMMMd().format(notes.publishedAt.toLocal())}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                notes.summary,
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 16),
              ...notes.changes.map(
                (change) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 7),
                        child: Container(width: 6, height: 6, decoration: BoxDecoration(color: theme.colorScheme.primary, shape: BoxShape.circle)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(change, style: const TextStyle(height: 1.4))),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PatchNotesHistorySheet extends StatelessWidget {
  final List<ReleaseNotes> history;
  const _PatchNotesHistorySheet({required this.history});

  @override
  Widget build(BuildContext context) {
    return _SheetFrame(
      child: Flexible(
        child: history.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: Text('No installed update notes yet.')),
              )
            : ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                itemCount: history.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final notes = history[index];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    leading: const Icon(Icons.article_outlined),
                    title: Text('Version ${notes.version}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(notes.summary, maxLines: 2, overflow: TextOverflow.ellipsis),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => showPatchNotesSheet(context, notes),
                  );
                },
              ),
      ),
    );
  }
}

class _SheetFrame extends StatelessWidget {
  final Widget child;
  const _SheetFrame({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Theme.of(context).dividerColor, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}
