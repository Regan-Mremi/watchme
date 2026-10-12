
import 'dart:async';

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models.dart';
import '../services/api.dart';

class PlayerScreen extends StatefulWidget {
  final Episode episode;

  const PlayerScreen({
    super.key,
    required this.episode,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  VideoPlayerController? _video;
  ChewieController? _chewie;
  Timer? _progressTimer;
  String? _error;
  bool _redirecting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final url = await Api.playbackUrl(widget.episode.id);
      final start = await Api.savedPosition(widget.episode.id);

      final video = VideoPlayerController.networkUrl(
        Uri.parse(url),
      );

      await video.initialize();

      if (start > 5) {
        await video.seekTo(Duration(seconds: start));
      }

      final chewie = ChewieController(
        videoPlayerController: video,
        autoPlay: true,
        allowFullScreen: true,
        allowMuting: true,
      );

      if (!mounted) {
        video.dispose();
        chewie.dispose();
        return;
      }

      setState(() {
        _video = video;
        _chewie = chewie;
      });

      _progressTimer = Timer.periodic(
        const Duration(seconds: 15),
        (_) => _saveProgress(),
      );
    } on SubscriptionRequired {
      if (!mounted || _redirecting) return;

      _redirecting = true;

      // Return to MovieScreen, which knows the correct movie
      // and can open its purchase screen.
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not play this episode.\n$e';
        });
      }
    }
  }

  void _saveProgress() {
    final video = _video;

    if (video == null || !video.value.isInitialized) {
      return;
    }

    Api.savePosition(
      widget.episode.id,
      video.value.position.inSeconds,
    ).catchError((_) {});
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _saveProgress();
    _chewie?.dispose();
    _video?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.episode.label),
      ),
      backgroundColor: Colors.black,
      body: Center(
        child: _error != null
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                ),
              )
            : _chewie == null
                ? const CircularProgressIndicator()
                : AspectRatio(
                    aspectRatio: _video!.value.aspectRatio,
                    child: Chewie(controller: _chewie!),
                  ),
      ),
    );
  }
}