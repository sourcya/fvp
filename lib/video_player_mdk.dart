import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'src/global.dart' as mdk;
import 'src/player.dart' as mdk;
import 'fvp_platform_interface.dart';

class MdkVideoPlayer extends VideoPlayerPlatform {

  static final _players = <int, mdk.Player>{};
  static final _streamCtl = <int, StreamController<VideoEvent>>{};

  /// Registers this class as the default instance of [VideoPlayerPlatform].
  static void registerWith() {
    VideoPlayerPlatform.instance = MdkVideoPlayer();
  }

  @override
  Future<void> init() async{
  }

  @override
  Future<void> dispose(int textureId) async {
    final p = _players[textureId];
    if (p == null)
      return;
    // await: ensure player deleted when no use in fvp plugin
    await FvpPlatform.instance.releaseTexture(p.nativeHandle, textureId);
    _players.remove(textureId);
    p.dispose();
    _streamCtl.remove(textureId);
  }

  @override
  Future<int?> create(DataSource dataSource) async {
    String? asset;
    String? packageName;
    String? uri;
    String? formatHint;
    Map<String, String> httpHeaders = <String, String>{};
    switch (dataSource.sourceType) {
      case DataSourceType.asset:
        asset = dataSource.asset;
        packageName = dataSource.package;
        break;
      case DataSourceType.network:
        uri = dataSource.uri;
        //formatHint = _videoFormatStringMap[dataSource.formatHint];
        httpHeaders = dataSource.httpHeaders;
        break;
      case DataSourceType.file:
        uri = dataSource.uri;
        break;
      case DataSourceType.contentUri:
        uri = dataSource.uri;
        break;
    }
    final player = mdk.Player();

    // TODO: how to set decoders by user?
    switch (Platform.operatingSystem) {
    case 'windows':
        player.videoDecoders = ['MFT:d3d=11', 'CUDA', 'FFmpeg'];
    case 'macos':
        player.videoDecoders = ['VT', 'FFmpeg'];
    case 'ios':
        player.videoDecoders = ['VT', 'FFmpeg'];
    case 'linux':
        player.videoDecoders = ['VAAPI', 'CUDA', 'VDPAU', 'FFmpeg'];
    case 'android':
        player.videoDecoders = ['AMediaCodec', 'FFmpeg'];
    }

    final tex = await FvpPlatform.instance.createTexture(player.nativeHandle);
    _players[tex] = player;
    _streamCtl[tex] = _initEvents(player);
    player.media = uri!;
    player.prepare(); // required!
    return tex;
  }

  @override
  Future<void> setLooping(int textureId, bool looping) async {
    final player = _players[textureId];
    if (player != null) {
      player.loop = looping ? -1 : 0;
    }
  }

  @override
  Future<void> play(int textureId) async {
    final player = _players[textureId];
    if (player != null) {
      player.state = mdk.State.playing;
    }
  }

  @override
  Future<void> pause(int textureId) async {
    final player = _players[textureId];
    if (player != null) {
      player.state = mdk.State.paused;
    }
  }

  @override
  Future<void> setVolume(int textureId, double volume) async {
    final player = _players[textureId];
    if (player != null) {
      player.volume = volume;
    }
  }

  @override
  Future<void> setPlaybackSpeed(int textureId, double speed) async {
    final player = _players[textureId];
    if (player != null) {
      player.playbackRate = speed;
    }
  }

  @override
  Future<void> seekTo(int textureId, Duration position) async {
    final player = _players[textureId];
    if (player != null) {
      player.seek(position: position.inMilliseconds, flags: const mdk.SeekFlag(mdk.SeekFlag.fromStart|mdk.SeekFlag.keyFrame|mdk.SeekFlag.inCache));
    }
  }

  @override
  Future<Duration> getPosition(int textureId) async {
    final player = _players[textureId];
    if (player != null) {
      return Duration(milliseconds: player.position);
    }
    return Duration.zero;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int textureId) {
    var sc = _streamCtl[textureId];
    if (sc != null) {
      return sc.stream;
    }
    throw Exception('No Stream<VideoEvent> for textureId: $textureId.');
  }

  @override
  Widget buildView(int textureId) {
    return Texture(textureId: textureId);
  }

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {
  }

  StreamController<VideoEvent> _initEvents(mdk.Player player) {
    final sc = StreamController<VideoEvent>();
    player.onMediaStatusChanged((oldValue, newValue) {
      print('$hashCode player${player.nativeHandle} onMediaStatusChanged: $oldValue => $newValue');
      if (!oldValue.test(mdk.MediaStatus.loaded) && newValue.test(mdk.MediaStatus.loaded)) {
        final info = player.mediaInfo;
        var size = const Size(0, 0);
        if (info.video != null) {
          final vc = info.video![0].codec;
          size = Size(vc.width.toDouble(), vc.height.toDouble());
        }
        sc.add(VideoEvent(eventType: VideoEventType.initialized
          , duration: Duration(milliseconds: info.duration == 0 ? double.maxFinite.toInt() : info.duration) // FIXME: live stream info.duraiton == 0 and result a seekTo(0) in play()
          , size: size));
      } else if (!oldValue.test(mdk.MediaStatus.buffering) && newValue.test(mdk.MediaStatus.buffering)) {
        sc.add(VideoEvent(eventType: VideoEventType.bufferingStart));
      } else if (!oldValue.test(mdk.MediaStatus.buffered) && newValue.test(mdk.MediaStatus.buffered)) {
        sc.add(VideoEvent(eventType: VideoEventType.bufferingEnd));
      }
      return true;
    });
    // TODO: VideoEventType.bufferingUpdate via MediaEvent callback

    player.onStateChanged((oldValue, newValue) {
      print('$hashCode player${player.nativeHandle} onStateChanged: $oldValue => $newValue');
      sc.add(VideoEvent(eventType: VideoEventType.isPlayingStateUpdate
        , isPlaying: newValue == mdk.State.playing));
    });
    return sc;
  }
}