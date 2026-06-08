#!/usr/bin/env node

const DEFAULT_PROJECT_ID = 'alexis-tailor-system-2025';
const PROJECT_ID = process.env.FIREBASE_PROJECT_ID || process.argv[2] || DEFAULT_PROJECT_ID;

const SENSITIVE_KEY_PATTERN = /PRIVATE|SECRET|TOKEN|PASSWORD|CREDENTIAL|GEMINI_API_KEY/i;
const PUBLIC_ENV_ALLOWLIST = new Set([
  'NEXT_PUBLIC_FIREBASE_API_KEY',
]);

const EXPECTED_SECRET_ENVS = new Map([
  ['geminiProxy', new Set(['GEMINI_API_KEY'])],
  ['listGeminiModels', new Set(['GEMINI_API_KEY'])],
  ['ssralexisbespoke', new Set(['ALEXIS_PRIVATE_KEY'])],
  ['ssralexistailorsystem20', new Set(['ALEXIS_PRIVATE_KEY'])],
]);

function loadFirebaseAuth() {
  const candidates = [
    'firebase-tools/lib/auth',
    '/usr/local/lib/node_modules/firebase-tools/lib/auth',
    '/opt/homebrew/lib/node_modules/firebase-tools/lib/auth',
  ];

  for (const candidate of candidates) {
    try {
      return require(candidate);
    } catch (_) {
      // Try the next common Firebase CLI install location.
    }
  }

  throw new Error(
    'Cannot load Firebase CLI auth helpers. Install firebase-tools or run this on a machine with Firebase CLI configured.'
  );
}

function getAccessToken() {
  const auth = loadFirebaseAuth();
  const account = auth.getProjectDefaultAccount(PROJECT_ID) || auth.getGlobalDefaultAccount();
  const token = account?.tokens?.access_token;

  if (!token) {
    throw new Error('No Firebase CLI access token found. Run `firebase login --reauth` first.');
  }

  return token;
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function getJson(url, token) {
  let lastError;

  for (let attempt = 1; attempt <= 3; attempt += 1) {
    const response = await fetch(url, {
      headers: { Authorization: `Bearer ${token}` },
    });
    const text = await response.text();

    if (response.ok) {
      return text ? JSON.parse(text) : {};
    }

    lastError = `${url} failed ${response.status}: ${text.slice(0, 200)}`;

    if (![429, 500, 502, 503, 504].includes(response.status) || attempt === 3) {
      break;
    }

    await sleep(1000 * attempt);
  }

  throw new Error(lastError);
}

function functionName(resourceName) {
  return resourceName.split('/').pop();
}

function region(resourceName) {
  return resourceName.split('/locations/')[1]?.split('/')[0] || '';
}

function plainSensitiveKeys(env = {}) {
  return Object.keys(env)
    .filter((key) => SENSITIVE_KEY_PATTERN.test(key))
    .filter((key) => !PUBLIC_ENV_ALLOWLIST.has(key));
}

function secretKeys(secretEnv = []) {
  return secretEnv.map((secret) => `${secret.key}@${secret.version || 'latest'}`);
}

function missingExpectedSecrets(name, secretEnv = []) {
  const expected = EXPECTED_SECRET_ENVS.get(name);
  if (!expected) return [];

  const actual = new Set(secretEnv.map((secret) => secret.key));
  return [...expected].filter((key) => !actual.has(key));
}

async function main() {
  const token = getAccessToken();
  const v2Url = `https://cloudfunctions.googleapis.com/v2/projects/${PROJECT_ID}/locations/-/functions?filter=environment%3D%22GEN_2%22`;
  const v1Url = `https://cloudfunctions.googleapis.com/v1/projects/${PROJECT_ID}/locations/-/functions`;

  const [v2, v1] = await Promise.all([
    getJson(v2Url, token),
    getJson(v1Url, token),
  ]);

  const rows = [];

  for (const fn of v2.functions || []) {
    const name = functionName(fn.name);
    const env = fn.serviceConfig?.environmentVariables || {};
    const secretEnv = fn.serviceConfig?.secretEnvironmentVariables || [];

    rows.push({
      name,
      version: 'v2',
      region: region(fn.name),
      runtime: fn.buildConfig?.runtime || '',
      state: fn.state || '',
      plainSensitiveEnvKeys: plainSensitiveKeys(env),
      secretEnvKeys: secretKeys(secretEnv),
      missingExpectedSecretEnvKeys: missingExpectedSecrets(name, secretEnv),
    });
  }

  for (const fn of v1.functions || []) {
    const env = fn.environmentVariables || {};
    rows.push({
      name: functionName(fn.name),
      version: 'v1',
      region: region(fn.name),
      runtime: fn.runtime || '',
      state: fn.status || '',
      plainSensitiveEnvKeys: plainSensitiveKeys(env),
      secretEnvKeys: [],
      missingExpectedSecretEnvKeys: [],
    });
  }

  const failures = rows.filter(
    (row) => row.plainSensitiveEnvKeys.length || row.missingExpectedSecretEnvKeys.length
  );

  console.log(JSON.stringify({
    projectId: PROJECT_ID,
    checkedFunctions: rows.length,
    ok: failures.length === 0,
    functions: rows,
  }, null, 2));

  if (failures.length) {
    process.exitCode = 1;
  }
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
