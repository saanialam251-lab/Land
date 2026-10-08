import 'package:flutter/material.dart';
import '../../data/app_prefs.dart';
import '../../data/auth_service.dart';
import '../../data/history_store.dart';
import '../theme.dart';
import '../widgets/account_dialog.dart';
import '../widgets/pop.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        backgroundColor: AppColors.nearBlack,
      ),
      body: Column(
        children: [
          const _SyncBanner(),
          Expanded(child: _list()),
        ],
      ),
    );
  }

  Widget _list() {
    return AnimatedBuilder(
        animation: Listenable.merge([HistoryStore.I, AppPrefs.I]),
        builder: (context, _) {
          final items = HistoryStore.I.items;
          if (items.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No measurements yet.\nMeasure something and tap SAVE.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 16, height: 1.4),
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            itemBuilder: (_, i) {
              final m = items[i];
              return Appear(
                index: i < 8 ? i : 8,
                child: Dismissible(
                  key: ValueKey(m.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 24),
                    margin: const EdgeInsets.symmetric(vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.errorRed,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  onDismissed: (_) => HistoryStore.I.remove(m.id),
                  child: Card(
                    margin: const EdgeInsets.symmetric(vertical: 5),
                    child: ListTile(
                      leading: Icon(
                        m.mode == 'room'
                            ? Icons.crop_square
                            : m.mode == 'height'
                                ? Icons.height
                                : Icons.straighten,
                        color: AppColors.accentCyan,
                      ),
                      title: Text(
                        m.sqMeters != null
                            ? '${AppPrefs.I.area(m.sqMeters!)}  •  perimeter ${AppPrefs.I.len(m.meters)}'
                            : AppPrefs.I.len(m.meters),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        '${m.mode} • ${m.points} points • ${m.at.day}/${m.at.month}/${m.at.year} '
                        '${m.at.hour.toString().padLeft(2, '0')}:${m.at.minute.toString().padLeft(2, '0')}',
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.white54),
                        onPressed: () => HistoryStore.I.remove(m.id),
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
    );
  }
}

/// Shows where the history is kept and whether it is synced to the account.
class _SyncBanner extends StatelessWidget {
  const _SyncBanner();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([HistoryStore.I, AuthService.I]),
      builder: (context, _) {
        final h = HistoryStore.I;
        final user = AuthService.I.user;
        IconData icon;
        Color color;
        String text;
        Widget? action;

        if (user == null) {
          icon = Icons.cloud_off_rounded;
          color = AppColors.warningAmber;
          text = 'Not logged in: measurements stay on this phone only. Log in to keep them in your account.';
          action = TextButton(onPressed: () => showAccountDialog(context), child: const Text('Log in'));
        } else if (h.syncState == SyncState.syncing) {
          icon = Icons.sync_rounded;
          color = AppColors.accentCyan;
          text = 'Syncing with your account…';
        } else if (h.syncState == SyncState.offline) {
          icon = Icons.cloud_off_rounded;
          color = AppColors.warningAmber;
          text = 'Offline. Your changes are saved here and will upload automatically.';
          action = IconButton(
              tooltip: 'Try again', icon: const Icon(Icons.refresh_rounded), onPressed: () => h.syncNow());
        } else if (h.syncState == SyncState.error) {
          icon = Icons.error_outline_rounded;
          color = AppColors.errorRed;
          text = h.syncMessage.isEmpty ? 'Could not sync.' : h.syncMessage;
          action = IconButton(
              tooltip: 'Try again', icon: const Icon(Icons.refresh_rounded), onPressed: () => h.syncNow());
        } else {
          final t = h.lastSynced;
          icon = Icons.cloud_done_rounded;
          color = AppColors.successGreen;
          text = t == null
              ? 'Saved to ${user.firstName}\'s account'
              : 'Saved to ${user.firstName}\'s account · synced ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
          action = IconButton(
              tooltip: 'Sync now', icon: const Icon(Icons.refresh_rounded), onPressed: () => h.syncNow());
        }

        return Container(
          margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.10),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(0.35)),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(text, style: const TextStyle(color: Colors.white70, fontSize: 13.5, height: 1.3)),
                ),
              ),
              if (action != null) action,
            ],
          ),
        );
      },
    );
  }
}
