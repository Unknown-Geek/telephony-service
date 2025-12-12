#!/usr/bin/env python3
"""
TTS Server - OpenAI-compatible API using Microsoft Edge TTS
Provides /v1/audio/speech endpoint compatible with OpenAI TTS API
"""

import asyncio
import os
import tempfile
from flask import Flask, request, jsonify, send_file
import edge_tts

app = Flask(__name__)

# Voice mapping (OpenAI voices to Edge TTS voices)
VOICE_MAP = {
    'alloy': 'en-US-AriaNeural',
    'echo': 'en-US-GuyNeural',
    'fable': 'en-GB-SoniaNeural',
    'onyx': 'en-US-ChristopherNeural',
    'nova': 'en-US-JennyNeural',
    'shimmer': 'en-AU-NatashaNeural',
}

SOUNDS_DIR = os.environ.get('SOUNDS_DIR', '/app/sounds')

@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint"""
    return jsonify({'status': 'healthy', 'service': 'edge-tts'})

@app.route('/v1/audio/speech', methods=['POST'])
def text_to_speech():
    """
    OpenAI-compatible TTS endpoint
    Accepts JSON with: model, input, voice, response_format
    """
    try:
        data = request.get_json()
        
        if not data:
            return jsonify({'error': 'No JSON data provided'}), 400
        
        text = data.get('input', '')
        voice_name = data.get('voice', 'alloy')
        response_format = data.get('response_format', 'mp3')
        
        if not text:
            return jsonify({'error': 'No input text provided'}), 400
        
        # Map OpenAI voice to Edge TTS voice
        edge_voice = VOICE_MAP.get(voice_name, 'en-US-AriaNeural')
        
        # Generate TTS audio
        audio_data = asyncio.run(generate_tts(text, edge_voice))
        
        if audio_data:
            # Create temp file with appropriate extension
            suffix = '.mp3'
            with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as f:
                f.write(audio_data)
                temp_path = f.name
            
            return send_file(
                temp_path,
                mimetype='audio/mpeg',
                as_attachment=True,
                download_name=f'speech{suffix}'
            )
        else:
            return jsonify({'error': 'TTS generation failed'}), 500
            
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/v1/tts/generate', methods=['POST'])
def generate_for_asterisk():
    """
    Custom endpoint that saves audio file for Asterisk
    Returns the file path instead of audio data
    """
    try:
        data = request.get_json()
        
        text = data.get('input', '')
        unique_id = data.get('unique_id', 'default')
        voice_name = data.get('voice', 'alloy')
        
        if not text:
            return jsonify({'error': 'No input text provided'}), 400
        
        edge_voice = VOICE_MAP.get(voice_name, 'en-US-AriaNeural')
        
        # Generate TTS
        audio_data = asyncio.run(generate_tts(text, edge_voice))
        
        if audio_data:
            # Save to sounds directory
            output_path = os.path.join(SOUNDS_DIR, f'response_{unique_id}.mp3')
            with open(output_path, 'wb') as f:
                f.write(audio_data)
            
            return jsonify({
                'status': 'success',
                'audio_file': output_path,
                'text': text
            })
        else:
            return jsonify({'error': 'TTS generation failed'}), 500
            
    except Exception as e:
        return jsonify({'error': str(e)}), 500

async def generate_tts(text: str, voice: str) -> bytes:
    """Generate TTS audio using edge-tts"""
    communicate = edge_tts.Communicate(text, voice)
    audio_chunks = []
    
    async for chunk in communicate.stream():
        if chunk['type'] == 'audio':
            audio_chunks.append(chunk['data'])
    
    return b''.join(audio_chunks)

@app.route('/v1/voices', methods=['GET'])
def list_voices():
    """List available voices"""
    return jsonify({
        'voices': [
            {'id': k, 'name': v, 'provider': 'edge-tts'}
            for k, v in VOICE_MAP.items()
        ]
    })

if __name__ == '__main__':
    os.makedirs(SOUNDS_DIR, exist_ok=True)
    app.run(host='0.0.0.0', port=5050, debug=False)
