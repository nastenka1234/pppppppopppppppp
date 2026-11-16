import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../core/jalali.dart';
import '../../core/models.dart';
import '../../core/messenger.dart';
import '../../core/api_client.dart';

class WeeklyReportPdf {
  static const _bg = PdfColor(0.086, 0.075, 0.086);
  static const _surface = PdfColor(0.118, 0.102, 0.106);
  static const _line = PdfColor(0.176, 0.141, 0.149);
  static const _orange = PdfColor(1, 0.427, 0.161);
  static const _white = PdfColors.white;
  static const _muted = PdfColor(0.73, 0.73, 0.73);
  static const _green = PdfColor(0.435, 0.812, 0.592);

  static Future<File> create(Stats stats, {String studentName = ''}) async {
    final regularData = await rootBundle.load('assets/fonts/Vazirmatn-Regular.ttf');
    final boldData = await rootBundle.load('assets/fonts/Vazirmatn-Bold.ttf');
    final regular = pw.Font.ttf(regularData);
    final bold = pw.Font.ttf(boldData);
    final theme = pw.ThemeData.withFont(base: regular, bold: bold);
    final days = [...stats.days]..sort((a, b) => a.day.compareTo(b.day));
    final parts = [...stats.parts]..sort((a, b) => b.minutes.compareTo(a.minutes));
    final tests = stats.totalTests;
    final correct = days.fold<int>(0, (v, d) => v + d.correct);
    final active = days.where((d) => d.studyMin > 0).length;
    final accuracy = tests == 0 ? 0 : (correct * 100 / tests).round();
    final start = days.isEmpty ? todayIso() : days.first.day;
    final end = days.isEmpty ? todayIso() : days.last.day;

    pw.Widget metric(String title, String value, {PdfColor accent = _orange}) => pw.Expanded(
          child: pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 13),
            decoration: pw.BoxDecoration(
              color: _surface,
              borderRadius: pw.BorderRadius.circular(13),
              border: pw.Border.all(color: _line),
            ),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(title, style: pw.TextStyle(font: regular, color: _muted, fontSize: 8)),
              pw.SizedBox(height: 5),
              pw.Text(value, style: pw.TextStyle(font: bold, color: accent, fontSize: 15)),
            ]),
          ),
        );

    pw.Widget section(String title) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 18, bottom: 8),
          child: pw.Row(children: [
            pw.Container(width: 4, height: 15, decoration: pw.BoxDecoration(color: _orange, borderRadius: pw.BorderRadius.circular(2))),
            pw.SizedBox(width: 7),
            pw.Text(title, style: pw.TextStyle(font: bold, color: _white, fontSize: 11)),
          ]),
        );

    pw.Widget rtl(pw.Widget child) => pw.Directionality(textDirection: pw.TextDirection.rtl, child: child);
    final doc = pw.Document(title: 'گزارش هفتگی امید', author: 'Omid Study');
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(32, 34, 32, 34),
      theme: theme,
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        theme: theme,
        margin: const pw.EdgeInsets.fromLTRB(32, 34, 32, 34),
        buildBackground: (_) => pw.Container(color: _bg),
      ),
      footer: (ctx) => rtl(pw.Container(
        padding: const pw.EdgeInsets.only(top: 8),
        decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: _line))),
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text('OMID  •  مسیر رشد تو', style: pw.TextStyle(font: bold, color: _muted, fontSize: 7)),
          pw.Text('${fa(ctx.pageNumber)} / ${fa(ctx.pagesCount)}', style: pw.TextStyle(font: regular, color: _muted, fontSize: 7)),
        ]),
      )),
      build: (_) => [
        rtl(pw.Container(
          padding: const pw.EdgeInsets.all(19),
          decoration: pw.BoxDecoration(
            color: _surface,
            borderRadius: pw.BorderRadius.circular(18),
            border: pw.Border.all(color: _line),
          ),
          child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
            pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('OMID  /  WEEKLY REPORT', style: pw.TextStyle(font: bold, color: _orange, fontSize: 8, letterSpacing: 1.2)),
              pw.SizedBox(height: 8),
              pw.Text('گزارش هفتگی', style: pw.TextStyle(font: bold, color: _white, fontSize: 22)),
              pw.SizedBox(height: 4),
              pw.Text('${jalaliFull(start)} تا ${jalaliFull(end)}', style: pw.TextStyle(font: regular, color: _muted, fontSize: 9)),
              if (studentName.trim().isNotEmpty) ...[
                pw.SizedBox(height: 4),
                pw.Text('دانش‌آموز: $studentName', style: pw.TextStyle(font: regular, color: _muted, fontSize: 8)),
              ],
            ])),
            pw.Container(
              width: 43,
              height: 43,
              decoration: pw.BoxDecoration(color: _orange, borderRadius: pw.BorderRadius.circular(14)),
              alignment: pw.Alignment.center,
              child: pw.Text('O', style: pw.TextStyle(font: bold, color: _bg, fontSize: 27)),
            ),
          ]),
        )),
        pw.SizedBox(height: 14),
        rtl(pw.Row(children: [
          metric('زمان مطالعه', fmtMin(stats.totalMin)),
          pw.SizedBox(width: 8),
          metric('تعداد تست', fa(tests)),
        ])),
        pw.SizedBox(height: 8),
        rtl(pw.Row(children: [
          metric('درصد پاسخ صحیح', '${fa(accuracy)}٪', accent: _green),
          pw.SizedBox(width: 8),
          metric('روزهای فعال', '${fa(active)} از ${fa(days.length)}', accent: _green),
        ])),
        rtl(section('عملکرد روزانه')),
        rtl(pw.Table(
          border: pw.TableBorder(
            horizontalInside: const pw.BorderSide(color: _line, width: .6),
            bottom: const pw.BorderSide(color: _line),
          ),
          columnWidths: const {
            0: pw.FlexColumnWidth(2.2),
            1: pw.FlexColumnWidth(2),
            2: pw.FlexColumnWidth(1.3),
            3: pw.FlexColumnWidth(1.3),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: _surface),
              children: [for (final h in ['روز', 'مطالعه', 'تست', 'درست']) _cell(h, bold, _muted, header: true)],
            ),
            for (final d in days)
              pw.TableRow(children: [
                _cell(jalaliFull(d.day), regular, _white),
                _cell(fmtMin(d.studyMin), regular, _white),
                _cell(fa(d.tests), regular, _white),
                _cell(fa(d.correct), regular, _green),
              ]),
          ],
        )),
        rtl(section('جزئیات پارت‌ها')),
        if (parts.isEmpty)
          rtl(pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(color: _surface, borderRadius: pw.BorderRadius.circular(10)),
            child: pw.Text('هنوز داده‌ای برای پارت‌ها ثبت نشده است.', style: pw.TextStyle(font: regular, color: _muted, fontSize: 9)),
          ))
        else
          for (final p in parts.take(12))
            rtl(pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 7),
              padding: const pw.EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              decoration: pw.BoxDecoration(color: _surface, borderRadius: pw.BorderRadius.circular(10), border: pw.Border.all(color: _line)),
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
                pw.Row(children: [
                  pw.Expanded(child: pw.Text(p.part, style: pw.TextStyle(font: bold, color: _white, fontSize: 9))),
                  pw.Text(fmtMin(p.minutes), style: pw.TextStyle(font: bold, color: _orange, fontSize: 8)),
                ]),
                pw.SizedBox(height: 5),
                pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                  pw.Text('${fa(p.tests)} تست', style: pw.TextStyle(font: regular, color: _muted, fontSize: 8)),
                  pw.Text('${fa(p.correct)} درست', style: pw.TextStyle(font: regular, color: _muted, fontSize: 8)),
                  pw.Text('${fa(p.percent.round())}٪ دقت', style: pw.TextStyle(font: bold, color: _green, fontSize: 8)),
                ]),
              ]),
            )),
        pw.SizedBox(height: 12),
        rtl(pw.Container(
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(color: _surface, borderRadius: pw.BorderRadius.circular(12), border: pw.Border.all(color: _line)),
          child: pw.Text('این گزارش بر اساس داده‌های ثبت‌شده در اپلیکیشن امید تهیه شده است.', textAlign: pw.TextAlign.center, style: pw.TextStyle(font: regular, color: _muted, fontSize: 8)),
        )),
      ],
    ));

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/omid-weekly-$start-$end.pdf');
    await file.writeAsBytes(await doc.save(), flush: true);
    return file;
  }

  static pw.Widget _cell(String value, pw.Font font, PdfColor color, {bool header = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 8),
        child: pw.Text(value, style: pw.TextStyle(font: font, color: color, fontSize: header ? 8 : 7.5)),
      );
}

class WeeklyReportSender {
  static Future<void> send() async {
    final response = await Api.i.get('/stats', q: {'range': 7});
    final stats = Stats.fromJson(response);
    final studentName = await Api.i.readSecure('name') ?? '';
    final file = await WeeklyReportPdf.create(stats, studentName: studentName);
    try {
      await MessengerApi.sendFile(
        path: file.path,
        type: 'document',
        name: 'گزارش-هفتگی-امید.pdf',
        mimeType: 'application/pdf',
      );
    } finally {
      try { await file.delete(); } catch (_) {}
    }
  }
}
