import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../models/order.dart';
import '../models/workshop_order.dart';

class PdfService {
  // === 1. 收據列印 (保持原本設計) ===
  Future<void> printReceipt(BuildContext context, Order order) async {
    await _printDocument(
      context,
      name: 'Receipt_${order.id}',
      format: PdfPageFormat.roll80,
      builder: (font, boldFont) => _buildReceiptLayout(order, font, boldFont),
    );
  }

  // === 2. 工單列印 (雅思洋服 A4 格式) ===
  Future<void> printWorkshopOrder(
    BuildContext context,
    WorkshopOrder order,
  ) async {
    await _printDocument(
      context,
      name: 'Job_${order.customer}_${order.item}',
      format: PdfPageFormat.a4,
      builder: (font, boldFont) => _buildJobTicketLayout(order, font, boldFont),
    );
  }

  // --- 通用列印流程 ---
  Future<void> _printDocument(
    BuildContext context, {
    required String name,
    required PdfPageFormat format,
    required pw.Widget Function(pw.Font font, pw.Font boldFont) builder,
  }) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Dialog(
        backgroundColor: Colors.white,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text("Generating Document..."),
            ],
          ),
        ),
      ),
    );

    try {
      final font = await PdfGoogleFonts.notoSansTCRegular();
      final boldFont = await PdfGoogleFonts.notoSansTCBold();

      final doc = pw.Document();

      doc.addPage(
        pw.Page(
          pageFormat: format,
          theme: pw.ThemeData.withFont(base: font, bold: boldFont),
          margin: const pw.EdgeInsets.all(20), // A4 邊距
          build: (pw.Context context) {
            return builder(font, boldFont);
          },
        ),
      );

      if (context.mounted) {
        Navigator.of(context).pop();
      }

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => doc.save(),
        name: name,
      );
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  // =========================================================
  //  STYLE 1: ALEXIS BESPOKE 收據排版 (保持不變)
  // =========================================================
  pw.Widget _buildReceiptLayout(Order order, pw.Font font, pw.Font boldFont) {
    final dateFormat = DateFormat('MMM dd, yyyy, hh:mm a');
    final dashedDivider = pw.Container(
      margin: const pw.EdgeInsets.symmetric(vertical: 5),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(width: 0.5, style: pw.BorderStyle.dashed),
        ),
      ),
    );

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Center(
          child: pw.Column(
            children: [
              pw.Text(
                'ALEXIS BESPOKE',
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
              pw.SizedBox(height: 5),
              pw.Text(
                'Room 602, 6F, Wing Fu Building,',
                style: const pw.TextStyle(
                  fontSize: 8,
                  color: PdfColors.grey700,
                ),
              ),
              pw.Text(
                '18-24 Wing Kut Street, Central, Hong Kong',
                style: const pw.TextStyle(
                  fontSize: 8,
                  color: PdfColors.grey700,
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 15),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(vertical: 8),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.black, width: 2),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
          ),
          child: pw.Column(
            children: [
              pw.Text(
                'TOTAL',
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                '\$${order.total.toStringAsFixed(2)}',
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 10),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Items',
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              'Price',
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
            ),
          ],
        ),
        pw.Container(
          margin: const pw.EdgeInsets.only(top: 2, bottom: 5),
          height: 1,
          color: PdfColors.black,
        ),
        ...order.items.map((item) {
          return pw.Column(
            children: [
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    flex: 7,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          item.service,
                          style: const pw.TextStyle(fontSize: 10),
                        ),
                        if (item.fabricName != null)
                          pw.Text(
                            'Mat: ${item.fabricName} / Code: ${item.fabricId ?? "-"}',
                            style: const pw.TextStyle(
                              fontSize: 8,
                              color: PdfColors.grey700,
                            ),
                          ),
                        pw.Text(
                          '(${item.quantity.toInt()} x \$${item.price.toStringAsFixed(2)})',
                          style: const pw.TextStyle(
                            fontSize: 8,
                            color: PdfColors.grey700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  pw.Expanded(
                    flex: 3,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(
                          '\$${(item.price * item.quantity).toStringAsFixed(2)}',
                          style: pw.TextStyle(
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              dashedDivider,
            ],
          );
        }),
        pw.SizedBox(height: 5),
        _buildSpreadRow('SUBTOTAL', '\$${order.subtotal.toStringAsFixed(2)}'),
        _buildSpreadRow('TOTAL', '\$${order.total.toStringAsFixed(2)}'),
        _buildSpreadRow('TOTAL ITEMS', '${order.items.length}'),
        dashedDivider,
        if (order.deposit > 0)
          _buildSpreadRow(
            'Deposit (${order.paymentMethod})',
            '\$${order.deposit.toStringAsFixed(2)}',
          ),
        if (order.balancePayment > 0) ...[
          _buildSpreadRow(
            'Balance Payment',
            '\$${order.balancePayment.toStringAsFixed(2)}',
          ),
          if (order.balancePaidDate != null)
            _buildSpreadRow(
              'Balance Pmt Date',
              DateFormat('yyyy-MM-dd').format(order.balancePaidDate!),
            ),
        ],
        _buildSpreadRow('Balance Due', '\$${order.balance.toStringAsFixed(2)}'),
        dashedDivider,
        pw.SizedBox(height: 10),
        pw.Text(
          'Order Note:',
          style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
        ),
        pw.Text(order.id, style: const pw.TextStyle(fontSize: 9)),
        pw.SizedBox(height: 10),
        pw.Center(
          child: pw.Column(
            children: [
              pw.Text(
                'Sold to: ${order.customerName}',
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              if (order.createdAt != null)
                pw.Text(
                  dateFormat.format(order.createdAt!),
                  style: const pw.TextStyle(fontSize: 9),
                ),
              pw.Text(
                'Receipt: #${order.id}',
                style: const pw.TextStyle(fontSize: 9),
              ),
              pw.SizedBox(height: 5),
              pw.Text(
                'NO EXCHANGE NO REFUND',
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 15),
        pw.Center(
          child: pw.Text(
            'Thank you for shopping with Alexis Bespoke! We look forward to serving you again.',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              fontStyle: pw.FontStyle.italic,
              color: PdfColors.grey800,
            ),
          ),
        ),
        pw.SizedBox(height: 5),
        pw.Text(
          'Products are not eligible for any aftersales services. The customer confirms that all items have been inspected and received in good condition. The customer acknowledges and accepts that all purchases are final.',
          textAlign: pw.TextAlign.justify,
          style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
        ),
        pw.SizedBox(height: 25),
        pw.Container(
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide()),
          ),
          height: 20,
        ),
        pw.Center(
          child: pw.Text('Signature', style: const pw.TextStyle(fontSize: 8)),
        ),
      ],
    );
  }

  pw.Widget _buildSpreadRow(String left, String right) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            left,
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(
            right,
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          ),
        ],
      ),
    );
  }

  // =========================================================
  //  STYLE 2: 雅思洋服 A4 工單格式 (更新版 - 微調間距與字體)
  // =========================================================
  pw.Widget _buildJobTicketLayout(
    WorkshopOrder order,
    pw.Font font,
    pw.Font boldFont,
  ) {
    final dateFormat = DateFormat('yyyy-MM-dd');
    final borderStyle = pw.Border.all(color: PdfColors.black, width: 1);

    return pw.Container(
      decoration: pw.BoxDecoration(border: borderStyle),
      padding: const pw.EdgeInsets.all(10),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // 1. 頂部資訊 (Header)
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    '雅思洋服',
                    style: pw.TextStyle(
                      font: boldFont,
                      fontSize: 28,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    'ALEXIS BESPOKE',
                    style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    '中環永吉街24號永富大廈601室',
                    style: pw.TextStyle(font: font, fontSize: 10),
                  ),
                  pw.Text(
                    'Room 601, Wing Fu Bldg, 24 Wing Kut St, Central, HK',
                    style: pw.TextStyle(font: font, fontSize: 9),
                  ),
                ],
              ),
              pw.Container(
                width: 180,
                child: pw.Table(
                  border: pw.TableBorder.all(width: 1),
                  children: [
                    _buildTableRow(['單號 No.', order.orderId], boldFont),
                    _buildTableRow(['日期 Date', order.createdAt != null ? dateFormat.format(order.createdAt!) : ''], font),
                    _buildTableRow(['剪單 Cutter', ''], font),
                  ],
                ),
              ),
            ],
          ),
          
          pw.SizedBox(height: 15),

          // 2. 客戶資料欄
          pw.Container(
            decoration: pw.BoxDecoration(border: borderStyle),
            child: pw.Row(
              children: [
                _buildInfoCell('客人名稱 Name', order.customer, flex: 3, font: boldFont),
                _buildInfoCell('電話 Tel', '', flex: 2, font: font),
                _buildInfoCell('試身/交貨日期', dateFormat.format(order.dueDate), flex: 3, font: boldFont),
              ],
            ),
          ),

          pw.SizedBox(height: 10),

          // 3. 主體內容：左右分欄
          pw.Expanded(
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // 左側：尺寸測量區
                pw.Container(
                  width: 160,
                  margin: const pw.EdgeInsets.only(right: 10),
                  decoration: pw.BoxDecoration(border: borderStyle),
                  child: pw.Column(
                    children: [
                      _buildMeasurementRow('胸圍 Chest', ''),
                      _buildMeasurementRow('腰圍 Waist', ''),
                      _buildMeasurementRow('肚圍 Stomach', ''),
                      _buildMeasurementRow('坐圍 Hip', ''),
                      _buildMeasurementRow('肩寬 Shoulder', ''),
                      _buildMeasurementRow('背寬 Back', ''),
                      _buildMeasurementRow('後長 Length', ''),
                      _buildMeasurementRow('前長 F.Length', ''),
                      pw.Divider(height: 1, thickness: 1),
                      _buildMeasurementRow('袖長 Sleeve (L)', ''),
                      _buildMeasurementRow('袖長 Sleeve (R)', ''),
                      _buildMeasurementRow('袖口 Cuff (L)', ''),
                      _buildMeasurementRow('袖口 Cuff (R)', ''),
                      _buildMeasurementRow('領口 Neck', ''),
                      
                      pw.Divider(height: 1, thickness: 1),
                      pw.Container(
                        color: PdfColors.grey200,
                        width: double.infinity,
                        padding: const pw.EdgeInsets.symmetric(vertical: 2),
                        child: pw.Text('褲 Trouser', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                      ),
                      _buildMeasurementRow('腰圍 Waist', ''),
                      _buildMeasurementRow('坐圍 Hip', ''),
                      _buildMeasurementRow('褲浪 Crotch', ''),
                      _buildMeasurementRow('脾圍 Thigh', ''),
                      _buildMeasurementRow('褲腳 Bottom', ''),
                      _buildMeasurementRow('全長 Length', ''),

                      pw.Spacer(),
                      pw.Divider(height: 1, thickness: 1),
                      pw.Container(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text('恤衫 Shirt:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                            _buildCompactRow('領 Collar:', ''),
                            _buildCompactRow('袖 Cuff:', ''),
                            _buildCompactRow('前 Front:', ''),
                            _buildCompactRow('背 Back:', ''),
                            _buildCompactRow('袋 Pocket:', ''),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // 中間與右側主體
                pw.Expanded(
                  child: pw.Column(
                    children: [
                      // 4. 布料與品項
                      pw.Container(
                        decoration: pw.BoxDecoration(border: borderStyle),
                        height: 350,
                        child: pw.Column(
                          children: [
                            pw.Container(
                              decoration: const pw.BoxDecoration(
                                border: pw.Border(bottom: pw.BorderSide()),
                              ),
                              child: pw.Row(
                                children: [
                                  pw.Expanded(child: pw.Center(child: pw.Text('布料 Fabric', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)))),
                                  pw.Container(width: 1, height: 20, color: PdfColors.black),
                                  pw.Expanded(child: pw.Center(child: pw.Text('里布 Lining', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)))),
                                ],
                              ),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(5),
                              child: pw.Row(
                                mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                                children: [
                                  _buildCategoryCheck('西裝 Suit', order.itemType == 'SUIT'),
                                  _buildCategoryCheck('外套 Jkt', order.itemType == 'JACKET'),
                                  _buildCategoryCheck('褲 Trs', order.itemType == 'TROUSER'),
                                  _buildCategoryCheck('恤衫 Shirt', order.itemType == 'SHIRT'),
                                ],
                              ),
                            ),
                            pw.Expanded(
                              child: pw.Center(
                                child: pw.Text(
                                  order.item,
                                  style: pw.TextStyle(fontSize: 20, color: PdfColors.grey300, fontWeight: pw.FontWeight.bold),
                                ),
                              ),
                            ),
                            pw.Container(
                              width: double.infinity,
                              padding: const pw.EdgeInsets.all(5),
                              decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide())),
                              child: pw.Text('備註 Notes: ${order.notes}', style: const pw.TextStyle(fontSize: 10)),
                            ),
                          ],
                        ),
                      ),

                      pw.SizedBox(height: 10),

                      // 5. 右下角：款式與做工選擇 (已更新)
                      pw.Expanded(
                        child: pw.Container(
                          decoration: pw.BoxDecoration(border: borderStyle),
                          child: pw.Row(
                            children: [
                              // 左半：外套款式
                              pw.Expanded(
                                child: pw.Container(
                                  padding: const pw.EdgeInsets.all(5),
                                  child: pw.Column(
                                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                                    children: [
                                      pw.Text('外套 Jacket', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)), // Reduced title size
                                      pw.Divider(thickness: 0.5),
                                      _buildCheckRow('剪裁 Fit:', ['貼身', '正常', '鬆身']),
                                      _buildCheckRow('做工 Make:', ['全襯', '半襯']),
                                      _buildCheckRow('里布 Lin:', ['全里', '半里']),
                                      _buildCheckRow('內襟珠線 Inner stitch :', ['有', '無']),
                                      _buildCheckRow('腰袋 Pocket design :', ['平袋', '斜袋', '貼袋', '腰折袋']),
                                      _buildCheckRow('後叉 Vent:', ['雙開', '單開', '無']),
                                      pw.SizedBox(height: 4),
                                      _buildSimpleCheck('珠邊 Pick Stitch'),
                                      _buildSimpleCheck('袖口開鈕 Functional Cuff'),
                                      _buildSimpleCheck('直角領 Peak Lapel'),
                                    ],
                                  ),
                                )
                              ),
                              pw.Container(width: 1, color: PdfColors.black),
                              // 右半：褲款式
                              pw.Expanded(
                                child: pw.Container(
                                  padding: const pw.EdgeInsets.all(5),
                                  child: pw.Column(
                                    crossAxisAlignment:
                                        pw.CrossAxisAlignment.start,
                                    children: [
                                      pw.Text(
                                        '褲 Trouser',
                                        style: pw.TextStyle(
                                          fontWeight: pw.FontWeight.bold,
                                          fontSize: 8, // Reduced title size
                                        ),
                                      ),
                                      pw.Divider(thickness: 0.5),
                                      _buildCheckRow('褶 Pleat:', ['0', '1', '2','反褶Reverse pleat']),
                                      _buildCheckRow('腰帶 Waistbands:', ['腰帶Beltloop', '橡筋Elastic','側扣Side adjuster']),
                                      _buildCheckRow('搭帶 Closure:', ['圓搭帶round', '尖搭帶point']),
                                      _buildCheckRow('前袋 Front Pocket:', ['斜袋Slant', '平袋Straight']),
                                      _buildCheckRow('後袋 Back Pocket:', ['鈕扣Button', '無鈕扣No Button','0', '1','2']),
                                      _buildCheckRow('錢袋 Watch Pocket:', ['有', '無']),
                                      _buildCheckRow('褲腳 Hem:', ['直腳Plain', '摺腳Cuffed', '摺腳加高Cuffed High']),
                                      
                                      pw.SizedBox(height: 4),
                                      _buildSimpleCheck('Button Tab'),
                                      _buildSimpleCheck('Watch Pocket'),
                                      _buildSimpleCheck('Back Pockets'),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- 輔助 Widgets ---

  pw.TableRow _buildTableRow(List<String> cells, pw.Font font) {
    return pw.TableRow(
      children: cells.map((c) => pw.Padding(
        padding: const pw.EdgeInsets.all(4),
        child: pw.Text(c, style: pw.TextStyle(font: font, fontSize: 9)),
      )).toList(),
    );
  }

  pw.Widget _buildInfoCell(String label, String value, {int flex = 1, required pw.Font font}) {
    return pw.Expanded(
      flex: flex,
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 8),
        decoration: const pw.BoxDecoration(
          border: pw.Border(right: pw.BorderSide(width: 0.5)),
        ),
        child: pw.Row(
          children: [
            pw.Text('$label: ', style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey700)),
            pw.Expanded(child: pw.Text(value, style: pw.TextStyle(font: font, fontSize: 11, fontWeight: pw.FontWeight.bold))),
          ],
        ),
      ),
    );
  }

  pw.Widget _buildMeasurementRow(String label, String value) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 6),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(width: 0.5, color: PdfColors.grey400)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 9)),
          pw.Container(width: 40, height: 12, color: PdfColors.grey100), 
        ],
      ),
    );
  }

  pw.Widget _buildCompactRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        children: [
          pw.SizedBox(width: 40, child: pw.Text(label, style: const pw.TextStyle(fontSize: 8))),
          pw.Expanded(child: pw.Container(height: 1, color: PdfColors.grey400)),
        ],
      ),
    );
  }

  pw.Widget _buildCategoryCheck(String label, bool isChecked) {
    return pw.Row(
      children: [
        pw.Container(
          width: 10,
          height: 10,
          decoration: pw.BoxDecoration(
            border: pw.Border.all(),
            color: isChecked ? PdfColors.black : null,
          ),
        ),
        pw.SizedBox(width: 4),
        pw.Text(label, style: const pw.TextStyle(fontSize: 10)),
      ],
    );
  }

  pw.Widget _buildCheckRow(String label, List<String> options) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.5), // Reduced padding
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(width: 55, child: pw.Text(label, style: const pw.TextStyle(fontSize: 8))), // Font size 8
          pw.Expanded(
            child: pw.Wrap(
              spacing: 4, // Reduced spacing
              runSpacing: 2,
              children: options.map((opt) => pw.Row(
                mainAxisSize: pw.MainAxisSize.min,
                children: [
                  pw.Container(width: 6, height: 6, decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5))), // 6x6 box, thin border
                  pw.SizedBox(width: 2),
                  pw.Text(opt, style: const pw.TextStyle(fontSize: 8)), // Font size 8
                ],
              )).toList(),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildSimpleCheck(String label) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
      child: pw.Row(
        children: [
          pw.Container(width: 6, height: 6, decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5))), // 6x6 box, thin border
          pw.SizedBox(width: 4),
          pw.Text(label, style: const pw.TextStyle(fontSize: 8)), // Font size 8
        ],
      ),
    );
  }
}