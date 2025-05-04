from flask import Flask, request, jsonify
import requests
import pandas as pd
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity
import numpy as np
import os
import time
import random
import csv

app = Flask(__name__)

TMDB_API_KEY = 'caa52eead5146df17afc06cfce2168b9'
DATASET_FILE = 'movies_dataset.csv'
TARGET_MOVIE_COUNT = 3000
REQUEST_DELAY = 0.1

df = None
cosine_sim = None
tfidf = None
model_loaded = False

def fetch_movies_for_dataset(target_count=TARGET_MOVIE_COUNT):
    movies = []
    page = 1
    movies_fetched = 0

    while movies_fetched < target_count:
        try:
            print(f"Fetching page {page}...")
            response = requests.get(
                f'https://api.themoviedb.org/3/discover/movie?api_key={TMDB_API_KEY}&sort_by=popularity.desc&page={page}',
                timeout=10
            )
            if response.status_code != 200:
                print(f"Skipping page {page} due to status code: {response.status_code}")
                page += 1
                continue

            data = response.json().get('results', [])
            if not data:
                print(f"No more movies available after page {page}.")
                break

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
                movies_fetched += 1

                if movies_fetched >= target_count:
                    break

                time.sleep(REQUEST_DELAY)

            page += 1
            time.sleep(REQUEST_DELAY)

        except Exception as e:
            print(f"Error fetching movies from TMDB (page {page}): {e}")
            page += 1
            continue

    print(f"Fetched {len(movies)} movies for dataset.")
    return movies

def save_dataset_to_csv(movies):
    try:
        with open(DATASET_FILE, 'w', newline='', encoding='utf-8') as f:
            writer = csv.DictWriter(f, fieldnames=['id', 'title', 'poster_path', 'genres', 'cast', 'release_date', 'overview', 'features'])
            writer.writeheader()
            for movie in movies:
                movie_copy = movie.copy()
                movie_copy['genres'] = ','.join(movie_copy['genres'])
                movie_copy['cast'] = ','.join(movie_copy['cast'])
                writer.writerow(movie_copy)
        print(f"Saved dataset to {DATASET_FILE}.")
    except Exception as e:
        print(f"Error saving dataset to {DATASET_FILE}: {e}")

def load_dataset_from_csv():
    if not os.path.exists(DATASET_FILE):
        print(f"Dataset file {DATASET_FILE} not found.")
        return None

    try:
        movies = []
        with open(DATASET_FILE, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            for row in reader:
                row['genres'] = row['genres'].split(',') if row['genres'] else []
                row['cast'] = row['cast'].split(',') if row['cast'] else []
                row['id'] = int(row['id'])
                movies.append(row)
        print(f"Loaded {len(movies)} movies from {DATASET_FILE}.")
        return movies
    except Exception as e:
        print(f"Error loading dataset from {DATASET_FILE}: {e}")
        return None

def build_recommendation_model(movies):
    df = pd.DataFrame(movies)
    tfidf = TfidfVectorizer(stop_words='english')
    tfidf_matrix = tfidf.fit_transform(df['features'])
    cosine_sim = cosine_similarity(tfidf_matrix, tfidf_matrix)
    return df, cosine_sim, tfidf

def load_or_refresh_model():
    global df, cosine_sim, tfidf, model_loaded
    movies = load_dataset_from_csv()
    if movies is None or len(movies) < TARGET_MOVIE_COUNT:
        print("CSV dataset insufficient or missing, fetching from TMDB...")
        movies = fetch_movies_for_dataset(target_count=TARGET_MOVIE_COUNT)
        if not movies:
            print("No movies fetched to build the model.")
            return
        save_dataset_to_csv(movies)
    else:
        print(f"Using existing CSV dataset with {len(movies)} movies.")

    df, cosine_sim, tfidf = build_recommendation_model(movies)
    if df is None or cosine_sim is None or tfidf is None:
        print("Failed to load or refresh recommendation model.")
    else:
        print(f"Recommendation model loaded/refreshed with {len(df)} movies.")
        model_loaded = True

def get_recommendations(history, limit=10):
    global df, cosine_sim, tfidf
    load_or_refresh_model()

    if df is None or cosine_sim is None or tfidf is None:
        print("Recommendation model not available, returning empty list.")
        return []

    try:
        if not history:
            print("No user history provided, returning random movies.")
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
                    'tmdb_id': int(movie['id'])  # Convert to Python int
                }
                for movie in random_movies
            ]

        user_features = []
        weights = []
        for entry in history:
            genres = [g.replace(' ', '_').lower() for g in entry.get('genres', [])]
            cast = [c.replace(' ', '_').lower() for c in entry.get('cast', [])]
            if not genres and not cast:
                print(f"Skipping history entry for {entry.get('title', 'unknown')} due to empty genres and cast.")
                continue
            feature_str = ' '.join(genres + cast)
            user_features.append(feature_str)

            watch_time = entry.get('watch_time', 0)
            timestamp = entry.get('timestamp', 0)
            if watch_time > 0:
                weight = 1 + (watch_time / 60.0)
            else:
                days_old = (time.time() * 1000 - timestamp) / (1000 * 60 * 60 * 24)
                weight = 1 + (1 / (days_old + 1))
            weights.append(weight)

        if not user_features:
            print("No valid user history entries, returning random movies.")
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
                    'tmdb_id': int(movie['id'])  # Convert to Python int
                }
                for movie in random_movies
            ]

        print(f"User history features: {user_features}")
        print(f"Weights: {weights}")

        user_tfidf = tfidf.transform(user_features)
        weighted_tfidf = np.zeros_like(user_tfidf[0].toarray())
        total_weight = sum(weights)
        for i, weight in enumerate(weights):
            weighted_tfidf += user_tfidf[i].toarray() * (weight / (total_weight + 1e-10))

        user_sim_scores = cosine_similarity(weighted_tfidf, tfidf.transform(df['features'])).flatten()
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
                    'tmdb_id': int(movie['id'])  # Convert to Python int
                })
                seen_titles.add(movie['title'])

        if len(recommended_movies) < limit:
            print("Not enough unique recommendations, fetching more movies...")
            new_movies = fetch_movies_for_dataset(target_count=limit - len(recommended_movies))
            if new_movies:
                new_df = pd.DataFrame(new_movies)
                df = pd.concat([df, new_df]).drop_duplicates(subset=['id']).reset_index(drop=True)
                save_dataset_to_csv(df.to_dict('records'))
                tfidf_matrix = tfidf.fit_transform(df['features'])
                cosine_sim = cosine_similarity(tfidf_matrix, tfidf_matrix)

                user_tfidf = tfidf.transform(user_features)
                weighted_tfidf = np.zeros_like(user_tfidf[0].toarray())
                total_weight = sum(weights)
                for i, weight in enumerate(weights):
                    weighted_tfidf += user_tfidf[i].toarray() * (weight / (total_weight + 1e-10))

                user_sim_scores = cosine_similarity(weighted_tfidf, tfidf.transform(df['features'])).flatten()
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
                            'tmdb_id': int(movie['id'])  # Convert to Python int
                        })
                        seen_titles.add(movie['title'])

        print(f"Returning {len(recommended_movies)} unique recommendations: {[movie['title'] for movie in recommended_movies]}")
        return recommended_movies[:limit]
    except Exception as e:
        print(f"Error generating recommendations: {e}")
        return []

@app.route('/recommend', methods=['POST'])
def recommend():
    try:
        data = request.get_json()
        history = data.get('history', [])
        limit = data.get('limit', 10)

        recommended_movies = get_recommendations(history, limit)
        return jsonify(recommended_movies)
    except Exception as e:
        print(f"Error in /recommend endpoint: {e}")
        return jsonify({'error': str(e)}), 500

if __name__ == '__main__':
    print("Starting Flask server for movie recommendations...")
    app.run(debug=True, host='0.0.0.0', port=5000)