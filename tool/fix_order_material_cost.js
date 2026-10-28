#!/usr/bin/env node
// 將訂單 materialCost 修正為細項逐項計（每件 cost × 數量）嘅總和。
// 主要針對之前 Cloud Function 冇乘數量而少計嘅單，亦會補返從未計過布料成本嘅單。
// 只處理已經有 materialCost 欄位（即係系統計過）嘅訂單；舊匯入資料冇呢個欄位，唔會掂。
// 只調整布料成本嘅差額，外判成本保持原樣，避免順便用今日價錢重新定價。
//
// 用法（喺 repo 根目錄，先喺 functions/ 執行 npm install）：
//   gcloud auth application-default login
//   NODE_PATH=functions/node_modules node tool/fix_order_material_cost.js           # 只列出改動
//   NODE_PATH=functions/node_modules node tool/fix_order_material_cost.js --apply   # 寫入

const DEFAULT_PROJECT_ID = 'alexis-tailor-system-2025';
const BATCH_LIMIT = 400;

function toNumber(value, fallback = 0) {
  const number = typeof value === 'number' ? value : Number(value);
  return Number.isFinite(number) ? number : fallback;
}

function roundMoney(value) {
  return Math.round(value * 100) / 100;
}

// order: orders 文件資料；items: 該訂單嘅 order_items 資料。冇需要改就回傳 null。
function calculateFix(order, items) {
  if (typeof order.materialCost !== 'number' || items.length === 0) return null;

  const materialCost = roundMoney(
    items.reduce((sum, item) => sum + toNumber(item.cost) * toNumber(item.quantity, 1), 0)
  );
  const delta = roundMoney(materialCost - order.materialCost);
  if (Math.abs(delta) < 0.01) return null;

  const totalCost = roundMoney(toNumber(order.totalCost) + delta);
  return {
    materialCost,
    totalCost,
    totalProfit: roundMoney(toNumber(order.total) - totalCost),
  };
}

async function main() {
  const { initializeApp, applicationDefault } = require('firebase-admin/app');
  const { FieldValue, getFirestore } = require('firebase-admin/firestore');

  const apply = process.argv.includes('--apply');
  const projectId =
    process.env.FIREBASE_PROJECT_ID ||
    process.argv.slice(2).find((arg) => !arg.startsWith('--')) ||
    DEFAULT_PROJECT_ID;

  initializeApp({ credential: applicationDefault(), projectId });
  const db = getFirestore();

  const [ordersSnapshot, itemsSnapshot] = await Promise.all([
    db.collection('orders').get(),
    db.collection('order_items').get(),
  ]);

  const itemsByOrder = new Map();
  for (const doc of itemsSnapshot.docs) {
    const orderId = String(doc.get('orderId') || '');
    if (!itemsByOrder.has(orderId)) itemsByOrder.set(orderId, []);
    itemsByOrder.get(orderId).push(doc.data());
  }

  const fixes = [];
  for (const doc of ordersSnapshot.docs) {
    const order = doc.data();
    const fix = calculateFix(order, itemsByOrder.get(doc.id) || []);
    if (fix) fixes.push({ ref: doc.ref, id: doc.id, order, fix });
  }

  console.log(`Project: ${projectId}`);
  console.log(`需要修正：${fixes.length} 張訂單\n`);
  let totalDelta = 0;
  for (const { id, order, fix } of fixes) {
    const delta = fix.materialCost - order.materialCost;
    totalDelta += delta;
    console.log(
      `${id}  ${order.customerName || ''}  布料成本 ${order.materialCost} → ${fix.materialCost}` +
        `  總成本 ${order.totalCost} → ${fix.totalCost}  利潤 ${order.totalProfit} → ${fix.totalProfit}`
    );
  }
  console.log(`\n布料成本合共調整：${roundMoney(totalDelta)}`);

  if (!apply) {
    console.log('\n只係預覽，未寫入。確認冇問題再加 --apply 執行。');
    return;
  }

  for (let i = 0; i < fixes.length; i += BATCH_LIMIT) {
    const batch = db.batch();
    for (const { ref, fix } of fixes.slice(i, i + BATCH_LIMIT)) {
      batch.update(ref, { ...fix, updatedAt: FieldValue.serverTimestamp() });
    }
    await batch.commit();
  }
  console.log(`\n已更新 ${fixes.length} 張訂單。`);
}

if (require.main === module) {
  main().catch((error) => {
    console.error(error);
    process.exit(1);
  });
}

module.exports = { calculateFix };
