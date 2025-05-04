import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For orientation control
import 'package:firebase_auth/firebase_auth.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import '../services/firestore_service.dart';

class WatchMovieScreen extends StatefulWidget {
  const WatchMovieScreen({Key? key}) : super(key: key);

  @override
  _WatchMovieScreenState createState() => _WatchMovieScreenState();
}

class _WatchMovieScreenState extends State<WatchMovieScreen>
    with WidgetsBindingObserver {
  final FirestoreService _firestoreService = FirestoreService();
  YoutubePlayerController? _controller;
  int _watchTime = 0;
  bool _isWatching = false;
  bool _isPlaying = true;
  String? _errorMessage;
  Map<String, dynamic>? _movie;
  String? _trailerUrl;
  bool _showControls = true;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _initializePlayer();
  }

  void _initializePlayer() {
    if (_isDisposed) return;
    try {
      final arguments =
          ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      if (arguments == null) {
        _setError('No movie data provided.');
        return;
      }

      _movie = arguments['movie'] as Map<String, dynamic>?;
      _trailerUrl = arguments['trailerUrl'] as String?;

      if (_movie == null || _trailerUrl == null) {
        _setError('Invalid movie data or trailer URL.');
        return;
      }

      print('Movie title: ${_movie!['title']}');
      print('Raw trailer URL: $_trailerUrl');
      String? videoId;

      if (_trailerUrl!.contains('youtube.com') ||
          _trailerUrl!.contains('youtu.be')) {
        videoId = YoutubePlayer.convertUrlToId(_trailerUrl!);
        print('Extracted videoId from URL: $videoId');
      } else {
        final videoIdPattern = RegExp(r'^[a-zA-Z0-9_-]{11}$');
        if (videoIdPattern.hasMatch(_trailerUrl!)) {
          videoId = _trailerUrl;
          _trailerUrl = 'https://www.youtube.com/watch?v=$videoId';
          print('Converted video ID to URL: $_trailerUrl');
        }
      }

      if (videoId == null) {
        print('Failed to extract videoId from URL: $_trailerUrl');
        _setError(
          'Invalid YouTube trailer URL format. Please ensure a valid URL is provided.',
        );
        return;
      }

      print('Successfully extracted videoId: $videoId');
      _controller = YoutubePlayerController(
        initialVideoId: videoId,
        flags: const YoutubePlayerFlags(
          autoPlay: true,
          mute: false,
          enableCaption: true,
          loop: false,
          forceHD: false,
        ),
      )..addListener(_playerListener);
    } catch (e) {
      print(
        'Error in WatchMovieScreen didChangeDependencies for movie ${_movie?['title'] ?? 'unknown'}: $e',
      );
      _setError('Error initializing YouTube trailer player: $e');
    }
  }

  void _playerListener() {
    if (_isDisposed) return;
    if (_controller!.value.hasError) {
      print(
        'YouTube player error for movie ${_movie!['title']}: ${_controller!.value.errorCode}',
      );
      _setError('Error playing trailer: ${_controller!.value.errorCode}');
    } else if (_controller!.value.isReady && !_isWatching) {
      print(
        'YouTube player is ready for movie ${_movie!['title']}, starting watch timer',
      );
      _startWatching();
    }
    if (_controller!.value.playerState == PlayerState.ended) {
      if (mounted) {
        setState(() {
          _isWatching = false;
          _isPlaying = false;
          _showControls = true;
        });
      }
      print('Trailer ended for movie ${_movie!['title']}, pausing');
    }
  }

  void _setError(String message) {
    if (_isDisposed || !mounted) return;
    setState(() {
      _errorMessage = message;
    });
  }

  void _startWatching() {
    if (_isDisposed || !mounted) return;
    setState(() {
      _isWatching = _controller!.value.isPlaying;
    });
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (_isWatching && mounted && _controller!.value.isPlaying) {
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

  void _skipForward() {
    if (_controller == null || _isDisposed) return;
    final currentPosition = _controller!.value.position.inSeconds;
    _controller!.seekTo(Duration(seconds: currentPosition + 10));
  }

  void _skipBackward() {
    if (_controller == null || _isDisposed) return;
    final currentPosition = _controller!.value.position.inSeconds;
    _controller!.seekTo(
      Duration(
        seconds: (currentPosition - 10).clamp(0, double.infinity).toInt(),
      ),
    );
  }

  Future<void> _toggleFullScreen() async {
    if (_isDisposed || !mounted) return;
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    await Future.delayed(const Duration(milliseconds: 200));
    if (mounted) {
      setState(() {
        _controller?.pause();
        Navigator.pop(context);
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      if (_controller != null && _isPlaying) {
        _controller!.pause();
        setState(() {
          _isPlaying = false;
          _isWatching = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _isWatching = false;
    _controller?.removeListener(_playerListener);
    _controller?.dispose();
    WidgetsBinding.instance.removeObserver(this);

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId != null && _movie != null && _watchTime > 0) {
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
        'User not logged in, movie data missing, or no watch time recorded, cannot save watch history.',
      );
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return WillPopScope(
      onWillPop: () async {
        await _toggleFullScreen();
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          elevation: 2,
          shadowColor: Colors.white.withOpacity(0.1),
          iconTheme: const IconThemeData(color: Colors.white),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _toggleFullScreen,
          ),
          title: Text(
            _movie?['title'] ?? 'Unknown Title',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_errorMessage != null)
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: screenWidth * 0.05,
                          vertical: 16.0,
                        ),
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.white,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      )
                    else if (_controller != null)
                      YoutubePlayerBuilder(
                        player: YoutubePlayer(
                          controller: _controller!,
                          showVideoProgressIndicator: true,
                          progressIndicatorColor: Colors.white,
                          progressColors: const ProgressBarColors(
                            playedColor: Colors.white,
                            handleColor: Colors.white,
                          ),
                          onReady: () {
                            print(
                              'YouTube player is ready for movie ${_movie?['title'] ?? 'unknown'}.',
                            );
                          },
                        ),
                        builder: (context, player) {
                          return GestureDetector(
                            onTap: () {
                              if (!_isDisposed && mounted) {
                                setState(() {
                                  _showControls = !_showControls;
                                });
                              }
                            },
                            child: Container(
                              width: screenWidth,
                              height: screenHeight,
                              color: Colors.black,
                              child: Stack(
                                children: [
                                  player,
                                  if (_showControls)
                                    Positioned.fill(
                                      child: Container(
                                        color: Colors.black.withOpacity(0.5),
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.spaceEvenly,
                                              children: [
                                                IconButton(
                                                  icon: const Icon(
                                                    Icons.replay_10,
                                                    color: Colors.white,
                                                    size: 30,
                                                  ),
                                                  onPressed: _skipBackward,
                                                  tooltip: 'Skip Back 10s',
                                                ),
                                                IconButton(
                                                  icon: Icon(
                                                    _isPlaying
                                                        ? Icons
                                                            .pause_circle_filled
                                                        : Icons
                                                            .play_circle_filled,
                                                    color: Colors.white,
                                                    size: 40,
                                                  ),
                                                  onPressed: () {
                                                    if (!_isDisposed &&
                                                        mounted) {
                                                      setState(() {
                                                        _isPlaying =
                                                            !_isPlaying;
                                                        _isWatching =
                                                            _isPlaying;
                                                        _isPlaying
                                                            ? _controller!
                                                                .play()
                                                            : _controller!
                                                                .pause();
                                                      });
                                                    }
                                                  },
                                                  tooltip:
                                                      _isPlaying
                                                          ? 'Pause'
                                                          : 'Play',
                                                ),
                                                IconButton(
                                                  icon: const Icon(
                                                    Icons.forward_10,
                                                    color: Colors.white,
                                                    size: 30,
                                                  ),
                                                  onPressed: _skipForward,
                                                  tooltip: 'Skip Forward 10s',
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
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
            );
          },
        ),
      ),
    );
  }
}
