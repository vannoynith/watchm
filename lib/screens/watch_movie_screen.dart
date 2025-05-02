import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import '../services/firestore_service.dart';

class WatchMovieScreen extends StatefulWidget {
  const WatchMovieScreen({Key? key}) : super(key: key);

  @override
  _WatchMovieScreenState createState() => _WatchMovieScreenState();
}

class _WatchMovieScreenState extends State<WatchMovieScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  YoutubePlayerController? _controller;
  int _watchTime = 0;
  bool _isWatching = false;
  String? _errorMessage;
  Map<String, dynamic>? _movie;
  String? _trailerUrl;

  @override
  void initState() {
    super.initState();
    // Initialize variables, but defer argument fetching to didChangeDependencies
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    try {
      final arguments =
          ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      if (arguments == null) {
        setState(() {
          _errorMessage = 'No movie data provided.';
        });
        return;
      }

      _movie = arguments['movie'] as Map<String, dynamic>?;
      _trailerUrl = arguments['trailerUrl'] as String?;

      if (_movie == null || _trailerUrl == null) {
        setState(() {
          _errorMessage = 'Invalid movie data or trailer URL.';
        });
        return;
      }

      print(
        'Attempting to convert YouTube trailer URL for movie ${_movie!['title']}: $_trailerUrl',
      );
      String? videoId;

      // Handle different URL formats
      if (_trailerUrl!.contains('youtube.com') ||
          _trailerUrl!.contains('youtu.be')) {
        videoId = YoutubePlayer.convertUrlToId(_trailerUrl!);
      } else {
        // If the URL is just a video ID, construct the full URL
        final videoIdPattern = RegExp(r'^[a-zA-Z0-9_-]{11}$');
        if (videoIdPattern.hasMatch(_trailerUrl!)) {
          videoId = _trailerUrl;
          _trailerUrl = 'https://www.youtube.com/watch?v=$videoId';
          print('Converted video ID to URL: $_trailerUrl');
        }
      }

      if (videoId == null) {
        print('Failed to extract videoId from URL: $_trailerUrl');
        setState(() {
          _errorMessage =
              'Invalid YouTube trailer URL format. Please ensure a valid URL is provided.';
        });
      } else {
        print('Successfully extracted videoId: $videoId');
        _controller = YoutubePlayerController(
          initialVideoId: videoId,
          flags: const YoutubePlayerFlags(
            autoPlay: true,
            mute: false,
            enableCaption: true,
            // showVideoAnnotations: false,
          ),
        )..addListener(() {
          if (_controller!.value.hasError) {
            print(
              'YouTube player error for movie ${_movie!['title']}: ${_controller!.value.errorCode}',
            );
            setState(() {
              _errorMessage =
                  'Error playing trailer: ${_controller!.value.errorCode}';
            });
          } else if (_controller!.value.isReady && !_isWatching) {
            print(
              'YouTube player is ready for movie ${_movie!['title']}, starting watch timer',
            );
            _startWatching();
          }
        });
      }
    } catch (e) {
      print(
        'Error in WatchMovieScreen didChangeDependencies for movie ${_movie?['title'] ?? 'unknown'}: $e',
      );
      setState(() {
        _errorMessage = 'Error initializing YouTube trailer player: $e';
      });
    }
  }

  void _startWatching() {
    setState(() {
      _isWatching = true;
    });
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (_isWatching && mounted) {
        setState(() {
          _watchTime++;
        });
        return true;
      }
      return false;
    }).catchError((e) {
      print(
        'Error in watch time tracking for movie ${_movie?['title'] ?? 'unknown'}: $e',
      );
    });
  }

  @override
  void dispose() {
    _isWatching = false;
    _controller?.dispose();
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId != null && _movie != null) {
        _firestoreService
            .saveWatchHistory(userId, _movie!, _watchTime)
            .then((_) {
              print(
                'Watch history saved for movie: ${_movie!['title']}, watch time: $_watchTime seconds',
              );
            })
            .catchError((error) {
              print(
                'Failed to save watch history for movie ${_movie!['title']}: $error',
              );
            });
      } else {
        print(
          'User not logged in or movie data missing, cannot save watch history.',
        );
      }
    } catch (e) {
      print('Error in dispose for movie ${_movie?['title'] ?? 'unknown'}: $e');
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        print('Navigating back to HomeScreen from WatchMovieScreen');
        Navigator.pushReplacementNamed(context, '/home');
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: Text('Watch Trailer: ${_movie?['title'] ?? 'Unknown Title'}'),
          backgroundColor: Colors.black,
          elevation: 2,
          shadowColor: Colors.white.withOpacity(0.1),
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: Column(
          children: [
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(fontSize: 16, color: Colors.redAccent),
                  textAlign: TextAlign.center,
                ),
              )
            else if (_controller != null)
              YoutubePlayer(
                controller: _controller!,
                showVideoProgressIndicator: true,
                progressIndicatorColor: Colors.deepPurple,
                progressColors: const ProgressBarColors(
                  playedColor: Colors.deepPurple,
                  handleColor: Colors.deepPurpleAccent,
                ),
                onReady: () {
                  print(
                    'YouTube player is ready for movie ${_movie?['title'] ?? 'unknown'}.',
                  );
                },
                onEnded: (metaData) {
                  setState(() {
                    _isWatching = false;
                  });
                  print(
                    'Trailer ended for movie ${_movie?['title'] ?? 'unknown'}, navigating to HomeScreen',
                  );
                  Navigator.pushReplacementNamed(context, '/home');
                },
              ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                children: [
                  Text(
                    'Watching Trailer: ${_movie?['title'] ?? 'Unknown Title'}',
                    style: const TextStyle(
                      fontSize: 20,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Time Spent: $_watchTime seconds',
                    style: const TextStyle(fontSize: 16, color: Colors.white70),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _isWatching = false;
                      });
                      print(
                        'Stop Watching pressed for movie ${_movie?['title'] ?? 'unknown'}, navigating to HomeScreen',
                      );
                      Navigator.pushReplacementNamed(context, '/home');
                    },
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
                      'Stop Watching',
                      style: TextStyle(fontSize: 18, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
