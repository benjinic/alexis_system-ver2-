const { onRequest } = require('firebase-functions/v2/https');
const { onDocumentWritten } = require('firebase-functions/v2/firestore');
const { defineSecret } = require('firebase-functions/params');
const { initializeApp, getApps } = require('firebase-admin/app');
const { getAppCheck } = require('firebase-admin/app-check');
const { getAuth } = require('firebase-admin/auth');
const { FieldValue, getFirestore } = require('firebase-admin/firestore');
const axios = require('axios');

const GEMINI_MODEL = 'gemini-2.5-pro';
const GEMINI_RATE_LIMIT_PER_MINUTE = 20;
const DIAGNOSTIC_RATE_LIMIT_PER_MINUTE = 5;
const ORDER_ID_RATE_LIMIT_PER_MINUTE = 30;
const HTTP_REGION = 'us-central1';
const FIRESTORE_REGION = 'asia-east1';
const GEMINI_API_KEY = defineSecret('GEMINI_API_KEY');
const DEFAULT_ORDER_COUNTER = 14037;
const MONEY_PRECISION = 100;

if (!getApps().length) {
  initializeApp();
}

const db = getFirestore();

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

async function verifyAppCheck(req, res) {
  const appCheckToken = req.get('X-Firebase-AppCheck') || '';
  if (!appCheckToken) {
    res.status(401).json({ error: 'Missing Firebase App Check token.' });
    return null;
  }

  try {
    return await getAppCheck().verifyToken(appCheckToken);
  } catch (error) {
    res.status(401).json({ error: 'Invalid Firebase App Check token.' });
    return null;
  }
}

async function verifyRequest(req, res, { limitPerMinute, rateLimitName }) {
  const user = await verifyFirebaseUser(req, res);
  if (!user) return null;

  const app = await verifyAppCheck(req, res);
  if (!app) return null;

  const allowed = await consumeRateLimit({
    key: `${rateLimitName || 'request'}:${user.uid}`,
    limitPerMinute,
  });
  if (!allowed) {
    res.status(429).json({ error: 'Too many requests. Please try again later.' });
    return null;
  }

  return { user, app };
}

async function consumeRateLimit({ key, limitPerMinute }) {
  if (!limitPerMinute || limitPerMinute <= 0) return true;

  const now = Date.now();
  const windowMs = 60 * 1000;
  const windowId = Math.floor(now / windowMs);
  const safeKey = key.replace(/[^A-Za-z0-9_.:-]/g, '_');
  const ref = db
    .collection('_function_rate_limits')
    .doc(`${safeKey}:${windowId}`);

  return db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    const count = snapshot.exists ? snapshot.data().count || 0 : 0;
    if (count >= limitPerMinute) {
      return false;
    }

    transaction.set(
      ref,
      {
        count: count + 1,
        expiresAt: new Date((windowId + 2) * windowMs),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    return true;
  });
}

function toNumber(value, fallback = 0) {
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  if (typeof value === 'string') {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : fallback;
  }
  return fallback;
}

function roundMoney(value) {
  return Math.round(toNumber(value) * MONEY_PRECISION) / MONEY_PRECISION;
}

function valuesEqual(left, right) {
  if (typeof left === 'number' || typeof right === 'number') {
    return roundMoney(left) === roundMoney(right);
  }
  return left === right;
}

function changedFields(current, next) {
  const changes = {};
  Object.entries(next).forEach(([key, value]) => {
    if (!valuesEqual(current?.[key], value)) {
      changes[key] = value;
    }
  });
  return changes;
}

function itemRequiresFabric(item) {
  return Boolean(item.fabricId || item.fabricName) || toNumber(item.fabricUsed) > 0;
}

function allRequiredItemsOrdered(items) {
  const requiredItems = items.filter(itemRequiresFabric);
  return requiredItems.length > 0 && requiredItems.every((item) => item.isFabricOrdered === true);
}

async function getOrderItems(orderId) {
  const snapshot = await db
    .collection('order_items')
    .where('orderId', '==', orderId)
    .get();
  return snapshot.docs.map((doc) => ({ docId: doc.id, ...doc.data() }));
}

async function getServiceMap() {
  const snapshot = await db.collection('services').get();
  const map = new Map();
  snapshot.forEach((doc) => {
    const data = doc.data();
    if (data.name) {
      map.set(String(data.name), data);
    }
  });
  return map;
}

function resolveUnitPrice(item, serviceMap) {
  if (item.manualUnitPrice === true) {
    return toNumber(item.price);
  }
  const service = serviceMap.get(String(item.service || item.serviceName || ''));
  const servicePrice = toNumber(service?.price, 0);
  return servicePrice > 0 ? servicePrice : toNumber(item.price);
}

function calculateOrderDerivedFields(order, items, serviceMap) {
  const itemSummary = items
    .map((item) => String(item.service || item.serviceName || '').trim())
    .filter(Boolean)
    .join(', ');
  const fabricSummary = [...new Set(
    items
      .map((item) => String(item.fabricName || '').trim())
      .filter(Boolean)
  )].join(', ');

  const subtotal = items.length
    ? items.reduce(
        (sum, item) => sum + resolveUnitPrice(item, serviceMap) * toNumber(item.quantity, 1),
        0
      )
    : toNumber(order.subtotal);
  const discount = toNumber(order.discount);
  const total = Math.max(0, subtotal - discount);
  const materialCost = items.reduce((sum, item) => sum + toNumber(item.cost), 0);
  const outsourcingCost = items.reduce((sum, item) => {
    const service = serviceMap.get(String(item.service || item.serviceName || ''));
    return sum + toNumber(service?.outsourcingCost) * toNumber(item.quantity, 1);
  }, 0);
  const fixedCost = toNumber(order.fixedCost);
  const totalCost = materialCost + outsourcingCost + fixedCost;
  const balance = Math.max(
    0,
    total - (toNumber(order.deposit) + toNumber(order.balancePayment))
  );

  return {
    itemSummary: itemSummary.length > 50 ? `${itemSummary.substring(0, 47)}...` : itemSummary,
    fabricSummary,
    subtotal: roundMoney(subtotal),
    total: roundMoney(total),
    balance: roundMoney(balance),
    materialCost: roundMoney(materialCost),
    laborCost: 0,
    outsourcingCost: roundMoney(outsourcingCost),
    totalCost: roundMoney(totalCost),
    totalProfit: roundMoney(total - totalCost),
    isFabricOrdered: allRequiredItemsOrdered(items),
  };
}

async function syncOrderDerivedFields(orderId) {
  if (!orderId) return;

  const orderRef = db.collection('orders').doc(orderId);
  const orderSnapshot = await orderRef.get();
  if (!orderSnapshot.exists) return;

  const [items, serviceMap] = await Promise.all([
    getOrderItems(orderId),
    getServiceMap(),
  ]);
  const derived = calculateOrderDerivedFields(orderSnapshot.data(), items, serviceMap);
  const changes = changedFields(orderSnapshot.data(), derived);
  if (Object.keys(changes).length > 0) {
    await orderRef.set(
      {
        ...changes,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
  }

  const workshopSnapshot = await db
    .collection('workshop_orders')
    .where('orderId', '==', orderId)
    .get();
  if (!workshopSnapshot.empty) {
    const batch = db.batch();
    workshopSnapshot.forEach((doc) => {
      if (doc.data().isFabricOrdered !== derived.isFabricOrdered) {
        batch.update(doc.ref, {
          isFabricOrdered: derived.isFabricOrdered,
          updatedAt: FieldValue.serverTimestamp(),
        });
      }
    });
    if (workshopSnapshot.docs.some((doc) => doc.data().isFabricOrdered !== derived.isFabricOrdered)) {
      await batch.commit();
    }
  }
}

async function recomputeCustomerAggregate(customerId) {
  if (!customerId) return;

  const ordersSnapshot = await db
    .collection('orders')
    .where('customerId', '==', customerId)
    .get();

  let orderCount = 0;
  let totalSpent = 0;
  ordersSnapshot.forEach((doc) => {
    orderCount += 1;
    totalSpent += toNumber(doc.data().total);
  });

  const customerRef = db.collection('customers').doc(customerId);
  const customerSnapshot = await customerRef.get();
  if (!customerSnapshot.exists) return;

  const changes = changedFields(customerSnapshot.data(), {
    orders: orderCount,
    totalSpent: roundMoney(totalSpent),
  });
  if (Object.keys(changes).length > 0) {
    await customerRef.set(changes, { merge: true });
  }
}

exports.allocateOrderId = onRequest(
  { region: HTTP_REGION, cors: true },
  async (req, res) => {
    if (req.method === 'OPTIONS') {
      res.status(204).send('');
      return;
    }

    if (req.method !== 'POST') {
      res.status(405).json({ error: 'Method Not Allowed' });
      return;
    }

    const verified = await verifyRequest(req, res, {
      limitPerMinute: ORDER_ID_RATE_LIMIT_PER_MINUTE,
      rateLimitName: 'allocateOrderId',
    });
    if (!verified) return;

    const counterRef = db.collection('settings').doc('order_counter');
    const nextId = await db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(counterRef);
      const currentId = snapshot.exists
        ? toNumber(snapshot.data().current_id, DEFAULT_ORDER_COUNTER)
        : DEFAULT_ORDER_COUNTER;
      const id = currentId + 1;
      transaction.set(
        counterRef,
        {
          current_id: id,
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
      return id;
    });

    res.json({ orderId: nextId.toString() });
  }
);

exports.listGeminiModels = onRequest(
  { region: HTTP_REGION, cors: true, secrets: [GEMINI_API_KEY] },
  async (req, res) => {
    if (req.method === 'OPTIONS') {
      res.status(204).send('');
      return;
    }

    if (req.method !== 'GET') {
      res.status(405).json({ error: 'Method Not Allowed' });
      return;
    }

    const verified = await verifyRequest(req, res, {
      limitPerMinute: DIAGNOSTIC_RATE_LIMIT_PER_MINUTE,
      rateLimitName: 'listGeminiModels',
    });
    if (!verified) return;

    try {
      const response = await axios.get(
        `https://generativelanguage.googleapis.com/v1beta/models?key=${GEMINI_API_KEY.value()}&pageSize=50`
      );
      const models = (response.data.models || [])
        .filter((m) => (m.supportedGenerationMethods || []).includes('generateContent'))
        .map((m) => m.name);
      res.json({ models });
    } catch (error) {
      res.status(500).json({ error: error.response?.data || error.message });
    }
  }
);

exports.geminiProxy = onRequest(
  { region: HTTP_REGION, cors: true, secrets: [GEMINI_API_KEY] },
  async (req, res) => {
    if (req.method === 'OPTIONS') {
      res.status(204).send('');
      return;
    }

    if (req.method !== 'POST') {
      res.status(405).json({ error: 'Method Not Allowed' });
      return;
    }

    const verified = await verifyRequest(req, res, {
      limitPerMinute: GEMINI_RATE_LIMIT_PER_MINUTE,
      rateLimitName: 'geminiProxy',
    });
    if (!verified) return;

    if (!req.body || !Array.isArray(req.body.contents)) {
      res.status(400).json({ error: 'Invalid Gemini request body.' });
      return;
    }

    try {
      const response = await axios.post(
        `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${GEMINI_API_KEY.value()}`,
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

exports.syncOrderAggregates = onDocumentWritten(
  { region: FIRESTORE_REGION, document: 'orders/{orderId}' },
  async (event) => {
    const before = event.data?.before.exists ? event.data.before.data() : null;
    const after = event.data?.after.exists ? event.data.after.data() : null;
    const customerIds = new Set();

    if (before?.customerId) customerIds.add(before.customerId);
    if (after?.customerId) customerIds.add(after.customerId);

    await Promise.all([
      after ? syncOrderDerivedFields(event.params.orderId) : Promise.resolve(),
      ...[...customerIds].map((customerId) => recomputeCustomerAggregate(customerId)),
    ]);
  }
);

exports.syncOrderItemAggregates = onDocumentWritten(
  { region: FIRESTORE_REGION, document: 'order_items/{itemId}' },
  async (event) => {
    const before = event.data?.before.exists ? event.data.before.data() : null;
    const after = event.data?.after.exists ? event.data.after.data() : null;
    const orderIds = new Set();

    if (before?.orderId) orderIds.add(before.orderId);
    if (after?.orderId) orderIds.add(after.orderId);

    await Promise.all([...orderIds].map((orderId) => syncOrderDerivedFields(orderId)));
  }
);
