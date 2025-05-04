import 'package:http/http.dart' as http;
import 'dart:convert';
import '../services/firestore_service.dart';
import 'dart:math';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

class MovieService {
  final FirestoreService _firestoreService = FirestoreService();
  final String _baseUrl = 'http://10.0.2.2:5000';
  final String _tmdbApiKey = 'caa52eead5146df17afc06cfce2168b9';

  Future<List<Map<String, dynamic>>> fetchRecommendedMovies(
    String userId, {
    int limit = 10,
    required List<String> genres,
    required List<String> cast,
  }) async {
    try {
      List<Map<String, dynamic>> watchHistory = await _firestoreService
          .getWatchHistory(userId);
      List<Map<String, dynamic>> interactions = await _firestoreService
          .getInteractions(userId);
      List<Map<String, dynamic>> history = [];

      if (watchHistory.isNotEmpty) {
        watchHistory.sort(
          (a, b) => (b['watch_time'] ?? 0).compareTo(a['watch_time'] ?? 0),
        );
        Map<String, dynamic> mostWatched = watchHistory.first;
        history.add({
          'genres':
              (mostWatched['genres'] as List<dynamic>?)?.cast<String>() ?? [],
          'cast': (mostWatched['cast'] as List<dynamic>?)?.cast<String>() ?? [],
          'watch_time': mostWatched['watch_time'] ?? 0,
          'title': mostWatched['title'] ?? 'Unknown',
        });
        print(
          'Using watch history for recommendations: ${mostWatched['title']} (Watch time: ${mostWatched['watch_time']} seconds)',
        );
      } else if (interactions.isNotEmpty) {
        interactions.sort((a, b) {
          final aTimestamp = a['timestamp']?.toDate() ?? DateTime(1970);
          final bTimestamp = b['timestamp']?.toDate() ?? DateTime(1970);
          return bTimestamp.compareTo(aTimestamp);
        });
        Map<String, dynamic> lastInteracted = interactions.first;
        history.add({
          'genres':
              (lastInteracted['genres'] as List<dynamic>?)?.cast<String>() ??
              [],
          'cast':
              (lastInteracted['cast'] as List<dynamic>?)?.cast<String>() ?? [],
          'timestamp':
              lastInteracted['timestamp']?.toDate()?.millisecondsSinceEpoch ??
              0,
          'title': lastInteracted['title'] ?? 'Unknown',
        });
        print(
          'Using interactions for recommendations: ${lastInteracted['title']}',
        );
      } else {
        print(
          'No watch history or interactions found for user: $userId. Requesting random movies from backend.',
        );
      }

      if (history.isNotEmpty &&
          history.first['genres'].isEmpty &&
          history.first['cast'].isEmpty) {
        print(
          'No valid genres or cast in user history, requesting random movies.',
        );
        history.clear();
      }

      final response = await http.post(
        Uri.parse('$_baseUrl/recommend'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'history': history, 'limit': limit}),
      );

      if (response.statusCode == 200) {
        List<dynamic> recommendations = jsonDecode(response.body);
        print(
          'Fetched ${recommendations.length} recommendations from backend.',
        );
        List<Map<String, dynamic>> movies =
            recommendations.cast<Map<String, dynamic>>();
        for (var movie in movies) {
          if (movie['tmdb_id'] != null) {
            movie['id'] = movie['tmdb_id'];
          } else {
            print(
              'Warning: Movie ${movie['title']} has no tmdb_id, attempting to fetch TMDB ID',
            );
            final tmdbMovie = await _fetchTmdbMovieByTitle(movie['title']);
            if (tmdbMovie != null) {
              movie['id'] = tmdbMovie['id'];
              movie['tmdb_id'] = tmdbMovie['id'];
            } else {
              print('Could not find TMDB ID for movie: ${movie['title']}');
              movie['id'] = null;
            }
          }
          movie['poster_path'] = movie['poster_path'] ?? '';
          movie['release_date'] = movie['release_date'] ?? '';
          movie['genres'] = movie['genres'] ?? [];
          movie['cast'] = movie['cast'] ?? [];
          movie['overview'] = movie['overview'] ?? '';
        }
        movies = movies.where((movie) => movie['id'] != null).toList();
        print('Processed recommended movies: $movies');
        return movies;
      } else {
        throw Exception(
          'Failed to fetch recommendations: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      print('Error in fetchRecommendedMovies: $e');
      throw Exception('Error fetching recommendations: $e');
    }
  }

  Future<Map<String, dynamic>?> _fetchTmdbMovieByTitle(String title) async {
    try {
      final response = await http.get(
        Uri.parse(
          'https://api.themoviedb.org/3/search/movie?api_key=$_tmdbApiKey&query=${Uri.encodeComponent(title)}',
        ),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final results = data['results'] as List<dynamic>;
        if (results.isNotEmpty) {
          return results[0] as Map<String, dynamic>;
        }
      }
    } catch (e) {
      print('Error fetching TMDB movie by title ($title): $e');
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> fetchTmdbMovies({
    int limit = 100,
    bool forRecommendations = false,
  }) async {
    try {
      List<Map<String, dynamic>> movies = [];
      int pages = forRecommendations ? 10 : (limit / 20).ceil();
      int startPage = forRecommendations ? Random().nextInt(50) + 1 : 1;
      for (
        int page = startPage;
        page < startPage + pages && movies.length < limit;
        page++
      ) {
        final response = await http.get(
          Uri.parse(
            forRecommendations
                ? 'https://api.themoviedb.org/3/discover/movie?api_key=$_tmdbApiKey&page=$page'
                : 'https://api.themoviedb.org/3/discover/movie?api_key=$_tmdbApiKey&sort_by=popularity.desc&page=$page',
          ),
        );

        if (response.statusCode != 200) {
          throw Exception(
            'Failed to fetch TMDB movies: ${response.statusCode}',
          );
        }

        final data = jsonDecode(response.body);
        final List<dynamic> results = data['results'] ?? [];

        for (var movie in results) {
          if (movies.length >= limit) break;

          final movieId = movie['id'];
          final detailsResponse = await http.get(
            Uri.parse(
              'https://api.themoviedb.org/3/movie/$movieId?api_key=$_tmdbApiKey&append_to_response=credits',
            ),
          );

          if (detailsResponse.statusCode != 200) continue;

          final details = jsonDecode(detailsResponse.body);
          final genres =
              (details['genres'] as List<dynamic>?)
                  ?.map((g) => g['name'] as String)
                  .toList() ??
              [];
          final cast =
              (details['credits']?['cast'] as List<dynamic>?)
                  ?.take(5)
                  .map((c) => c['name'] as String)
                  .toList() ??
              [];

          movies.add({
            'id': movie['id'],
            'title': movie['title'] ?? 'Unknown Title',
            'poster_path': movie['poster_path'],
            'genres': genres,
            'cast': cast,
            'release_date': movie['release_date']?.substring(0, 4) ?? 'Unknown',
            'overview': movie['overview'] ?? 'No description available',
          });
        }
      }

      print(
        'Fetched ${movies.length} movies from TMDB (forRecommendations: $forRecommendations).',
      );
      return movies;
    } catch (e) {
      print('Error in fetchTmdbMovies: $e');
      throw Exception('Error fetching TMDB movies: $e');
    }
  }

  Future<String?> fetchMovieTrailer(String movieId) async {
    try {
      final response = await http.get(
        Uri.parse(
          'https://api.themoviedb.org/3/movie/$movieId/videos?api_key=$_tmdbApiKey',
        ),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('TMDB API response for movie $movieId: $data');
        final videos = data['results'] as List<dynamic>;
        print('Available videos for movie $movieId: $videos');
        final youtubeVideo = videos.firstWhere(
          (video) =>
              video['site'] == 'YouTube' &&
              (video['type'] == 'Trailer' || video['type'] == 'Teaser'),
          orElse: () => null,
        );
        if (youtubeVideo != null) {
          final videoKey = youtubeVideo['key'];
          final trailerUrl = 'https://www.youtube.com/watch?v=$videoKey';
          print(
            'Found YouTube video for movie $movieId (type: ${youtubeVideo['type']}): $trailerUrl',
          );
          return trailerUrl;
        } else {
          print('No YouTube Trailer or Teaser found for movie $movieId');
        }
      } else {
        print(
          'Failed to fetch trailer for movie $movieId, status code: ${response.statusCode}, body: ${response.body}',
        );
      }
    } catch (e) {
      print('Error fetching trailer for movie $movieId: $e');
    }
    return null;
  }
}
