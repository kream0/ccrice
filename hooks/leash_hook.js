#!/usr/bin/env node
/**
 * Leash Hook - Sends Claude Code activity to the Leash server
 * Reads transcript file on Stop to capture assistant responses
 */

const http = require('http');
const fs = require('fs');

const LEASH_PORT = process.env.LEASH_PORT || '3001';

const HOSTS_TO_TRY = [
    'localhost',
    '127.0.0.1',
    process.env.LEASH_HOST,
    'host.docker.internal',
    '172.17.0.1',
].filter(Boolean);

async function tryHost(host, payload) {
    return new Promise((resolve) => {
        const options = {
            hostname: host,
            port: parseInt(LEASH_PORT),
            path: '/api/hooks',
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Content-Length': Buffer.byteLength(payload)
            },
            timeout: 1000
        };

        const req = http.request(options, (res) => {
            resolve({ success: true, host });
        });

        req.on('error', () => resolve({ success: false, host }));
        req.on('timeout', () => {
            req.destroy();
            resolve({ success: false, host });
        });

        req.write(payload);
        req.end();
    });
}

async function sendToLeash(agentId, eventType, data) {
    const payload = JSON.stringify({
        type: 'hook_event',
        eventType,
        agentId,
        timestamp: Date.now(),
        data
    });

    for (const host of HOSTS_TO_TRY) {
        const result = await tryHost(host, payload);
        if (result.success) {
            return true;
        }
    }
    return false;
}

/**
 * Read the last assistant message from transcript file
 */
function getLastAssistantMessage(transcriptPath) {
    if (!transcriptPath || !fs.existsSync(transcriptPath)) {
        return null;
    }

    try {
        const content = fs.readFileSync(transcriptPath, 'utf8');
        const lines = content.trim().split('\n').reverse();
        
        for (const line of lines) {
            try {
                const entry = JSON.parse(line);
                if (entry.type === 'assistant' && entry.message?.content) {
                    const textContent = entry.message.content
                        .filter(c => c.type === 'text')
                        .map(c => c.text)
                        .join('');
                    return textContent.substring(0, 200);
                }
            } catch (e) {
                continue;
            }
        }
    } catch (e) {
        // Ignore errors
    }
    return null;
}

async function main() {
    const hookType = process.argv[2] || 'unknown';
    let inputData = {};

    // Read JSON from stdin
    try {
        const chunks = [];
        process.stdin.setEncoding('utf8');

        await new Promise((resolve, reject) => {
            process.stdin.on('data', chunk => chunks.push(chunk));
            process.stdin.on('end', resolve);
            process.stdin.on('error', reject);
            setTimeout(resolve, 100);
        });

        if (chunks.length > 0) {
            const data = chunks.join('');
            if (data.trim()) {
                inputData = JSON.parse(data);
            }
        }
    } catch (e) {
        // No stdin or invalid JSON
    }

    const sessionId = inputData.session_id || 'unknown';
    const agentId = `claude-wsl-${sessionId.substring(0, 8)}`;

    // Always include transcript_path so server can read chat history
    const dataToSend = {
        ...inputData,
        transcript_path: inputData.transcript_path
    };

    // On Stop event, try to get the assistant's response from transcript
    if (hookType === 'Stop' && inputData.transcript_path) {
        const assistantMessage = getLastAssistantMessage(inputData.transcript_path);
        if (assistantMessage) {
            dataToSend.assistant_response = assistantMessage;
        }
    }

    await sendToLeash(agentId, hookType, dataToSend);
    process.exit(0);
}

main();
