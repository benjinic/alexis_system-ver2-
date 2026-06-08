const { onRequest } = require('firebase-functions/v2/https');
const { defineSecret } = require('firebase-functions/params');
const { initializeApp, getApps } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const axios = require('axios');

const GEMINI_MODEL = "gemini-2.5-pro";
const geminiApiKey = defineSecret('GEMINI_API_KEY');

if (!getApps().length) {
  initializeApp();
}

async function verifyFirebaseUser(req, res) {
  const authHeader = req.get('Authorization') || '';
  const match = authHeader.match(/^Bearer (.+)$/);
  if (!match) {
    res.status(401).json({ error: 'Missing Firebase ID token.' });
    return null;
  }

  try {
    return await getAuth().verifyIdToken(match[1]);
  } catch (error) {
    res.status(401).json({ error: 'Invalid Firebase ID token.' });
    return null;
  }
}

exports.listGeminiModels = onRequest(
  { region: 'us-central1', cors: true, secrets: [geminiApiKey] },
  async (req, res) => {
    if (req.method !== 'GET') {
      res.status(405).json({ error: 'Method Not Allowed' });
      return;
    }

    const user = await verifyFirebaseUser(req, res);
    if (!user) return;

    try {
      const response = await axios.get(
        `https://generativelanguage.googleapis.com/v1beta/models?key=${geminiApiKey.value()}&pageSize=50`
      );
      const models = (response.data.models || [])
        .filter(m => (m.supportedGenerationMethods || []).includes('generateContent'))
        .map(m => m.name);
      res.json({ models });
    } catch (error) {
      res.status(500).json({ error: error.response?.data || error.message });
    }
  }
);

exports.geminiProxy = onRequest(
  { region: 'us-central1', cors: true, secrets: [geminiApiKey] },
  async (req, res) => {
    if (req.method !== 'POST') {
      res.status(405).json({ error: 'Method Not Allowed' });
      return;
    }

    const user = await verifyFirebaseUser(req, res);
    if (!user) return;

    if (!req.body || !Array.isArray(req.body.contents)) {
      res.status(400).json({ error: 'Invalid Gemini request body.' });
      return;
    }

    try {
      const response = await axios.post(
        `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${geminiApiKey.value()}`,
        req.body,
        { headers: { 'Content-Type': 'application/json' } }
      );
      res.json(response.data);
    } catch (error) {
      const status = error.response?.status || 500;
      const data = error.response?.data || { error: error.message };
      res.status(status).json(data);
    }
  }
);
