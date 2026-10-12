
class Movie {
  final String id;
  final String title;
  final String? description;
  final String? posterUrl;
  final String? genre;
  final int? releaseYear;
  final int freeEpisodes;
  final int? price;

  Movie({
    required this.id,
    required this.title,
    this.description,
    this.posterUrl,
    this.genre,
    this.releaseYear,
    required this.freeEpisodes,
    this.price,
  });

  factory Movie.fromJson(Map<String, dynamic> j) => Movie(
        id: j['id'] as String,
        title: j['title'] as String,
        description: j['description'] as String?,
        posterUrl: j['poster_url'] as String?,
        genre: j['genre'] as String?,
        releaseYear: j['release_year'] as int?,
        freeEpisodes: (j['free_episodes'] as int?) ?? 3,
        price: j['price'] as int?,
      );
}

class Episode {
  final String id;
  final String movieId;
  final int number;
  final String? title;
  final int? durationSeconds;
  final String? thumbnailUrl;

  Episode({
    required this.id,
    required this.movieId,
    required this.number,
    this.title,
    this.durationSeconds,
    this.thumbnailUrl,
  });

  factory Episode.fromJson(Map<String, dynamic> j) => Episode(
        id: j['id'] as String,
        movieId: j['movie_id'] as String,
        number: j['episode_number'] as int,
        title: j['title'] as String?,
        durationSeconds: j['duration_seconds'] as int?,
        thumbnailUrl: j['thumbnail_url'] as String?,
      );

  String get label => title == null || title!.isEmpty
      ? 'Episode $number'
      : 'Episode $number · $title';
}

class Plan {
  final String id;
  final String name;
  final int price;
  final String currency;
  final int durationDays;

  Plan({
    required this.id,
    required this.name,
    required this.price,
    required this.currency,
    required this.durationDays,
  });

  factory Plan.fromJson(Map<String, dynamic> j) => Plan(
        id: j['id'] as String,
        name: j['name'] as String,
        price: j['price'] as int,
        currency: j['currency'] as String,
        durationDays: j['duration_days'] as int,
      );
}