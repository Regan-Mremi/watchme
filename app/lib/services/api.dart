
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models.dart';

/// Thrown when the server requires the user to purchase a movie.
class SubscriptionRequired implements Exception {
  @override
  String toString() => 'Movie purchase required';
}

class Api {
  static SupabaseClient get _db => Supabase.instance.client;

  // -------------------------------------------------------------
  // Catalog
  // -------------------------------------------------------------

  static Future<List<Movie>> movies() async {
    final rows = await _db
        .from('movies')
        .select()
        .order('created_at', ascending: false);

    return rows.map<Movie>(Movie.fromJson).toList();
  }

  static Future<List<Episode>> episodes(String movieId) async {
    final rows = await _db
        .from('episodes')
        .select()
        .eq('movie_id', movieId)
        .order('episode_number');

    return rows.map<Episode>(Episode.fromJson).toList();
  }

  // -------------------------------------------------------------
  // Individual movie purchases
  // -------------------------------------------------------------

  /// Checks whether the signed-in user purchased this movie.
  static Future<bool> hasPurchasedMovie(String movieId) async {
    final uid = _db.auth.currentUser?.id;

    if (uid == null) {
      return false;
    }

    final purchase = await _db
        .from('movie_purchases')
        .select('id')
        .eq('user_id', uid)
        .eq('movie_id', movieId)
        .maybeSingle();

    return purchase != null;
  }

  /// Starts mobile-money checkout for one movie.
  /// The server determines the movie price.
  static Future<void> startMovieCheckout(
    String movieId, {
    required String phone,
  }) async {
    final res = await _db.functions.invoke(
      'create-payment',
      body: {
        'movie_id': movieId,
        'phone': phone,
      },
    );

    final data = res.data;

    if (data is Map && data['error'] != null) {
      throw Exception(
        data['message']?.toString() ??
            data['error'].toString(),
      );
    }

    if (res.status < 200 || res.status >= 300) {
      throw Exception('Payment request failed.');
    }
  }

  // -------------------------------------------------------------
  // Playback
  // -------------------------------------------------------------

  /// The server checks free episodes and movie purchases
  /// before returning a signed video URL.
  static Future<String> playbackUrl(String episodeId) async {
    try {
      final res = await _db.functions.invoke(
        'get-playback',
        body: {
          'episode_id': episodeId,
        },
      );

      final data = res.data;

      if (data is! Map || data['url'] is! String) {
        throw Exception(
          'The video service did not return a playback URL.',
        );
      }

      return data['url'] as String;
    } on FunctionException catch (e) {
      if (e.status == 402) {
        throw SubscriptionRequired();
      }

      rethrow;
    }
  }

  // -------------------------------------------------------------
  // Watch progress
  // -------------------------------------------------------------

  static Future<int> savedPosition(String episodeId) async {
    final uid = _db.auth.currentUser?.id;

    if (uid == null) {
      throw Exception('Please sign in to continue.');
    }

    final row = await _db
        .from('watch_progress')
        .select('position_seconds')
        .eq('user_id', uid)
        .eq('episode_id', episodeId)
        .maybeSingle();

    return (row?['position_seconds'] as int?) ?? 0;
  }

  static Future<void> savePosition(
    String episodeId,
    int seconds,
  ) async {
    final uid = _db.auth.currentUser?.id;

    if (uid == null) {
      throw Exception('Please sign in to save your progress.');
    }

    await _db.from('watch_progress').upsert({
      'user_id': uid,
      'episode_id': episodeId,
      'position_seconds': seconds,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  // -------------------------------------------------------------
  // Authentication
  // -------------------------------------------------------------

  static Future<void> signIn(
    String email,
    String password,
  ) async {
    await _db.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  static Future<void> signUp(
    String email,
    String password,
    String name,
  ) async {
    await _db.auth.signUp(
      email: email,
      password: password,
      data: {
        'full_name': name,
      },
    );
  }

  static Future<void> signOut() async {
    await _db.auth.signOut();
  }
}