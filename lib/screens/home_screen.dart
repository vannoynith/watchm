import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/movie_service.dart';

class HomeScreen extends StatefulWidget {
  final bool flaskServerFailed;

  const HomeScreen({Key? key, required this.flaskServerFailed})
    : super(key: key);

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final MovieService _movieService = MovieService();
  List<Map<String, dynamic>> _recommendedMovies = [];
  List<Map<String, dynamic>> _allMovies = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchMovies();
  }

  Future<void> _fetchMovies() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId != null && !widget.flaskServerFailed) {
        _recommendedMovies = await _movieService.fetchRecommendedMovies(
          userId,
          genres: [], // Populated by watch history or interactions
          cast: [],
        );
        print('Fetched recommended movies: $_recommendedMovies');
      } else if (widget.flaskServerFailed) {
        print('Skipping recommendations due to Flask server failure.');
        _recommendedMovies = [];
      } else {
        print('User not logged in, skipping recommended movies.');
        _recommendedMovies = [];
      }
      _allMovies = await _movieService.fetchTmdbMovies();
      print('Fetched all movies: $_allMovies');
    } catch (e) {
      print('Error fetching movies: $e');
      setState(() {
        _errorMessage = 'Error fetching movies: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Home'),
        backgroundColor: Colors.black,
        elevation: 2,
        shadowColor: Colors.white.withOpacity(0.1),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () async {
              try {
                await FirebaseAuth.instance.signOut();
                print('User signed out, navigating to LoginScreen');
                Navigator.pushReplacementNamed(context, '/login');
              } catch (e) {
                print('Error signing out: $e');
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Error signing out: $e'),
                    backgroundColor: Colors.redAccent,
                  ),
                );
              }
            },
          ),
        ],
      ),
      body:
          _isLoading
              ? const Center(
                child: CircularProgressIndicator(color: Colors.deepPurple),
              )
              : _errorMessage != null
              ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _errorMessage!,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.redAccent,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _fetchMovies,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 40,
                          vertical: 16,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Retry',
                        style: TextStyle(fontSize: 18, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              )
              : RefreshIndicator(
                onRefresh: _fetchMovies,
                color: Colors.deepPurple,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Recommended for You',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 16),
                        widget.flaskServerFailed
                            ? const Center(
                              child: Text(
                                'Recommendations unavailable: Flask server not running.',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.white70,
                                ),
                              ),
                            )
                            : _recommendedMovies.isEmpty
                            ? const Center(
                              child: Text(
                                'No recommendations available.',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.white70,
                                ),
                              ),
                            )
                            : SizedBox(
                              height: 200,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                itemCount: _recommendedMovies.length,
                                itemBuilder: (context, index) {
                                  final movie = _recommendedMovies[index];
                                  return GestureDetector(
                                    onTap: () {
                                      if (movie['id'] == null) {
                                        print(
                                          'Invalid TMDB ID for recommended movie: ${movie['title']}, skipping navigation',
                                        );
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Cannot load movie details: Missing TMDB ID.',
                                            ),
                                            backgroundColor: Colors.redAccent,
                                          ),
                                        );
                                        return;
                                      }
                                      print(
                                        'Navigating to MovieDetailScreen for recommended movie: ${movie['title']} (ID: ${movie['id']})',
                                      );
                                      Navigator.pushNamed(
                                        context,
                                        '/movie_detail',
                                        arguments: movie,
                                      );
                                    },
                                    child: Container(
                                      width: 120,
                                      margin: const EdgeInsets.only(right: 16),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              child:
                                                  movie['poster_path'] !=
                                                              null &&
                                                          movie['poster_path']
                                                              .isNotEmpty
                                                      ? Image.network(
                                                        'https://image.tmdb.org/t/p/w200${movie['poster_path']}',
                                                        fit: BoxFit.cover,
                                                        errorBuilder:
                                                            (
                                                              context,
                                                              error,
                                                              stackTrace,
                                                            ) => const Icon(
                                                              Icons.error,
                                                              size: 50,
                                                              color:
                                                                  Colors
                                                                      .white70,
                                                            ),
                                                      )
                                                      : const Icon(
                                                        Icons.movie,
                                                        size: 50,
                                                        color: Colors.white70,
                                                      ),
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            movie['title'] ?? 'Unknown Title',
                                            style: const TextStyle(
                                              fontSize: 14,
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                        const SizedBox(height: 24),
                        const Text(
                          'All Movies',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _allMovies.isEmpty
                            ? const Center(
                              child: Text(
                                'No movies available.',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.white70,
                                ),
                              ),
                            )
                            : GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 2,
                                    childAspectRatio: 0.7,
                                    crossAxisSpacing: 16,
                                    mainAxisSpacing: 16,
                                  ),
                              itemCount: _allMovies.length,
                              itemBuilder: (context, index) {
                                final movie = _allMovies[index];
                                return GestureDetector(
                                  onTap: () {
                                    if (movie['id'] == null) {
                                      print(
                                        'Invalid TMDB ID for TMDB movie: ${movie['title']}, skipping navigation',
                                      );
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Cannot load movie details: Missing TMDB ID.',
                                          ),
                                          backgroundColor: Colors.redAccent,
                                        ),
                                      );
                                      return;
                                    }
                                    print(
                                      'Navigating to MovieDetailScreen for TMDB movie: ${movie['title']} (ID: ${movie['id']})',
                                    );
                                    Navigator.pushNamed(
                                      context,
                                      '/movie_detail',
                                      arguments: movie,
                                    );
                                  },
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          child:
                                              movie['poster_path'] != null
                                                  ? Image.network(
                                                    'https://image.tmdb.org/t/p/w200${movie['poster_path']}',
                                                    fit: BoxFit.cover,
                                                    errorBuilder:
                                                        (
                                                          context,
                                                          error,
                                                          stackTrace,
                                                        ) => const Icon(
                                                          Icons.error,
                                                          size: 50,
                                                          color: Colors.white70,
                                                        ),
                                                  )
                                                  : const Icon(
                                                    Icons.movie,
                                                    size: 50,
                                                    color: Colors.white70,
                                                  ),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        movie['title'] ?? 'Unknown Title',
                                        style: const TextStyle(
                                          fontSize: 14,
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                      ],
                    ),
                  ),
                ),
              ),
    );
  }
}
