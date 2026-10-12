
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../models.dart';
import '../services/api.dart';
import 'paywall_screen.dart';
import 'player_screen.dart';

class MovieScreen extends StatefulWidget {
  final Movie movie;

  const MovieScreen({
    super.key,
    required this.movie,
  });

  @override
  State<MovieScreen> createState() => _MovieScreenState();
}

class _MovieScreenState extends State<MovieScreen> {
  late Future<List<Episode>> _episodes;

  bool _purchased = false;
  bool _checkingPurchase = true;

  static const Color _background = Color(0xFF080B14);
  static const Color _surface = Color(0xFF151A29);
  static const Color _purple = Color(0xFF8054FF);

  @override
  void initState() {
    super.initState();
    _episodes = Api.episodes(widget.movie.id);
    _checkPurchase();
  }

  Future<void> _checkPurchase() async {
    try {
      final purchased =
          await Api.hasPurchasedMovie(widget.movie.id);

      if (!mounted) return;

      setState(() {
        _purchased = purchased;
        _checkingPurchase = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _checkingPurchase = false;
      });
    }
  }

  bool _isLocked(Episode episode) {
    return episode.number > widget.movie.freeEpisodes &&
        !_purchased;
  }

  Future<void> _open(Episode episode) async {
    if (_checkingPurchase) return;

    if (_isLocked(episode)) {
      final purchased = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => PaywallScreen(movie: widget.movie),
        ),
      );

      if (!mounted) return;

      if (purchased == true) {
        await _checkPurchase();
      }

      return;
    }

    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerScreen(episode: episode),
      ),
    );

    if (mounted) {
      await _checkPurchase();
    }
  }

  Future<void> _refreshEpisodes() async {
    setState(() {
      _episodes = Api.episodes(widget.movie.id);
    });

    try {
      await _episodes;
    } catch (_) {
      // The error is displayed below.
    }

    await _checkPurchase();
  }

  String _formatDuration(int seconds) {
    final duration = Duration(seconds: seconds);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final secs = duration.inSeconds.remainder(60);

    if (hours > 0) return '${hours}h ${minutes}m';
    if (minutes > 0 && secs > 0) return '${minutes}m ${secs}s';
    if (minutes > 0) return '$minutes min';
    return '${secs}s';
  }

  @override
  Widget build(BuildContext context) {
    final movie = widget.movie;

    final details = <String>[
      if (movie.genre != null && movie.genre!.isNotEmpty)
        movie.genre!,
      if (movie.releaseYear != null)
        '${movie.releaseYear}',
    ];

    return Scaffold(
      backgroundColor: _background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 390,
            pinned: true,
            backgroundColor: _background,
            foregroundColor: Colors.white,
            elevation: 0,
            title: const Text(
              'Movie details',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  if (movie.posterUrl != null &&
                      movie.posterUrl!.trim().isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: movie.posterUrl!,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        color: _surface,
                      ),
                      errorWidget: (_, __, ___) =>
                          _posterPlaceholder(),
                    )
                  else
                    _posterPlaceholder(),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withOpacity(0.30),
                          Colors.transparent,
                          _background.withOpacity(0.70),
                          _background,
                        ],
                        stops: const [0.0, 0.35, 0.72, 1.0],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: 24,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (details.isNotEmpty)
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: details.map((detail) {
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.13),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: Colors.white24,
                                  ),
                                ),
                                child: Text(
                                  detail,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        const SizedBox(height: 12),
                        Text(
                          movie.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _purchaseStatus(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (movie.description != null &&
                      movie.description!.trim().isNotEmpty) ...[
                    const Text(
                      'About this movie',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      movie.description!,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        height: 1.65,
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Episodes',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _surface,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${movie.freeEpisodes} free',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (!_purchased &&
                      movie.price != null &&
                      movie.price! > 0)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFF35216C),
                            Color(0xFF211A3C),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _purple.withOpacity(0.45),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.workspace_premium,
                            color: Color(0xFFD5BEFF),
                            size: 28,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Unlock the full movie',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'TZS ${movie.price}',
                                  style: const TextStyle(
                                    color: Color(0xFFD5BEFF),
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.arrow_forward_ios,
                            color: Colors.white70,
                            size: 16,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          FutureBuilder<List<Episode>>(
            future: _episodes,
            builder: (context, snapshot) {
              if (snapshot.connectionState ==
                  ConnectionState.waiting) {
                return const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: CircularProgressIndicator(
                      color: _purple,
                    ),
                  ),
                );
              }

              if (snapshot.hasError) {
                return SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.cloud_off,
                            color: Colors.white54,
                            size: 42,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Could not load episodes',
                            style: TextStyle(color: Colors.white),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: _refreshEpisodes,
                            child: const Text('Try again'),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }

              final episodes = snapshot.data ?? <Episode>[];

              if (episodes.isEmpty) {
                return const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Text(
                      'No episodes available yet.',
                      style: TextStyle(color: Colors.white60),
                    ),
                  ),
                );
              }

              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final episode = episodes[index];
                      final locked = _isLocked(episode);

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Material(
                          color: _surface,
                          borderRadius: BorderRadius.circular(16),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: _checkingPurchase
                                ? null
                                : () => _open(episode),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  ClipRRect(
                                    borderRadius:
                                        BorderRadius.circular(12),
                                    child: SizedBox(
                                      width: 76,
                                      height: 76,
                                      child: episode.thumbnailUrl != null &&
                                              episode.thumbnailUrl!
                                                  .trim()
                                                  .isNotEmpty
                                          ? CachedNetworkImage(
                                              imageUrl:
                                                  episode.thumbnailUrl!,
                                              fit: BoxFit.cover,
                                              errorWidget: (_, __, ___) =>
                                                  _episodePlaceholder(),
                                              placeholder: (_, __) =>
                                                  _episodePlaceholder(),
                                            )
                                          : _episodePlaceholder(),
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'EPISODE ${episode.number}',
                                          style: const TextStyle(
                                            color: Color(0xFFB7A0FF),
                                            fontSize: 10,
                                            letterSpacing: 1.2,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 5),
                                        Text(
                                          episode.label,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        if (episode.durationSeconds !=
                                                null &&
                                            episode.durationSeconds! > 0) ...[
                                          const SizedBox(height: 5),
                                          Text(
                                            _formatDuration(
                                              episode.durationSeconds!,
                                            ),
                                            style: const TextStyle(
                                              color: Colors.white54,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: locked
                                          ? Colors.white.withOpacity(0.07)
                                          : _purple.withOpacity(0.18),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      locked
                                          ? Icons.lock_outline
                                          : Icons.play_arrow_rounded,
                                      color: locked
                                          ? Colors.white70
                                          : const Color(0xFFD5BEFF),
                                      size: 23,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                    childCount: episodes.length,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _purchaseStatus() {
    if (_checkingPurchase) {
      return const Row(
        children: [
          SizedBox(
            width: 15,
            height: 15,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          ),
          SizedBox(width: 9),
          Text(
            'Checking purchase...',
            style: TextStyle(color: Colors.white70),
          ),
        ],
      );
    }

    final unlocked = _purchased;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: unlocked
            ? Colors.green.withOpacity(0.17)
            : _purple.withOpacity(0.18),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: unlocked
              ? Colors.green.withOpacity(0.5)
              : _purple.withOpacity(0.5),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            unlocked ? Icons.verified : Icons.play_circle_outline,
            color: unlocked ? Colors.greenAccent : const Color(0xFFD5BEFF),
            size: 17,
          ),
          const SizedBox(width: 7),
          Text(
            unlocked
                ? 'All episodes unlocked'
                : '${widget.movie.freeEpisodes} free episodes',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _posterPlaceholder() {
    return Container(
      color: _surface,
      child: const Center(
        child: Icon(
          Icons.movie_outlined,
          color: Colors.white38,
          size: 70,
        ),
      ),
    );
  }

  Widget _episodePlaceholder() {
    return Container(
      color: const Color(0xFF22283A),
      child: const Center(
        child: Icon(
          Icons.movie_outlined,
          color: Colors.white54,
          size: 30,
        ),
      ),
    );
  }
}