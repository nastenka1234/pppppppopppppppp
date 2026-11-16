import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import '../../core/jalali.dart';
import '../../theme/tokens.dart';
import 'player_service.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final p = PlayerService.i.player;
    return StreamBuilder<SequenceState?>(
      stream: p.sequenceStateStream,
      builder: (context, snap) {
        final tag = snap.data?.currentSource?.tag;
        if (tag is! MediaItem) return const SizedBox.shrink();
        return InkWell(
          onTap: () => showFullPlayer(context),
          child: Container(
            height: 58,
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: T.sec,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: T.line),
            ),
            child: Row(children: [
              const Icon(Icons.graphic_eq_rounded, color: T.acc),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(tag.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700))),
              StreamBuilder<PlayerState>(
                stream: p.playerStateStream,
                builder: (_, s) => IconButton(
                  icon: Icon(
                      (s.data?.playing ?? false) ? Icons.pause_rounded : Icons.play_arrow_rounded),
                  onPressed: PlayerService.i.toggle,
                ),
              ),
              IconButton(icon: const Icon(Icons.skip_next_rounded), onPressed: PlayerService.i.next),
            ]),
          ),
        );
      },
    );
  }
}

void showFullPlayer(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _FullPlayer(),
  );
}

class _FullPlayer extends StatelessWidget {
  const _FullPlayer();
  @override
  Widget build(BuildContext context) {
    final p = PlayerService.i.player;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(32),
              gradient: const LinearGradient(colors: [T.acc, T.sec], begin: Alignment.topRight),
            ),
            child: const Icon(Icons.music_note_rounded, size: 54, color: T.hi),
          ),
          const SizedBox(height: 18),
          StreamBuilder<SequenceState?>(
            stream: p.sequenceStateStream,
            builder: (_, s) {
              final tag = s.data?.currentSource?.tag;
              return Text(tag is MediaItem ? tag.title : '',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900));
            },
          ),
          const SizedBox(height: 14),
          StreamBuilder<Duration?>(
            stream: p.durationStream,
            builder: (_, d) => StreamBuilder<Duration>(
              stream: p.positionStream,
              builder: (_, pos) {
                final total = (d.data ?? Duration.zero).inMilliseconds.toDouble();
                final cur = (pos.data ?? Duration.zero).inMilliseconds.toDouble();
                return Column(children: [
                  Slider(
                    value: total <= 0 ? 0 : cur.clamp(0, total),
                    max: total <= 0 ? 1 : total,
                    onChanged: (v) => p.seek(Duration(milliseconds: v.round())),
                  ),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text(clock((cur / 1000).round()), style: const TextStyle(color: T.tx2)),
                    Text(clock((total / 1000).round()), style: const TextStyle(color: T.tx2)),
                  ]),
                ]);
              },
            ),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(iconSize: 34, icon: const Icon(Icons.skip_next_rounded), onPressed: PlayerService.i.next),
            StreamBuilder<PlayerState>(
              stream: p.playerStateStream,
              builder: (_, s) => IconButton.filled(
                iconSize: 40,
                style: IconButton.styleFrom(backgroundColor: T.acc, foregroundColor: T.bg),
                icon: Icon((s.data?.playing ?? false) ? Icons.pause_rounded : Icons.play_arrow_rounded),
                onPressed: PlayerService.i.toggle,
              ),
            ),
            IconButton(iconSize: 34, icon: const Icon(Icons.skip_previous_rounded), onPressed: PlayerService.i.prev),
          ]),
        ]),
      ),
    );
  }
}
