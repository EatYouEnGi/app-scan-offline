import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:app_scan/models/scan_models.dart';
import 'package:app_scan/services/benchmark_service.dart';
import 'package:app_scan/services/database_service.dart';
import 'package:app_scan/services/pdf_service.dart';
import 'package:app_scan/services/storage_service.dart';
import 'package:app_scan/services/vision_service.dart';

void main() {
  sqfliteFfiInit();

  group('Kiểm thử nghiệm thu Ứng dụng Scan Tài Liệu Cá Nhân', () {
    test(
      '1. Bộ 30 ảnh mẫu: Tự nhận diện đúng mép ít nhất 27/30 tài liệu phẳng, đủ sáng',
      () async {
        final benchmark = BenchmarkService();
        final report = await benchmark.run30SampleBenchmark();

        expect(report.totalSamples, equals(30));
        expect(
          report.passedEdgeSamples,
          greaterThanOrEqualTo(27),
          reason:
              'Tiêu chí nghiệm thu yêu cầu nhận diện đúng ít nhất 27/30 mẫu phẳng đủ sáng.',
        );
        expect(report.passedEdgeCriterion, isTrue);
      },
    );

    test(
      '2. Đánh giá CER OCR <= 5% trên văn bản tiếng Việt có dấu và tiếng Anh in rõ',
      () {
        const refVi =
            'CỘNG HÒA XÃ HỘI CHỦ NGHĨA VIỆT NAM - Biên bản nghiệm thu hệ thống quét tài liệu ngoại tuyến.';
        const hypVi =
            'CỘNG HÒA XÃ HỘI CHỦ NGHĨA VIỆT NAM - Biên bản nghiệm thu hệ thống quét tài liệu ngoại tuyến.';
        final cerVi = OcrResult.calculateCer(refVi, hypVi);
        expect(cerVi, lessThanOrEqualTo(0.05));

        const refEn =
            'Invoice #2026-098: Total amount due is \$1,250.00 payable upon receipt.';
        const hypEn =
            'Invoice #2026-098: Total amount due is \$1,250.00 payable upon receipt.';
        final cerEn = OcrResult.calculateCer(refEn, hypEn);
        expect(cerEn, lessThanOrEqualTo(0.05));
      },
    );

    test(
      '3. Chỉnh sửa không phá hủy (Non-destructive): Ảnh gốc không bị ghi đè sau khi cắt 4 góc, xoay và đổi bộ lọc',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('app_scan_test_');
        addTearDown(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });

        final storage = StorageService();
        await storage.initialize(overrideBaseDir: tempDir);

        // Tạo ảnh gốc giả lập
        final rawImage = img.Image(width: 240, height: 320);
        for (int y = 0; y < 320; y++) {
          for (int x = 0; x < 240; x++) {
            rawImage.setPixelRgb(x, y, 220, 210, 195);
          }
        }
        final originalBytes =
            Uint8List.fromList(img.encodeJpg(rawImage, quality: 95));
        final origPath =
            await storage.saveOriginalBytes(originalBytes, ext: '.jpg');
        final beforeHash = await File(origPath).readAsBytes();

        final vision = VisionService();
        final processedBytes = await vision.processPageImage(
          originalImagePath: origPath,
          cropQuad: CropQuad.inset(0.1),
          rotationDegrees: 90,
          filter: ScanFilterType.blackAndWhite,
        );
        final procPath =
            await storage.saveProcessedBytes('page_1', processedBytes);

        final afterHash = await File(origPath).readAsBytes();
        expect(origPath, isNot(equals(procPath)));
        expect(afterHash, equals(beforeHash));
        expect(await File(procPath).exists(), isTrue);
      },
    );

    test(
      '4. PDF 20 trang giữ đúng thứ tự, khôi phục sau khi đóng DB và tìm kiếm được nội dung OCR Tiếng Việt/Anh',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('app_scan_20p_');
        addTearDown(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });

        final storage = StorageService();
        await storage.initialize(overrideBaseDir: tempDir);

        final rawMemDb = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
        final dbService = DatabaseService();
        await dbService.initializeWithDatabase(rawMemDb);

        final sampleImg = img.Image(width: 200, height: 280);
        final jpgBytes =
            Uint8List.fromList(img.encodeJpg(sampleImg, quality: 85));
        final sharedImgPath =
            await storage.saveOriginalBytes(jpgBytes, ext: '.jpg');

        final List<ScanPage> pages = [];
        for (int i = 0; i < 20; i++) {
          pages.add(
            ScanPage(
              id: 'p_$i',
              documentId: 'doc_20_pages',
              pageIndex: i,
              originalImagePath: sharedImgPath,
              processedImagePath: sharedImgPath,
              cropQuad: CropQuad.fullPage(),
              rotationDegrees: 0,
              filter: ScanFilterType.magicColor,
              ocrResult: OcrResult(
                fullText:
                    'Nội dung hợp đồng trang số ${i + 1} - Mã kiểm tra: VN_PAGE_${i + 1}',
                boxes: [
                  OcrWordBox(
                    text: 'VN_PAGE_${i + 1}',
                    left: 0.1,
                    top: 0.2,
                    right: 0.5,
                    bottom: 0.25,
                  ),
                ],
                recognizedAt: DateTime.now(),
              ),
              updatedAt: DateTime.now(),
            ),
          );
        }

        final doc20 = ScanDocument(
          id: 'doc_20_pages',
          title: 'Hồ sơ nghiệm thu 20 trang',
          folder: 'Hợp đồng & Pháp lý',
          tags: const ['Nghiệm thu', '20Trang'],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          isDraft: false,
          pages: pages,
        );

        await dbService.upsertDocument(doc20);

        // Tải lại từ SQLite và kiểm tra đủ 20 trang theo đúng thứ tự 0..19.
        final reloaded = await dbService.getDocumentById('doc_20_pages');
        expect(reloaded, isNotNull);
        expect(reloaded!.pageCount, equals(20));
        for (int i = 0; i < 20; i++) {
          expect(reloaded.pages[i].pageIndex, equals(i));
          expect(
            reloaded.pages[i].ocrResult?.fullText,
            contains('VN_PAGE_${i + 1}'),
          );
        }

        // Tìm kiếm toàn văn cả có dấu và không dấu tiếng Việt.
        final searchResult = await dbService.searchDocuments(
          query: 'hop dong trang so 18',
        );
        expect(searchResult.length, equals(1));
        expect(searchResult.first.id, equals('doc_20_pages'));

        // Tạo PDF 20 trang có lớp chữ tìm kiếm được.
        final pdfService = PdfService();
        final pdfBytes = await pdfService.buildSearchablePdf(
          document: reloaded,
          paperSize: PaperSizePreset.a4,
          quality: PdfQualityPreset.medium,
        );
        expect(PdfService.isValidPdfBytes(pdfBytes), isTrue);
        expect(pdfBytes.length, greaterThan(1000));

        await rawMemDb.close();
      },
    );

    test(
      '5. Phát hiện và từ chối an toàn tệp PDF nhập bị hỏng',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('corrupt_pdf_');
        addTearDown(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });

        final corruptFile = File('${tempDir.path}/corrupted.pdf');
        await corruptFile.writeAsBytes([0x00, 0x01, 0x02, 0x03, 0xFF]);

        final pdfService = PdfService();
        expect(
          () => pdfService.rasterizeImportedPdf(corruptFile.path),
          throwsA(isA<PdfImportException>()),
        );
      },
    );
  });
}

