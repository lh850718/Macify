import '../content/content_models.dart';
import 'media_resource_resolver.dart';

enum MediaPrefetchBlockReason {
  ready,
  emptyScope,
  noLocalCycle,
  localCycleIncomplete,
  noRemoteCandidates,
}

class MediaPrefetchDecision {
  const MediaPrefetchDecision._({
    required this.reason,
    required this.remainingLocalVideoIds,
    this.video,
  });

  const MediaPrefetchDecision.ready({
    required VideoItem video,
    required Set<String> remainingLocalVideoIds,
  }) : this._(
         reason: MediaPrefetchBlockReason.ready,
         video: video,
         remainingLocalVideoIds: remainingLocalVideoIds,
       );

  const MediaPrefetchDecision.blocked({
    required MediaPrefetchBlockReason reason,
    required Set<String> remainingLocalVideoIds,
  }) : this._(reason: reason, remainingLocalVideoIds: remainingLocalVideoIds);

  final MediaPrefetchBlockReason reason;
  final VideoItem? video;
  final Set<String> remainingLocalVideoIds;

  bool get shouldDownload =>
      reason == MediaPrefetchBlockReason.ready && video != null;
}

class MediaPrefetchPolicy {
  const MediaPrefetchPolicy(this.resolver);

  final MediaResourceResolver resolver;

  MediaPrefetchDecision nextVideoToDownload({
    required Iterable<VideoItem> playbackScope,
    required Set<String> playedVideoIds,
    Set<String> skippedVideoIds = const {},
    String? currentVideoId,
  }) {
    final videos = playbackScope.toList(growable: false);
    if (videos.isEmpty) {
      return const MediaPrefetchDecision.blocked(
        reason: MediaPrefetchBlockReason.emptyScope,
        remainingLocalVideoIds: {},
      );
    }

    final localVideoIds = <String>{};
    final remoteCandidates = <VideoItem>[];
    for (final video in videos) {
      final resource = resolver.videoResourceFor(video);
      if (!resource.isPlayable) continue;
      if (resource.isLocal) {
        localVideoIds.add(video.id);
      } else if (resource.status == MediaResourceStatus.remote &&
          !skippedVideoIds.contains(video.id) &&
          video.id != currentVideoId) {
        remoteCandidates.add(video);
      }
    }

    if (localVideoIds.isEmpty) {
      return const MediaPrefetchDecision.blocked(
        reason: MediaPrefetchBlockReason.noLocalCycle,
        remainingLocalVideoIds: {},
      );
    }

    final remainingLocalVideoIds = localVideoIds
        .where((id) => !playedVideoIds.contains(id))
        .toSet();
    if (remainingLocalVideoIds.isNotEmpty) {
      return MediaPrefetchDecision.blocked(
        reason: MediaPrefetchBlockReason.localCycleIncomplete,
        remainingLocalVideoIds: remainingLocalVideoIds,
      );
    }

    if (remoteCandidates.isEmpty) {
      return MediaPrefetchDecision.blocked(
        reason: MediaPrefetchBlockReason.noRemoteCandidates,
        remainingLocalVideoIds: remainingLocalVideoIds,
      );
    }

    return MediaPrefetchDecision.ready(
      video: remoteCandidates.first,
      remainingLocalVideoIds: remainingLocalVideoIds,
    );
  }
}
