import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class StreamService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<String?> getStreamingUrl(String movieId) async {
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) {
        throw Exception('User not logged in');
      }

      DocumentSnapshot movieDoc =
          await _firestore.collection('movies').doc(movieId).get();

      if (!movieDoc.exists) {
        throw Exception('Movie not found');
      }

      Map<String, dynamic> movieData = movieDoc.data() as Map<String, dynamic>;
      String? streamingUrl = movieData['streamingUrl'];

      if (streamingUrl == null) {
        throw Exception('Streaming URL not available for this movie');
      }

      return streamingUrl;
    } catch (e) {
      throw Exception('Error fetching streaming URL: $e');
    }
  }

  Future<String?> initiateTorrentStream(String magnetLink) async {
    try {
      print('Initiating torrent stream for magnet link: $magnetLink');
      return magnetLink;
    } catch (e) {
      throw Exception('Error initiating torrent stream: $e');
    }
  }
}
