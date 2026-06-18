#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

const DEFAULT_PROXY_URL = 'https://geminiproxy-iv4r7rb3ja-uc.a.run.app';
const PROXY_URL = process.env.GEMINI_PROXY_URL || process.argv[2] || DEFAULT_PROXY_URL;
const APP_CHECK_TOKEN = process.env.FIREBASE_APPCHECK_TOKEN || '';

function readWebApiKey() {
  if (process.env.FIREBASE_WEB_API_KEY) {
    return process.env.FIREBASE_WEB_API_KEY;
  }

  const firebaseOptionsPath = path.join(process.cwd(), 'lib', 'firebase_options.dart');
  const source = fs.readFileSync(firebaseOptionsPath, 'utf8');
  const webBlockMatch = source.match(/static const FirebaseOptions web = FirebaseOptions\(([\s\S]*?)\n\s*\);/);
  const block = webBlockMatch ? webBlockMatch[1] : source;
  const apiKeyMatch = block.match(/apiKey:\s*'([^']+)'/);

  if (!apiKeyMatch) {
    throw new Error('Cannot find Firebase web apiKey. Set FIREBASE_WEB_API_KEY and retry.');
  }

  return apiKeyMatch[1];
}

async function postJson(url, body, headers = {}) {
  const response = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      ...headers,
    },
    body: JSON.stringify(body),
  });

  const text = await response.text();
  let json = {};

  try {
    json = text ? JSON.parse(text) : {};
  } catch (_) {
    json = { raw: text };
  }

  return { response, json };
}

async function createAnonymousUser(apiKey) {
  const { response, json } = await postJson(
    `https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${apiKey}`,
    { returnSecureToken: true }
  );

  if (!response.ok) {
    throw new Error(
      `Anonymous Firebase Auth sign-up failed ${response.status}. Check that Anonymous sign-in is enabled.`
    );
  }

  return json;
}

async function deleteAnonymousUser(apiKey, idToken) {
  if (!idToken) return;

  await postJson(
    `https://identitytoolkit.googleapis.com/v1/accounts:delete?key=${apiKey}`,
    { idToken }
  ).catch(() => {});
}

function candidateText(body) {
  return body?.candidates?.[0]?.content?.parts
    ?.map((part) => part.text || '')
    .join('')
    .trim() || '';
}

async function main() {
  const apiKey = readWebApiKey();

  const unauthorized = await postJson(PROXY_URL, { contents: [] });
  const unauthOk = unauthorized.response.status === 401;

  const user = await createAnonymousUser(apiKey);

  try {
    const authorized = await postJson(
      PROXY_URL,
      {
        contents: [{ role: 'user', parts: [{ text: 'Answer with exactly: OK' }] }],
        generationConfig: { maxOutputTokens: 1024, temperature: 0 },
      },
      {
        Authorization: `Bearer ${user.idToken}`,
        ...(APP_CHECK_TOKEN ? { 'X-Firebase-AppCheck': APP_CHECK_TOKEN } : {}),
      }
    );

    const text = candidateText(authorized.json);
    const authOk = authorized.response.status === 200 && Boolean(text);

    const result = {
      proxyUrl: PROXY_URL,
      ok: unauthOk && authOk,
      unauthorized: {
        expectedStatus: 401,
        status: unauthorized.response.status,
      },
      authorized: {
        expectedStatus: 200,
        status: authorized.response.status,
        candidateCount: authorized.json?.candidates?.length || 0,
        finishReason: authorized.json?.candidates?.[0]?.finishReason || null,
        hasText: Boolean(text),
        appCheckHeaderSent: Boolean(APP_CHECK_TOKEN),
        preview: text.slice(0, 40),
      },
    };

    console.log(JSON.stringify(result, null, 2));

    if (!result.ok) {
      process.exitCode = 1;
    }
  } finally {
    await deleteAnonymousUser(apiKey, user.idToken);
  }
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
