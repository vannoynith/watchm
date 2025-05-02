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
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _fetchMovies();
  }

  Future<void> _fetchMovies() async {
    if (_isRefreshing || !mounted) return;
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
        _isRefreshing = true;
      });
    }
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId != null && !widget.flaskServerFailed) {
        _recommendedMovies = await _movieService.fetchRecommendedMovies(
          userId,
          genres: [],
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
      if (mounted) {
        setState(() {
          _errorMessage = 'Error fetching movies: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text(
          'WatchM',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
            fontSize: 22,
            letterSpacing: 1.2,
          ),
        ),
        elevation: 6,
        shadowColor: Colors.white.withOpacity(0.2),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _fetchMovies,
            tooltip: 'Refresh Movies',
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () async {
              try {
                await FirebaseAuth.instance.signOut();
                print('User signed out, navigating to LoginScreen');
                Navigator.pushReplacementNamed(context, '/login');
              } catch (e) {
                print('Error signing out: $e');
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Error signing out: $e',
                        style: const TextStyle(color: Colors.white),
                      ),
                      backgroundColor: Colors.black,
                    ),
                  );
                }
              }
            },
            tooltip: 'Logout',
          ),
        ],
      ),
      body:
          _isLoading
              ? const Center(
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 3,
                ),
              )
              : _errorMessage != null
              ? Center(
                child: Card(
                  color: Colors.black,
                  elevation: 8,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  margin: const EdgeInsets.all(16),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: Colors.white,
                          size: 40,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _errorMessage!,
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton(
                          onPressed: _fetchMovies,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 40,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: const BorderSide(color: Colors.white),
                            ),
                          ),
                          child: const Text(
                            'Retry',
                            style: TextStyle(fontSize: 16, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
              : RefreshIndicator(
                onRefresh: () => Future.value(), // Disable pull-to-refresh
                color: Colors.white,
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
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 1.5,
                            shadows: [
                              Shadow(
                                color: Colors.white,
                                offset: Offset(1.0, 1.0),
                                blurRadius: 2.0,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        widget.flaskServerFailed
                            ? const Center(
                              child: Card(
                                color: Colors.black,
                                elevation: 4,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.all(
                                    Radius.circular(12),
                                  ),
                                ),
                                child: Padding(
                                  padding: EdgeInsets.all(12),
                                  child: Text(
                                    'Recommendations unavailable: Flask server not running.',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.white,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                            )
                            : _recommendedMovies.isEmpty
                            ? const Center(
                              child: Card(
                                color: Colors.black,
                                elevation: 4,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.all(
                                    Radius.circular(12),
                                  ),
                                ),
                                child: Padding(
                                  padding: EdgeInsets.all(12),
                                  child: Text(
                                    'No recommendations available.',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.white,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                            )
                            : SizedBox(
                              height: 240,
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
                                        if (mounted) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Cannot load movie details: Missing TMDB ID.',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                ),
                                              ),
                                              backgroundColor: Colors.black,
                                            ),
                                          );
                                        }
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
                                    child: Padding(
                                      padding: const EdgeInsets.only(right: 12),
                                      child: Card(
                                        elevation: 6,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            15,
                                          ),
                                        ),
                                        color: Colors.black,
                                        child: Container(
                                          width: 150,
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              ClipRRect(
                                                borderRadius:
                                                    const BorderRadius.vertical(
                                                      top: Radius.circular(15),
                                                    ),
                                                child:
                                                    movie['poster_path'] !=
                                                                null &&
                                                            movie['poster_path']
                                                                .isNotEmpty
                                                        ? Image.network(
                                                          'https://image.tmdb.org/t/p/w200${movie['poster_path']}',
                                                          fit: BoxFit.cover,
                                                          height: 180,
                                                          width: 150,
                                                          errorBuilder:
                                                              (
                                                                context,
                                                                error,
                                                                stackTrace,
                                                              ) => Container(
                                                                height: 180,
                                                                width: 150,
                                                                color:
                                                                    Colors
                                                                        .black,
                                                                child: const Icon(
                                                                  Icons.error,
                                                                  size: 40,
                                                                  color:
                                                                      Colors
                                                                          .white,
                                                                ),
                                                              ),
                                                        )
                                                        : Container(
                                                          height: 180,
                                                          width: 150,
                                                          color: Colors.black,
                                                          child: const Icon(
                                                            Icons.movie,
                                                            size: 40,
                                                            color: Colors.white,
                                                          ),
                                                        ),
                                              ),
                                              Padding(
                                                padding: const EdgeInsets.all(
                                                  8.0,
                                                ),
                                                child: Text(
                                                  movie['title'] ??
                                                      'Unknown Title',
                                                  style: const TextStyle(
                                                    fontSize: 14,
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
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
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 1.5,
                            shadows: [
                              Shadow(
                                color: Colors.white,
                                offset: Offset(1.0, 1.0),
                                blurRadius: 2.0,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        _allMovies.isEmpty
                            ? const Center(
                              child: Card(
                                color: Colors.black,
                                elevation: 4,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.all(
                                    Radius.circular(12),
                                  ),
                                ),
                                child: Padding(
                                  padding: EdgeInsets.all(12),
                                  child: Text(
                                    'No movies available.',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.white,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
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
                                      if (mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Cannot load movie details: Missing TMDB ID.',
                                              style: TextStyle(
                                                color: Colors.white,
                                              ),
                                            ),
                                            backgroundColor: Colors.black,
                                          ),
                                        );
                                      }
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
                                  child: Card(
                                    elevation: 6,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(15),
                                    ),
                                    color: Colors.black,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        ClipRRect(
                                          borderRadius:
                                              const BorderRadius.vertical(
                                                top: Radius.circular(15),
                                              ),
                                          child:
                                              movie['poster_path'] != null
                                                  ? Image.network(
                                                    'https://image.tmdb.org/t/p/w200${movie['poster_path']}',
                                                    fit: BoxFit.cover,
                                                    height: 180,
                                                    width: double.infinity,
                                                    errorBuilder:
                                                        (
                                                          context,
                                                          error,
                                                          stackTrace,
                                                        ) => Container(
                                                          height: 180,
                                                          color: Colors.black,
                                                          child: const Icon(
                                                            Icons.error,
                                                            size: 40,
                                                            color: Colors.white,
                                                          ),
                                                        ),
                                                  )
                                                  : Container(
                                                    height: 180,
                                                    color: Colors.black,
                                                    child: const Icon(
                                                      Icons.movie,
                                                      size: 40,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.all(8.0),
                                          child: Text(
                                            movie['title'] ?? 'Unknown Title',
                                            style: const TextStyle(
                                              fontSize: 14,
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
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
