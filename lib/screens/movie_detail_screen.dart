import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/firestore_service.dart';
import '../services/movie_service.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class MovieDetailScreen extends StatelessWidget {
  const MovieDetailScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final movie =
        ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
    final FirestoreService _firestoreService = FirestoreService();
    final MovieService _movieService = MovieService();
    final userId = FirebaseAuth.instance.currentUser?.uid;

    if (userId != null) {
      _firestoreService
          .saveInteraction(userId, movie)
          .then((_) {
            print('Interaction saved for movie: ${movie['title']}');
          })
          .catchError((error) {
            print('Failed to save interaction: $error');
          });
    } else {
      print('User not logged in, cannot save interaction.');
    }

    // Check if the movie's release date is in the future
    bool isUnreleased = false;
    final releaseDateStr = movie['release_date'] ?? '';
    if (releaseDateStr.isNotEmpty) {
      try {
        final releaseDate = DateTime.parse(releaseDateStr);
        final currentDate = DateTime(
          2025,
          5,
          2,
        ); // Current date as of May 02, 2025
        isUnreleased = releaseDate.isAfter(currentDate);
      } catch (e) {
        print('Error parsing release date: $e');
      }
    }

    return WillPopScope(
      onWillPop: () async {
        print('Navigating back to HomeScreen from MovieDetailScreen');
        Navigator.pushReplacementNamed(context, '/home');
        return false; // Prevent default back navigation
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: Text(movie['title'] ?? 'Movie Details'),
          backgroundColor: Colors.black,
          elevation: 2,
          shadowColor: Colors.white.withOpacity(0.1),
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 300,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child:
                        movie['poster_path'] != null &&
                                movie['poster_path'].isNotEmpty
                            ? Image.network(
                              'https://image.tmdb.org/t/p/w500${movie['poster_path']}',
                              fit: BoxFit.cover,
                              errorBuilder:
                                  (context, error, stackTrace) => const Icon(
                                    Icons.error,
                                    size: 100,
                                    color: Colors.white70,
                                  ),
                            )
                            : const Icon(
                              Icons.movie,
                              size: 100,
                              color: Colors.white70,
                            ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  movie['title'] ?? 'Unknown Title',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Release Date: ${movie['release_date'] ?? 'Unknown'}',
                  style: const TextStyle(fontSize: 16, color: Colors.white70),
                ),
                const SizedBox(height: 8),
                Text(
                  'Genres: ${(movie['genres'] as List<dynamic>?)?.join(', ') ?? 'Unknown'}',
                  style: const TextStyle(fontSize: 16, color: Colors.white70),
                ),
                const SizedBox(height: 8),
                Text(
                  'Cast: ${(movie['cast'] as List<dynamic>?)?.join(', ') ?? 'Unknown'}',
                  style: const TextStyle(fontSize: 16, color: Colors.white70),
                ),
                const SizedBox(height: 16),
                Text(
                  'Overview',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  movie['overview'] ?? 'No description available.',
                  style: const TextStyle(fontSize: 16, color: Colors.white70),
                ),
                const SizedBox(height: 24),
                Center(
                  child: ElevatedButton(
                    onPressed:
                        isUnreleased
                            ? () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Trailer not yet released for this movie.',
                                  ),
                                  backgroundColor: Colors.redAccent,
                                ),
                              );
                            }
                            : () async {
                              try {
                                print(
                                  'Fetching trailer for movie: ${movie['title']} (ID: ${movie['id']})',
                                );
                                String? movieId = movie['id']?.toString();
                                // Validate the movie ID
                                if (movieId == null ||
                                    !RegExp(r'^\d+$').hasMatch(movieId)) {
                                  print(
                                    'Invalid TMDB ID: $movieId, attempting to fetch TMDB ID for ${movie['title']}',
                                  );
                                  final tmdbMovie = await _movieService
                                      ._fetchTmdbMovieByTitle(movie['title']);
                                  if (tmdbMovie != null) {
                                    movieId = tmdbMovie['id'].toString();
                                    print('Fetched TMDB ID: $movieId');
                                  } else {
                                    throw Exception(
                                      'Could not find TMDB ID for movie: ${movie['title']}',
                                    );
                                  }
                                }
                                final trailerUrl = await _movieService
                                    .fetchMovieTrailer(movieId);
                                if (trailerUrl != null) {
                                  print(
                                    'Navigating to WatchMovieScreen with trailer URL: $trailerUrl',
                                  );
                                  Navigator.pushNamed(
                                    context,
                                    '/watch_movie',
                                    arguments: {
                                      'movie': movie,
                                      'trailerUrl': trailerUrl,
                                    },
                                  );
                                } else {
                                  print(
                                    'No trailer URL returned for movie: ${movie['title']}',
                                  );
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'No trailer available for this movie.',
                                      ),
                                      backgroundColor: Colors.redAccent,
                                    ),
                                  );
                                }
                              } catch (e) {
                                print(
                                  'Error fetching trailer for movie ${movie['title']}: $e',
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Error fetching trailer: $e'),
                                    backgroundColor: Colors.redAccent,
                                  ),
                                );
                              }
                            },
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          isUnreleased ? Colors.grey : Colors.deepPurple,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 40,
                        vertical: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Watch Trailer',
                      style: TextStyle(fontSize: 18, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Add this extension to access private method for this file only
extension on MovieService {
  Future<Map<String, dynamic>?> _fetchTmdbMovieByTitle(String title) async {
    try {
      final response = await http.get(
        Uri.parse(
          'https://api.themoviedb.org/3/search/movie?api_key=caa52eead5146df17afc06cfce2168b9&query=${Uri.encodeComponent(title)}',
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
}
