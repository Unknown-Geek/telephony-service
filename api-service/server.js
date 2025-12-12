const express = require('express');
const bodyParser = require('body-parser');
const { exec } = require('child_process');
const app = express();
const port = 3030;

app.use(bodyParser.json());

// Endpoint to initiate an outbound call
app.get('/', (req, res) => {
    res.send('Asterisk Trigger API is running');
});

app.post('/call', (req, res) => {
    const { phoneNumber, context = 'outbound-ai-test', extension = 's' } = req.body;

    if (!phoneNumber) {
        return res.status(400).json({ error: 'phoneNumber is required' });
    }

    console.log(`Received request to call ${phoneNumber} using context ${context}`);

    // Construct the Asterisk CLI command for channel originate
    // We use Local channel to ensure dialplan processing or PJSIP directly
    // Using PJSIP directly for simplicity in targeting Twilio
    // IMPORTANT: Ensure Caller ID logic is handled or passed
    // NOTE: The dialplan context 'outbound-ai-test' needs to exist to handle the answered call
    // For now, let's dial via PJSIP and connect to a simple Playback application or a Context
    
    // Command: channel originate PJSIP/<number>@twilio-endpoint extension s@<context>
    // We need to pass the Caller ID! We can do this in the originate command often, or ensure pjsip.conf handles it.
    // pjsip.conf has from_user=+17756187988 so it should be fine universally.

    // Sanitize input roughly
    const safeNumber = phoneNumber.replace(/[^0-9+]/g, '');
    
    const command = `sudo asterisk -rx "channel originate PJSIP/${safeNumber}@twilio-endpoint extension ${extension}@${context}"`;

    console.log(`Executing: ${command}`);

    exec(command, (error, stdout, stderr) => {
        if (error) {
            console.error(`Error: ${error.message}`);
            return res.status(500).json({ error: 'Failed to initiate call', details: error.message });
        }
        if (stderr) {
            console.error(`Stderr: ${stderr}`);
        }
        console.log(`Stdout: ${stdout}`);
        res.json({ message: 'Call initiated successfully', output: stdout });
    });
});

app.listen(port, () => {
    console.log(`Asterisk Trigger API listening at http://localhost:${port}`);
});
