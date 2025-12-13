#!/usr/bin/env python3
"""
Whisper STT Service - Free Speech-to-Text using faster-whisper
Runs on port 5051
"""

import os
import tempfile
from flask import Flask, request, jsonify
from faster_whisper import WhisperModel

app = Flask(__name__)

# Load model on startup (using 'base' for speed, 'small' for better accuracy)
MODEL_SIZE = os.environ.get("WHISPER_MODEL", "base")
print(f"Loading Whisper model: {MODEL_SIZE}")
model = WhisperModel(MODEL_SIZE, device="cpu", compute_type="int8")
print("Model loaded!")

@app.route('/health', methods=['GET'])
def health():
    return jsonify({"status": "ok", "model": MODEL_SIZE})

@app.route('/transcribe', methods=['POST'])
def transcribe():
    """
    Accepts audio file upload and returns transcribed text.
    Expects multipart/form-data with 'file' field.
    """
    if 'file' not in request.files:
        return jsonify({"error": "No file provided"}), 400
    
    audio_file = request.files['file']
    
    # Save to temp file
    with tempfile.NamedTemporaryFile(suffix='.wav', delete=False) as tmp:
        audio_file.save(tmp.name)
        tmp_path = tmp.name
    
    try:
        # Transcribe
        segments, info = model.transcribe(tmp_path, beam_size=5)
        text = " ".join([segment.text for segment in segments])
        
        return jsonify({
            "text": text.strip(),
            "language": info.language,
            "duration": info.duration
        })
    except Exception as e:
        return jsonify({"error": str(e)}), 500
    finally:
        # Cleanup
        os.unlink(tmp_path)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5051)
