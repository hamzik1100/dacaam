import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/utils/enums.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/order.dart';
import '../../data/models/restaurant.dart';

/// Builds and prints the customer's receipt.
///
/// Laid out for an 80mm roll rather than A4: that is what a restaurant counter
/// printer takes, and Android's print service will still scale it onto a sheet
/// or a PDF for anyone without one. The same document shares to WhatsApp, which
/// is how most customers here want their copy.
class Receipt {
  const Receipt._();

  /// 80mm wide, and as long as the order needs — a fixed page height would
  /// clip a large order's lines rather than running on.
  static const double _widthMm = 80;

  static Future<void> print(
    RestaurantOrder order,
    Restaurant restaurant,
    AppLanguage lang,
  ) async {
    await Printing.layoutPdf(
      name: "DACAAM-${order.number}",
      onLayout: (PdfPageFormat _) => build(order, restaurant, lang),
    );
  }

  static Future<void> share(
    RestaurantOrder order,
    Restaurant restaurant,
    AppLanguage lang,
  ) async {
    await Printing.sharePdf(
      bytes: await build(order, restaurant, lang),
      filename: 'rasiid-${order.number}.pdf',
    );
  }

  static Future<Uint8List> build(
    RestaurantOrder order,
    Restaurant restaurant,
    AppLanguage lang,
  ) async {
    final pw.Document doc = pw.Document();

    // The built-in PDF fonts are enough here: Somali orthography is plain
    // Latin, so nothing needs a bundled typeface, and shipping one would add
    // several hundred kilobytes to the APK for no visible gain.
    final pw.Font base = pw.Font.helvetica();
    final pw.Font bold = pw.Font.helveticaBold();

    final PdfPageFormat format = PdfPageFormat(
      _widthMm * PdfPageFormat.mm,
      double.infinity,
      marginAll: 4 * PdfPageFormat.mm,
    );

    doc.addPage(
      pw.Page(
        pageFormat: format,
        build: (pw.Context context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          mainAxisSize: pw.MainAxisSize.min,
          children: <pw.Widget>[
            _header(order, restaurant, base, bold),
            _rule(),
            _meta(order, base, lang),
            _rule(),
            _lines(order, base, bold),
            _rule(),
            _totals(order, base, bold),
            // Also when there are no payments at all: an order put on the tab
            // has none, and a receipt that stays silent about a debt is the
            // one document the customer keeps.
            if (order.payments.isNotEmpty ||
                !order.paymentStatus.isSettled) ...<pw.Widget>[
              _rule(),
              _payments(order, base, bold),
            ],
            pw.SizedBox(height: 8),
            _footer(base),
          ],
        ),
      ),
    );

    return doc.save();
  }

  // ------------------------------------------------------------- sections

  static pw.Widget _header(
    RestaurantOrder order,
    Restaurant restaurant,
    pw.Font base,
    pw.Font bold,
  ) {
    return pw.Column(
      children: <pw.Widget>[
        pw.Text(
          restaurant.name,
          style: pw.TextStyle(font: bold, fontSize: 13),
          textAlign: pw.TextAlign.center,
        ),
        if (restaurant.phone.isNotEmpty)
          pw.Text(
            restaurant.phone,
            style: pw.TextStyle(font: base, fontSize: 8),
          ),
        if (restaurant.address.isNotEmpty)
          pw.Text(
            restaurant.address,
            style: pw.TextStyle(font: base, fontSize: 8),
            textAlign: pw.TextAlign.center,
          ),
        pw.SizedBox(height: 6),
        pw.Text(
          '#${order.number}',
          style: pw.TextStyle(font: bold, fontSize: 15),
        ),
      ],
    );
  }

  static pw.Widget _meta(
    RestaurantOrder order,
    pw.Font base,
    AppLanguage lang,
  ) {
    final List<List<String>> rows = <List<String>>[
      <String>['Taariikh', Fmt.dateTime(order.createdAt, lang)],
      <String>['Nooca', order.type == OrderType.dineIn ? 'Halkan Cun' : 'Qaad'],
      if (order.tableLabel != null) <String>['Miis', order.tableLabel!],
      if (order.waiterName.isNotEmpty) <String>['Adeege', order.waiterName],
      if (order.customerName.isNotEmpty)
        <String>['Macmiil', order.customerName],
    ];

    return pw.Column(
      children: rows
          .map((List<String> r) => _row(r[0], r[1], base, size: 8))
          .toList(),
    );
  }

  static pw.Widget _lines(RestaurantOrder order, pw.Font base, pw.Font bold) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: order.lines.map((OrderLine l) {
        return pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: <pw.Widget>[
              pw.Text(l.name, style: pw.TextStyle(font: bold, fontSize: 9)),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: <pw.Widget>[
                  pw.Text(
                    '${l.quantity} x ${Fmt.number(l.unitPrice)}',
                    style: pw.TextStyle(font: base, fontSize: 8),
                  ),
                  pw.Text(
                    Fmt.number(l.total),
                    style: pw.TextStyle(font: base, fontSize: 9),
                  ),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  static pw.Widget _totals(RestaurantOrder order, pw.Font base, pw.Font bold) {
    return pw.Column(
      children: <pw.Widget>[
        _row('Wadarta Hoose', Fmt.number(order.subtotal), base),
        if (order.discount > 0)
          _row('Qiimo Dhimis', '-${Fmt.number(order.discount)}', base),
        if (order.taxAmount > 0)
          _row(
            'Canshuur (${Fmt.decimal(order.taxRate * 100)}%)',
            Fmt.number(order.taxAmount),
            base,
          ),
        if (order.packagingFee > 0)
          _row('Baakadayn', Fmt.number(order.packagingFee), base),
        pw.SizedBox(height: 3),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: <pw.Widget>[
            pw.Text('WADARTA', style: pw.TextStyle(font: bold, fontSize: 11)),
            pw.Text(
              Fmt.money(order.total),
              style: pw.TextStyle(font: bold, fontSize: 11),
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _payments(
    RestaurantOrder order,
    pw.Font base,
    pw.Font bold,
  ) {
    final double paid = order.payments.fold<double>(
      0,
      (double sum, OrderPaymentEntry p) => sum + p.amount,
    );
    final double outstanding = order.total - paid;

    return pw.Column(
      children: <pw.Widget>[
        ...order.payments.map(
          (OrderPaymentEntry p) =>
              _row(p.method.label, Fmt.number(p.amount), base),
        ),
        // Only when something is still owed. Printing "Baaqi 0" on a settled
        // receipt invites the question of what it means.
        if (outstanding > 0.001) ...<pw.Widget>[
          _row('Hadhay', Fmt.number(outstanding), bold, size: 9),
          if (order.customerName.isNotEmpty)
            _row('Dayn', order.customerName, base),
        ],
      ],
    );
  }

  static pw.Widget _footer(pw.Font base) {
    return pw.Column(
      children: <pw.Widget>[
        pw.Text('Mahadsanid!', style: pw.TextStyle(font: base, fontSize: 9)),
        pw.SizedBox(height: 2),
        pw.Text(
          'DACAAM · Kafiican Innovations',
          style: pw.TextStyle(
            font: base,
            fontSize: 6,
            color: PdfColors.grey600,
          ),
        ),
      ],
    );
  }

  // -------------------------------------------------------------- helpers

  static pw.Widget _row(
    String label,
    String value,
    pw.Font font, {
    double size = 8.5,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 0.8),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: <pw.Widget>[
          pw.Text(
            label,
            style: pw.TextStyle(font: font, fontSize: size),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(font: font, fontSize: size),
          ),
        ],
      ),
    );
  }

  static pw.Widget _rule() => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 4),
    child: pw.Divider(height: 0.5, borderStyle: pw.BorderStyle.dashed),
  );
}
