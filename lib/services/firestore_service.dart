import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> saveInteraction(
    String userId,
    Map<String, dynamic> movie,
  ) async {
    try {
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('interactions')
          .add({
            'movie_id': movie['id'],
            'title': movie['title'],
            'timestamp': FieldValue.serverTimestamp(),
            'genres': movie['genres'],
            'cast': movie['cast'],
          });
    } catch (e) {
      print('Error saving interaction: $e');
      throw e;
    }
  }

  Future<void> saveWatchHistory(
    String userId,
    Map<String, dynamic> movie,
    int watchTime,
  ) async {
    try {
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('watch_history')
          .add({
            'movie_id': movie['id'],
            'title': movie['title'],
            'watch_time': watchTime,
            'timestamp': FieldValue.serverTimestamp(),
            'genres': movie['genres'],
            'cast': movie['cast'],
          });
    } catch (e) {
      print('Error saving watch history: $e');
      throw e;
    }
  }

  Future<List<Map<String, dynamic>>> getWatchHistory(String userId) async {
    try {
      final querySnapshot =
          await _firestore
              .collection('users')
              .doc(userId)
              .collection('watch_history')
              .orderBy('timestamp', descending: true)
              .limit(10)
              .get();
      return querySnapshot.docs
          .map((doc) => doc.data() as Map<String, dynamic>)
          .toList();
    } catch (e) {
      print('Error fetching watch history: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getInteractions(String userId) async {
    try {
      final querySnapshot =
          await _firestore
              .collection('users')
              .doc(userId)
              .collection('interactions')
              .orderBy('timestamp', descending: true)
              .limit(10)
              .get();
      return querySnapshot.docs
          .map((doc) => doc.data() as Map<String, dynamic>)
          .toList();
    } catch (e) {
      print('Error fetching interactions: $e');
      return [];
    }
  }
}
