#!/usr/bin/env node
// 唯讀掃描 Firestore 各 collection 嘅重覆資料，唔會寫入或刪除任何文件。
//
// 用法（喺 repo 根目錄）：
//   gcloud auth application-default login
//   NODE_PATH=functions/node_modules node tool/audit_firestore_duplicates.js [projectId]
//
// 需要先喺 functions/ 執行 npm install（用佢嘅 firebase-admin）。

const { initializeApp, applicationDefault } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');

const DEFAULT_PROJECT_ID = 'alexis-tailor-system-2025';
const PROJECT_ID = process.env.FIREBASE_PROJECT_ID || process.argv[2] || DEFAULT_PROJECT_ID;

// 同一客戶、同一金額、相隔少於呢個時間嘅訂單，視為可能重覆提交。
const ORDER_DOUBLE_SUBMIT_WINDOW_MS = 5 * 60 * 1000;

initializeApp({ credential: applicationDefault(), projectId: PROJECT_ID });
const db = getFirestore();

function norm(value) {
  return (value ?? '').toString().trim().replace(/\s+/g, ' ').toUpperCase();
}

function normPhone(value) {
  return (value ?? '').toString().replace(/[^\d+]/g, '');
}

function toMillis(value) {
  if (value == null) return null;
  if (typeof value.toMillis === 'function') return value.toMillis();
  if (typeof value === 'number') return value;
  const parsed = Date.parse(value);
  return Number.isNaN(parsed) ? null : parsed;
}

// 按 keyFn 分組，只回傳多過一份嘅組。keyFn 回傳空值就跳過。
function groupDuplicates(docs, keyFn) {
  const groups = new Map();
  for (const doc of docs) {
    const key = keyFn(doc.data(), doc);
    if (!key) continue;
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(doc);
  }
  return [...groups.entries()].filter(([, list]) => list.length > 1);
}

function report(title, groups, describe = (doc) => doc.id) {
  console.log(`\n## ${title}: ${groups.length} 組`);
  for (const [key, list] of groups.slice(0, 50)) {
    console.log(`  - ${key}  (${list.length} 份)`);
    for (const doc of list) console.log(`      ${describe(doc)}`);
  }
  if (groups.length > 50) console.log(`  ... 仲有 ${groups.length - 50} 組未列出`);
}

async function load(name) {
  const snapshot = await db.collection(name).get();
  console.log(`${name}: ${snapshot.size} 份文件`);
  return snapshot.docs;
}

async function main() {
  console.log(`Project: ${PROJECT_ID}\n`);
  const [customers, inventory, services, orders, orderItems, workshop, images, bespoke] =
    await Promise.all([
      load('customers'),
      load('inventory'),
      load('services'),
      load('orders'),
      load('order_items'),
      load('workshop_orders'),
      load('order_images'),
      load('bespoke_orders'),
    ]);

  const orderIds = new Set(orders.map((d) => d.id));
  const ordersByCustomer = new Map();
  for (const doc of orders) {
    const customerId = doc.get('customerId');
    if (customerId) ordersByCustomer.set(customerId, (ordersByCustomer.get(customerId) || 0) + 1);
  }
  const describeCustomer = (doc) =>
    `${doc.id}  name=${doc.get('name')}  phone=${doc.get('phone') || '-'}  訂單=${ordersByCustomer.get(doc.id) || 0}`;

  report('customers 同名', groupDuplicates(customers, (d) => norm(d.name)), describeCustomer);
  report('customers 同電話', groupDuplicates(customers, (d) => normPhone(d.phone)), describeCustomer);

  report('inventory 同名布料', groupDuplicates(inventory, (d) => norm(d.name)),
    (doc) => `${doc.id}  name=${doc.get('name')}  stock=${doc.get('stock')}`);

  report('services 同名服務（Cloud Functions 用名稱對應成本，同名會互相覆蓋）',
    groupDuplicates(services, (d) => norm(d.name)),
    (doc) => `${doc.id}  price=${doc.get('price')}  outsourcingCost=${doc.get('outsourcingCost')}`);

  report('orders 同 uniqueId', groupDuplicates(orders, (d) => d.uniqueId));

  // 疑似重覆提交：同客戶、同金額、時間好接近。
  const doubleSubmits = [];
  for (const [key, list] of groupDuplicates(orders, (d) => d.customerId && `${d.customerId}|${d.total}`)) {
    const sorted = list
      .map((doc) => ({ doc, at: toMillis(doc.get('createdAt')) }))
      .filter((x) => x.at != null)
      .sort((a, b) => a.at - b.at);
    for (let i = 1; i < sorted.length; i++) {
      if (sorted[i].at - sorted[i - 1].at <= ORDER_DOUBLE_SUBMIT_WINDOW_MS) {
        doubleSubmits.push([key, [sorted[i - 1].doc, sorted[i].doc]]);
      }
    }
  }
  report('orders 疑似重覆提交（同客戶同金額，相隔 ≤ 5 分鐘）', doubleSubmits,
    (doc) => `${doc.id}  ${doc.get('customerName')}  createdAt=${new Date(toMillis(doc.get('createdAt'))).toISOString()}`);

  report('order_items 同一訂單內同一 item id',
    groupDuplicates(orderItems, (d) => d.orderId && d.id && `${d.orderId}|${d.id}`),
    (doc) => `${doc.id}  service=${doc.get('service')}`);
  const orphanItems = orderItems.filter((d) => !orderIds.has((d.get('orderId') || '').toString()));
  console.log(`\n## order_items 孤立（訂單已唔存在）: ${orphanItems.length} 份`);

  report('workshop_orders 同訂單同項目（同一張單有兩件一樣嘅貨屬正常）',
    groupDuplicates(workshop, (d) => d.orderId && `${d.orderId}|${norm(d.item)}`),
    (doc) => `${doc.id}  status=${doc.get('status')}`);

  report('order_images 同訂單同檔案',
    groupDuplicates(images, (d) => d.orderId && `${d.orderId}|${d.imageUrl || d.fileName}`));

  report('bespoke_orders 匯入咗同一張 POS 單', groupDuplicates(bespoke, (d) => d.posOrderId));

  console.log('\n完成（只讀，冇修改任何資料）。');
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
