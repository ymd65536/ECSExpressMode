from flask import Flask, jsonify
import os

app = Flask(__name__)

@app.route('/')
def index():
    return jsonify({
        'message': 'Hello from ECS Express Mode!',
        'status': 'running'
    })

@app.route('/health')
def health():
    return jsonify({
        'status': 'healthy'
    }), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=80)
