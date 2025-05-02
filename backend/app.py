from flask import Flask, request, jsonify
import requests
import pandas as pd
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity
import numpy as np
import os
import time
import random

app = Flask(__name__)

TMDB_API_KEY = 'caa52eead5146df17afc06cfce2168b9'
MODEL_REFRESH_FILE = 'last_model_refresh.txt'

# Global variables for the recommendation model
df = None
cosine_sim = None
tfidf = None
model_loaded = False  # Track if the model has been loaded

def fetch_movies_for_dataset(pages=5):
    """Fetch movies from TMDB to build the recommendation dataset."""
    movies = []
    for page in range(1, pages + 1):
        try:
            response = requests.get(
                f'https://api.themoviedb.org/3/discover/movie?api_key={TMDB_API_KEY}&sort_by=popularity.desc&page={page}',
                timeout=10
            )
            if response.status_code != 200:
                print(f"Skipping page {page} due to status code: {response.status_code}")
                continue

            data = response.json().get('results', [])
            for movie in data:
                movie_id = movie['id']
                details_response = requests.get(
                    f'https://api.themoviedb.org/3/movie/{movie_id}?api_key={TMDB_API_KEY}&append_to_response=credits',
                    timeout=10
                )
                if details_response.status_code != 200:
                    print(f"Skipping movie {movie_id} due to details fetch failure: {details_response.status_code}")
                    continue

                details = details_response.json()
                movie_genres = [g['name'].replace(' ', '_').lower() for g in details.get('genres', [])]
                movie_cast = [c['name'].replace(' ', '_').lower() for c in details.get('credits', {}).get('cast', [])[:5]]

                movies.append({
                    'id': movie_id,
                    'title': details.get('title', 'Unknown Title'),
                    'poster_path': details.get('poster_path'),
                    'genres': movie_genres,
                    'cast': movie_cast,
                    'release_date': details.get('release_date', 'Unknown')[:4],
                    'overview': details.get('overview', 'No description available'),
                    'features': ' '.join(movie_genres + movie_cast)
                })
        except Exception as e:
            print(f"Error fetching movies from TMDB (page {page}): {e}")
            continue
    print(f"Fetched {len(movies)} movies for dataset.")
    return movies

def build_recommendation_model():
    """Build or rebuild the recommendation model using TF-IDF and cosine similarity."""
    movies = fetch_movies_for_dataset(pages=5)
    if not movies:
        print("No movies fetched to build the model.")
        return None, None, None

    df = pd.DataFrame(movies)
    tfidf = TfidfVectorizer(stop_words='english')
    tfidf_matrix = tfidf.fit_transform(df['features'])
    cosine_sim = cosine_similarity(tfidf_matrix, tfidf_matrix)
    return df, cosine_sim, tfidf

def should_refresh_model():
    """Check if the model should be refreshed (every 24 hours)."""
    if not os.path.exists(MODEL_REFRESH_FILE):
        print(f"Model refresh file {MODEL_REFRESH_FILE} not found, creating it.")
        with open(MODEL_REFRESH_FILE, 'w') as f:
            f.write(str(time.time()))
        return True

    try:
        with open(MODEL_REFRESH_FILE, 'r') as f:
            last_refresh = float(f.read().strip())
    except (ValueError, IOError) as e:
        print(f"Error reading {MODEL_REFRESH_FILE}: {e}, forcing refresh.")
        return True

    current_time = time.time()
    time_diff = current_time - last_refresh
    refresh_needed = time_diff >= 24 * 60 * 60
    print(f"Time since last refresh: {time_diff/3600:.2f} hours, refresh needed: {refresh_needed}")
    return refresh_needed

def update_refresh_timestamp():
    """Update the timestamp of the last model refresh."""
    try:
        with open(MODEL_REFRESH_FILE, 'w') as f:
            f.write(str(time.time()))
        print(f"Updated refresh timestamp in {MODEL_REFRESH_FILE}.")
    except IOError as e:
        print(f"Error updating {MODEL_REFRESH_FILE}: {e}")

def load_or_refresh_model():
    """Load the existing model or refresh it if needed."""
    global df, cosine_sim, tfidf, model_loaded
    if model_loaded and not should_refresh_model():
        print("Model already loaded and no refresh needed.")
        return

    print("Loading or refreshing recommendation model...")
    df, cosine_sim, tfidf = build_recommendation_model()
    if df is None or cosine_sim is None or tfidf is None:
        print("Failed to load or refresh recommendation model.")
    else:
        print(f"Recommendation model loaded/refreshed with {len(df)} movies.")
        model_loaded = True
        update_refresh_timestamp()

def get_recommendations(genres, cast, limit=10):
    """Generate movie recommendations based on genres and cast."""
    global df, cosine_sim, tfidf
    load_or_refresh_model()

    if df is None or cosine_sim is None or tfidf is None:
        print("Recommendation model not available, returning empty list.")
        return []

    try:
        genres = [g.replace(' ', '_').lower() for g in genres] if genres else []
        cast = [c.replace(' ', '_').lower() for c in cast] if cast else []
        print(f"Received genres: {genres}, cast: {cast}")

        if not genres and not cast:
            print("No genres or cast provided, returning random movies.")
            if len(df) <= limit:
                random_movies = df.to_dict('records')
            else:
                random_indices = random.sample(range(len(df)), limit)
                random_movies = df.iloc[random_indices].to_dict('records')
            return [
                {
                    'title': movie['title'],
                    'poster_path': movie['poster_path'],
                    'genres': movie['genres'],
                    'cast': movie['cast'],
                    'release_date': movie['release_date'],
                    'overview': movie['overview'],
                }
                for movie in random_movies
            ]

        user_features = ' '.join(genres + cast)
        print(f"Generating recommendations with features: {user_features}")

        user_tfidf = tfidf.transform([user_features])
        user_sim_scores = cosine_similarity(user_tfidf, tfidf.transform(df['features'])).flatten()
        movie_indices = user_sim_scores.argsort()[::-1]

        recommended_movies = []
        seen_titles = set()
        for idx in movie_indices:
            if user_sim_scores[idx] <= 0:
                continue
            if len(recommended_movies) >= limit:
                break
            movie = df.iloc[idx]
            if movie['title'] not in seen_titles:
                recommended_movies.append({
                    'title': movie['title'],
                    'poster_path': movie['poster_path'],
                    'genres': movie['genres'],
                    'cast': movie['cast'],
                    'release_date': movie['release_date'],
                    'overview': movie['overview'],
                })
                seen_titles.add(movie['title'])

        if len(recommended_movies) < limit:
            print("Not enough unique recommendations, fetching more movies...")
            new_movies = fetch_movies_for_dataset(pages=1)
            if new_movies:
                new_df = pd.DataFrame(new_movies)
                df = pd.concat([df, new_df]).drop_duplicates(subset=['id']).reset_index(drop=True)
                tfidf_matrix = tfidf.fit_transform(df['features'])
                cosine_sim = cosine_similarity(tfidf_matrix, tfidf_matrix)

                user_tfidf = tfidf.transform([user_features])
                user_sim_scores = cosine_similarity(user_tfidf, tfidf.transform(df['features'])).flatten()
                movie_indices = user_sim_scores.argsort()[::-1]

                for idx in movie_indices:
                    if user_sim_scores[idx] <= 0:
                        continue
                    if len(recommended_movies) >= limit:
                        break
                    movie = df.iloc[idx]
                    if movie['title'] not in seen_titles:
                        recommended_movies.append({
                            'title': movie['title'],
                            'poster_path': movie['poster_path'],
                            'genres': movie['genres'],
                            'cast': movie['cast'],
                            'release_date': movie['release_date'],
                            'overview': movie['overview'],
                        })
                        seen_titles.add(movie['title'])

        print(f"Returning {len(recommended_movies)} unique recommendations: {[movie['title'] for movie in recommended_movies]}")
        return recommended_movies[:limit]
    except Exception as e:
        print(f"Error generating recommendations: {e}")
        return []

@app.route('/recommend', methods=['POST'])
def recommend():
    """Endpoint to receive user preferences and return movie recommendations."""
    try:
        data = request.get_json()
        genres = data.get('genres', [])
        cast = data.get('cast', [])
        limit = data.get('limit', 10)

        recommended_movies = get_recommendations(genres, cast, limit)
        return jsonify(recommended_movies)
    except Exception as e:
        print(f"Error in /recommend endpoint: {e}")
        return jsonify({'error': str(e)}), 500

# Load or refresh the model when the server starts
if __name__ == '__main__':
    print("Starting Flask server for movie recommendations...")
    load_or_refresh_model()
    app.run(debug=True, host='0.0.0.0', port=5000)