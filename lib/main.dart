import 'dart:convert';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'
    show PlatformDispatcher, kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:watchm/services/auth_service.dart';
import 'package:watchm/screens/login_screen.dart';
import 'package:watchm/screens/signup_screen.dart';
import 'package:watchm/screens/home_screen.dart';
import 'package:watchm/screens/movie_detail_screen.dart';
import 'package:watchm/screens/watch_movie_screen.dart';

void main() async {
  print('Starting app initialization...');
  FlutterError.onError = (FlutterErrorDetails details) {
    print('Caught unhandled Flutter error: ${details.exception}');
    print('Stack trace: ${details.stack}');
    if (kDebugMode) {
      FlutterError.dumpErrorToConsole(details);
    }
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    print('Caught unhandled platform error: $error');
    print('Stack trace: $stack');
    return true;
  };

  try {
    print('Initializing Flutter bindings...');
    WidgetsFlutterBinding.ensureInitialized();
    print('Flutter bindings initialized.');

    print('Initializing Firebase...');
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    print('Firebase initialized successfully');
  } catch (e) {
    print('Error during initialization: $e');
    rethrow;
  }
  print('Running app...');
  runApp(const MyApp());
}

Future<bool> checkFlaskServer() async {
  if (kIsWeb) {
    print('Flask server check skipped on web platform.');
    return false;
  }
  try {
    // Use 10.0.2.2 for Android emulator instead of localhost
    final socket = await Socket.connect(
      '10.0.2.2',
      5000,
      timeout: const Duration(seconds: 2),
    );
    socket.destroy();
    print('Flask server is running on port 5000.');
    return true;
  } catch (e) {
    print('Flask server is not running: $e');
    return false;
  }
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _flaskServerFailed = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    print('MyApp initState called.');
    try {
      checkFlaskServer()
          .then((success) {
            if (!success && mounted) {
              setState(() {
                _flaskServerFailed = true;
              });
              print('Flask server failed: $_flaskServerFailed');
            }
          })
          .catchError((e) {
            print('Error checking Flask server: $e');
            if (mounted) {
              setState(() {
                _flaskServerFailed = true;
                _errorMessage = 'Error checking Flask server: $e';
              });
            }
          });
    } catch (e) {
      print('Error in initState: $e');
      setState(() {
        _flaskServerFailed = true;
        _errorMessage = 'Error in app initialization: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    print('Building MyApp widget...');
    final AuthService _authService = AuthService();

    if (kIsWeb) {
      print('Detected web platform. Showing unsupported message.');
      return MaterialApp(
        home: const Scaffold(
          backgroundColor: Colors.black,
          body: Center(
            child: Text(
              'This app is not supported on web. Please use a mobile device.',
              style: TextStyle(color: Colors.white, fontSize: 20),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    if (_errorMessage != null) {
      print('Showing error message: $_errorMessage');
      return MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: Center(
            child: Text(
              'Error: $_errorMessage\nPlease restart the app or check logs for details.',
              style: const TextStyle(color: Colors.redAccent, fontSize: 20),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    print('Setting up MaterialApp for mobile...');
    return MaterialApp(
      title: 'Movie Recommender',
      theme: ThemeData(
        primarySwatch: Colors.deepPurple,
        scaffoldBackgroundColor: Colors.black,
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Colors.white, fontFamily: 'Roboto'),
          bodyMedium: TextStyle(color: Colors.white70, fontFamily: 'Roboto'),
          titleLarge: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontFamily: 'Roboto',
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            foregroundColor: Colors.white,
            backgroundColor: Colors.deepPurple,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 5,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.black,
          elevation: 2,
          shadowColor: Colors.white10,
          iconTheme: IconThemeData(color: Colors.white),
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
            fontFamily: 'Roboto',
          ),
        ),
      ),
      routes: {
        '/login': (context) => const LoginScreen(),
        '/signup': (context) => const SignupScreen(),
        '/home': (context) => HomeScreen(flaskServerFailed: _flaskServerFailed),
        '/movie_detail': (context) => const MovieDetailScreen(),
        '/watch_movie': (context) => const WatchMovieScreen(),
      },
      home: FutureBuilder<User?>(
        future: _authService.getCurrentUserAsync(),
        builder: (context, AsyncSnapshot<User?> snapshot) {
          print('Building FutureBuilder for auth check...');
          if (snapshot.connectionState == ConnectionState.waiting) {
            print('Auth check waiting...');
            return const Scaffold(
              backgroundColor: Colors.black,
              body: Center(child: CircularProgressIndicator()),
            );
          }

          if (snapshot.hasError) {
            print('Error in authentication check: ${snapshot.error}');
            return const LoginScreen();
          }

          if (snapshot.data != null) {
            print('User logged in, navigating to HomeScreen.');
            return HomeScreen(flaskServerFailed: _flaskServerFailed);
          }

          print('No user logged in, showing LoginScreen.');
          return const LoginScreen();
        },
      ),
    );
  }
}
