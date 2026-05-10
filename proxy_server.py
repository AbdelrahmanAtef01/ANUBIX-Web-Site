from flask import Flask, request, jsonify
from flask_cors import CORS
import requests

app = Flask(__name__)
# Legally tells the browser that your Flutter app is allowed to talk to this server
CORS(app) 

# The API Key provided by Andrew is injected here!
OMNILINK_API_KEY = "Bearer olink_Y7moAqrI3XhoSJNnB9fbeQWN"
OMNILINK_URL = "https://www.omnilink-agents.com/api/chat"

@app.route('/api/chat', methods=['POST'])
def chat():
    incoming_data = request.json
    
    headers = {
        'Content-Type': 'application/json',
        'Authorization': OMNILINK_API_KEY
    }
    
    try:
        response = requests.post(OMNILINK_URL, json=incoming_data, headers=headers)
        return jsonify(response.json()), response.status_code
    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    print("🟢 Anubix Middleware Server running on port 5000...")
    app.run(port=5000)