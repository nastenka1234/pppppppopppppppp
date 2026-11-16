import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:just_audio/just_audio.dart';
import '../../core/api_client.dart';
import '../../core/jalali.dart';
import '../../core/models.dart';
import '../../theme/glass.dart';
import '../../theme/tokens.dart';
import 'player_service.dart';
import '../../theme/lottie_views.dart';

final tracksProvider = FutureProvider.autoDispose<List<Track>>((ref) async {
  final r = await Api.i.getC('/music');
  return [for (final x in (r['tracks'] as List? ?? [])) Track.fromJson(x)];
});

class MusicPage extends ConsumerWidget {
  const MusicPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks = ref.watch(tracksProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.refresh(tracksProvider.future),
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
        const PageTitle('موزیک', sub: 'برای تمرکز بیشتر'),
        tracks.when(
          loading: () => const AppLoader(),
          error: (e, _) => ErrorState(e is ApiError ? e.fa : 'خطا در دریافت موزیک',
              onRetry: () => ref.invalidate(tracksProvider)),
          data: (list) {
            if (list.isEmpty) {
              return StateView(
                asset: LottieAssets.error404,
                title: 'موزیکی در دسترس نیست',
                sub: 'ممکن است اینترنت قطع باشد.',
                size: 150,
                actionLabel: 'تلاش دوباره',
                onAction: () => ref.invalidate(tracksProvider),
              );
            }
            return StreamBuilder<SequenceState?>(
              stream: PlayerService.i.player.sequenceStateStream,
              builder: (_, snap) {
                final tag = snap.data?.currentSource?.tag;
                final curId = tag is MediaItem ? tag.id : null;
                return Column(children: [
                  for (var i = 0; i < list.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Glass(
                        radius: 24,
                        onTap: () => PlayerService.i.play(list, i),
                        child: Row(children: [
                          Icon(curId == list[i].id ? Icons.graphic_eq_rounded : Icons.play_arrow_rounded,
                              color: curId == list[i].id ? T.acc : T.tx2),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(list[i].title, style: const TextStyle(fontWeight: FontWeight.w700)),
                              if (list[i].tag.isNotEmpty)
                                Text(list[i].tag, style: const TextStyle(color: T.tx2, fontSize: 12)),
                            ]),
                          ),
                          Text(clock(list[i].duration), style: const TextStyle(color: T.tx2)),
                        ]),
                      ),
                    ),
                ]);
              },
            );
          },
        ),
      ]),
    );
  }
}
