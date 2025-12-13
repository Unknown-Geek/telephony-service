const express = require('express');
const bodyParser = require('body-parser');
const { exec } = require('child_process');
const fs = require('fs');
const path = require('path');
const app = express();
const port = process.env.PORT || 3030;

const ASTERISK_HOST = process.env.ASTERISK_HOST || 'localhost';
const CONVERSATION_DIR = '/var/lib/asterisk/conversations';

// Ensure conversation directory exists
try {
    if (!fs.existsSync(CONVERSATION_DIR)) {
        fs.mkdirSync(CONVERSATION_DIR, { recursive: true });
    }
} catch (e) {
    console.warn('Could not create conversation dir:', e.message);
}

app.use(bodyParser.json());

// Health check
app.get('/', (req, res) => {
    res.json({ 
        status: 'running',
        service: 'Asterisk Telephony API',
        version: '3.0.0',
        endpoints: {
            'POST /call': 'Trigger outbound call with script',
            'GET /calls': 'List active calls',
            'POST /hangup': 'Hangup a call',
            'GET /conversation/:sessionId': 'Get conversation transcript'
        }
    });
});

app.get('/health', (req, res) => {
    res.json({ status: 'ok' });
});

/**
 * Trigger an outbound call with a custom script
 * 
 * Required: phoneNumber (E.164 format, e.g., +919074691700)
 * Required: script (text to narrate to the receiver)
 * Optional: callbackUrl (URL to POST conversation when call ends)
 */
app.post('/call', async (req, res) => {
    const { 
        phoneNumber, 
        script,
        callbackUrl,
        context = 'outbound-ai-conversational', 
        extension = 's',
        callerId = '+17756187988'
    } = req.body;

    // Validation
    if (!phoneNumber) {
        return res.status(400).json({ 
            error: 'phoneNumber is required',
            format: 'E.164 format (e.g., +919074691700)'
        });
    }

    if (!script) {
        return res.status(400).json({ 
            error: 'script is required',
            description: 'The exact conversational text for the voice AI to speak'
        });
    }

    // Sanitize inputs
    const safeNumber = phoneNumber.replace(/[^0-9+]/g, '');
    const sessionId = `call_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
    
    // Escape script for shell
    const safeScript = script.replace(/'/g, "'\\''").replace(/"/g, '\\"');
    const safeCallback = callbackUrl ? callbackUrl.replace(/'/g, "'\\''") : '';

    console.log(`[${new Date().toISOString()}] Call request:`);
    console.log(`  Phone: ${safeNumber}`);
    console.log(`  Script: ${script.substring(0, 100)}...`);
    console.log(`  Session: ${sessionId}`);
    console.log(`  Callback: ${callbackUrl || 'none'}`);

    // Store call metadata for the AGI script to read
    const callData = {
        sessionId,
        phoneNumber: safeNumber,
        script,
        callbackUrl: callbackUrl || '',
        startTime: new Date().toISOString(),
        conversation: []
    };

    try {
        fs.writeFileSync(
            path.join(CONVERSATION_DIR, `${sessionId}.json`),
            JSON.stringify(callData, null, 2)
        );
    } catch (e) {
        console.error('Failed to write call data:', e.message);
    }

    // Build Asterisk CLI command with channel variables
    const command = `sudo asterisk -rx "channel originate PJSIP/${safeNumber}@twilio-endpoint extension ${extension}@${context} Set(SCRIPT='${safeScript}') Set(SESSION_ID='${sessionId}') Set(CALLBACK_URL='${safeCallback}')"`;

    console.log(`Executing Asterisk command...`);

    exec(command, (error, stdout, stderr) => {
        if (error) {
            console.error(`Error: ${error.message}`);
            return res.status(500).json({ 
                error: 'Failed to initiate call', 
                details: error.message 
            });
        }

        console.log(`Success: Call initiated to ${safeNumber}`);
        res.json({ 
            message: 'Call initiated successfully', 
            phoneNumber: safeNumber,
            sessionId: sessionId,
            script: script,
            callbackUrl: callbackUrl || null,
            note: 'Conversation will be POSTed to callbackUrl when call ends'
        });
    });
});

// Get conversation transcript
app.get('/conversation/:sessionId', (req, res) => {
    const { sessionId } = req.params;
    const filePath = path.join(CONVERSATION_DIR, `${sessionId}.json`);

    try {
        if (fs.existsSync(filePath)) {
            const data = JSON.parse(fs.readFileSync(filePath, 'utf8'));
            res.json(data);
        } else {
            res.status(404).json({ error: 'Conversation not found' });
        }
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
});

// List active calls
app.get('/calls', (req, res) => {
    exec('sudo asterisk -rx "core show channels"', (error, stdout, stderr) => {
        if (error) {
            return res.status(500).json({ error: error.message });
        }
        res.json({ channels: stdout });
    });
});

// Hangup a specific channel
app.post('/hangup', (req, res) => {
    const { channel } = req.body;
    if (!channel) {
        return res.status(400).json({ error: 'channel is required' });
    }
    
    exec(`sudo asterisk -rx "channel request hangup ${channel}"`, (error, stdout, stderr) => {
        if (error) {
            return res.status(500).json({ error: error.message });
        }
        res.json({ message: 'Hangup requested', output: stdout });
    });
});

app.listen(port, '0.0.0.0', () => {
    console.log(`Asterisk Telephony API v3.0.0 listening at http://0.0.0.0:${port}`);
    console.log(`Conversation storage: ${CONVERSATION_DIR}`);
});
