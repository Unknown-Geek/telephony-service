const express = require('express');
const bodyParser = require('body-parser');
const { exec } = require('child_process');
const app = express();
const port = process.env.PORT || 3030;

// Asterisk host - use host.docker.internal in Docker, localhost otherwise
const ASTERISK_HOST = process.env.ASTERISK_HOST || 'localhost';

app.use(bodyParser.json());

// Health check
app.get('/', (req, res) => {
    res.json({ 
        status: 'running',
        service: 'Asterisk Trigger API',
        version: '2.0.0'
    });
});

app.get('/health', (req, res) => {
    res.json({ status: 'ok' });
});

// Trigger an outbound call
app.post('/call', (req, res) => {
    const { 
        phoneNumber, 
        context = 'outbound-ai-conversational', 
        extension = 's',
        callerId = '+17756187988'
    } = req.body;

    if (!phoneNumber) {
        return res.status(400).json({ error: 'phoneNumber is required' });
    }

    console.log(`[${new Date().toISOString()}] Call request: ${phoneNumber} -> ${context}`);

    // Sanitize phone number
    const safeNumber = phoneNumber.replace(/[^0-9+]/g, '');
    
    // Build Asterisk CLI command
    // When running in Docker, we need to connect to Asterisk differently
    let command;
    if (ASTERISK_HOST === 'localhost' || ASTERISK_HOST === '127.0.0.1') {
        command = `sudo asterisk -rx "channel originate PJSIP/${safeNumber}@twilio-endpoint extension ${extension}@${context}"`;
    } else {
        // When in Docker, use SSH or Asterisk Manager Interface (AMI)
        // For now, assume Asterisk is on host network
        command = `ssh ${ASTERISK_HOST} 'sudo asterisk -rx "channel originate PJSIP/${safeNumber}@twilio-endpoint extension ${extension}@${context}"'`;
    }

    console.log(`Executing: ${command}`);

    exec(command, (error, stdout, stderr) => {
        if (error) {
            console.error(`Error: ${error.message}`);
            return res.status(500).json({ 
                error: 'Failed to initiate call', 
                details: error.message 
            });
        }
        if (stderr) {
            console.error(`Stderr: ${stderr}`);
        }
        console.log(`Success: Call initiated to ${safeNumber}`);
        res.json({ 
            message: 'Call initiated successfully', 
            phoneNumber: safeNumber,
            context: context,
            output: stdout 
        });
    });
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
    console.log(`Asterisk Trigger API listening at http://0.0.0.0:${port}`);
    console.log(`Asterisk Host: ${ASTERISK_HOST}`);
});
