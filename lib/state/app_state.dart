import 'dart:io';
import 'dart:ui';
import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../models/scan_models.dart';
import '../services/benchmark_service.dart';
import '../services/database_service.dart';
import '../services/ocr_service.dart';
import '../services/pdf_service.dart';
import '../services/security_service.dart';
import '../services/storage_service.dart';
import '../services/vision_service.dart';

/// Quản lý trạng thái toàn cục của ứng dụng Scan Tài Liệu Cá Nhân.
class AppState extends ChangeNotifier {
  final DatabaseService databaseService;
  final StorageService storageService;
  final VisionService visionService;
  final OcrService ocrService;
  final PdfService pdfService;
  final SecurityService securityService;
  final BenchmarkService benchmarkService;

  final Uuid _uuid = const Uuid();

  List<ScanDocument> _documents = [];
  List<ScanDocument> _recoverableDrafts = [];
  ScanDocument? _activeDraft;

  String _searchQuery = '';
  String _selectedFolder = 'Tất cả tài liệu';
  String? _selectedTag;

  bool _isLoading = false;
  String? _busyMessage;
  String? _lastError;

  bool _biometricLockEnabled = false;
  bool _isLocked = false;

  AppState({
    DatabaseService? databaseService,
    StorageService? storageService,
    VisionService? visionService,
    OcrService? ocrService,
    PdfService? pdfService,
    SecurityService? securityService,
    BenchmarkService? benchmarkService,
  })  : databaseService = databaseService ?? DatabaseService(),
        storageService = storageService ?? StorageService(),
        visionService = visionService ?? VisionService(),
        ocrService = ocrService ?? OcrService(),
        pdfService = pdfService ?? PdfService(),
        securityService = securityService ?? SecurityService(),
        benchmarkService = benchmarkService ?? BenchmarkService();

  List<ScanDocument> get documents => _documents;
  List<ScanDocument> get recoverableDrafts => _recoverableDrafts;
  ScanDocument? get activeDraft => _activeDraft;

  String get searchQuery => _searchQuery;
  String get selectedFolder => _selectedFolder;
  String? get selectedTag => _selectedTag;

  bool get isLoading => _isLoading;
  String? get busyMessage => _busyMessage;
  String? get lastError => _lastError;

  bool get biometricLockEnabled => _biometricLockEnabled;
  bool get isLocked => _isLocked;

  List<String> get availableFolders {
    final set = <String>{
      'Tất cả tài liệu',
      'Hóa đơn & Biên lai',
      'Hợp đồng & Pháp lý',
      'CCCD & Giấy tờ tùy thân',
      'Tài liệu học tập',
    };
    for (final doc in _documents) {
      if (doc.folder.trim().isNotEmpty) {
        set.add(doc.folder.trim());
      }
    }
    return set.toList();
  }

  List<String> get availableTags {
    final set = <String>{};
    for (final doc in _documents) {
      set.addAll(doc.tags);
    }
    final list = set.toList()..sort();
    return list;
  }

  Future<void> initialize() async {
    _setBusy(true, 'Đang khởi tạo kho tài liệu ngoại tuyến...');
    try {
      await storageService.initialize();
      _biometricLockEnabled = await securityService.isBiometricLockEnabled();
      if (_biometricLockEnabled) {
        _isLocked = true;
      }
      await refreshLibrary();
    } catch (e) {
      _lastError = e.toString();
    } finally {
      _setBusy(false, null);
    }
  }

  Future<bool> unlockWithBiometrics() async {
    final ok = await securityService.authenticateUser();
    if (ok) {
      _isLocked = false;
      notifyListeners();
    }
    return ok;
  }

  Future<void> toggleBiometricLock(bool enabled) async {
    if (enabled) {
      final canUse = await securityService.canCheckBiometrics();
      if (!canUse) {
        _lastError =
            'Thiết bị hiện chưa cài đặt Face ID / Touch ID hoặc vân tay.';
        notifyListeners();
        return;
      }
      final verified = await securityService.authenticateUser(
        reason: 'Xác nhận sinh trắc học để bật khóa ứng dụng',
      );
      if (!verified) return;
    }
    await securityService.setBiometricLockEnabled(enabled);
    _biometricLockEnabled = enabled;
    _isLocked = false;
    notifyListeners();
  }

  void clearError() {
    _lastError = null;
    notifyListeners();
  }

  Future<void> refreshLibrary() async {
    _documents = await databaseService.searchDocuments(
      query: _searchQuery,
      folderFilter: _selectedFolder,
      tagFilter: _selectedTag,
    );
    _recoverableDrafts = await databaseService.loadDraftDocuments();
    notifyListeners();
  }

  Future<void> setSearchQuery(String query) async {
    _searchQuery = query;
    await refreshLibrary();
  }

  Future<void> setFolderFilter(String folder) async {
    _selectedFolder = folder;
    await refreshLibrary();
  }

  Future<void> setTagFilter(String? tag) async {
    _selectedTag = tag;
    await refreshLibrary();
  }

  /// Mở trình quét AI trên thiết bị (Google ML Kit Document Scanner trên Android /
  /// Apple VisionKit trên iOS): tự động bắt mép giấy mọi góc độ không cần khung,
  /// tự chụp và làm phẳng trang.
  Future<List<String>?> launchNativeAiScanner({int maxPages = 100}) async {
    try {
      final result = await CunningDocumentScanner.scanDocuments(
        noOfPages: maxPages,
        scannerSource: ScannerSource.cameraAndGallery,
        output: ScanOutput.images,
        androidScannerMode: AndroidScannerMode.full,
      );
      if (result == null || result.images.isEmpty) {
        return null;
      }
      return result.images.toList();
    } catch (_) {
      return null;
    }
  }

  Future<ScanDocument> startNewDraft({String? customTitle}) async {
    final now = DateTime.now();
    final formatted = DateFormat('dd/MM/yyyy HH:mm').format(now);
    final draft = ScanDocument(
      id: _uuid.v4(),
      title: customTitle ?? 'Scan $formatted',
      folder: _selectedFolder == 'Tất cả tài liệu'
          ? 'Tất cả tài liệu'
          : _selectedFolder,
      tags: const [],
      createdAt: now,
      updatedAt: now,
      isDraft: true,
      pages: const [],
    );
    await databaseService.upsertDocument(draft);
    _activeDraft = draft;
    notifyListeners();
    return draft;
  }

  Future<ScanDocument> resumeDraft(ScanDocument draft) async {
    final latest = await databaseService.getDocumentById(draft.id) ?? draft;
    _activeDraft = latest;
    notifyListeners();
    return latest;
  }

  Future<ScanDocument> finalizeDocument(ScanDocument doc) async {
    final latest = await databaseService.getDocumentById(doc.id) ?? doc;
    final finalized = latest.copyWith(
      isDraft: false,
      updatedAt: DateTime.now(),
    );
    await databaseService.upsertDocument(finalized);
    if (_activeDraft?.id == finalized.id) {
      _activeDraft = null;
    }
    await refreshLibrary();
    return finalized;
  }

  /// Thêm một hoặc nhiều ảnh vào tài liệu.
  /// Nếu `alreadyCroppedByAi = true` (ảnh trả về từ ML Kit Document Scanner / VisionKit),
  /// giữ nguyên khung trang đã được AI cắt phẳng và chạy OCR kết hợp (Offline + AI).
  Future<ScanDocument> addImagesToDocument({
    required ScanDocument document,
    required List<String> sourceImagePaths,
    ScanFilterType defaultFilter = ScanFilterType.magicColor,
    bool alreadyCroppedByAi = false,
    bool runOcrImmediately = true,
  }) async {
    var currentDoc =
        await databaseService.getDocumentById(document.id) ?? document;
    final existingPages = List<ScanPage>.from(currentDoc.pages);

    for (int i = 0; i < sourceImagePaths.length; i++) {
      _setBusy(
        true,
        'Đang xử lý AI trang ${i + 1}/${sourceImagePaths.length} (Làm nét & OCR Tiếng Việt)...',
      );
      try {
        final origPath =
            await storageService.importOriginalImage(sourceImagePaths[i]);
        final detectedQuad = alreadyCroppedByAi
            ? CropQuad.fullPage()
            : await visionService.detectDocumentCorners(origPath);
        final pageId = _uuid.v4();

        final appliedFilter =
            alreadyCroppedByAi ? ScanFilterType.original : defaultFilter;

        final processedBytes = await visionService.processPageImage(
          originalImagePath: origPath,
          cropQuad: detectedQuad,
          rotationDegrees: 0,
          filter: appliedFilter,
        );
        final procPath =
            await storageService.saveProcessedBytes(pageId, processedBytes);

        OcrResult? ocr;
        if (runOcrImmediately) {
          ocr = await ocrService.recognizePageImage(
            procPath,
            enhanceHandwriting: true,
          );
        }

        final newPage = ScanPage(
          id: pageId,
          documentId: currentDoc.id,
          pageIndex: existingPages.length,
          originalImagePath: origPath,
          processedImagePath: procPath,
          cropQuad: detectedQuad,
          rotationDegrees: 0,
          filter: appliedFilter,
          ocrResult: ocr,
          updatedAt: DateTime.now(),
        );

        existingPages.add(newPage);
        currentDoc = currentDoc.copyWith(
          pages: List<ScanPage>.from(existingPages),
          updatedAt: DateTime.now(),
        );
        await databaseService.upsertDocument(currentDoc);
      } catch (e) {
        _lastError = 'Lỗi khi thêm ảnh thứ ${i + 1}: $e';
      }
    }

    _setBusy(false, null);
    if (_activeDraft?.id == currentDoc.id) {
      _activeDraft = currentDoc;
    }
    await refreshLibrary();
    return currentDoc;
  }

  /// Chỉnh sửa không phá hủy một trang.
  Future<ScanPage> updatePageTransform({
    required ScanPage page,
    CropQuad? cropQuad,
    int? rotationDegrees,
    ScanFilterType? filter,
    List<PageAnnotation>? annotations,
    bool rerunOcr = true,
  }) async {
    _setBusy(true, 'Đang áp dụng chỉnh sửa & nhận dạng OCR...');
    try {
      final newQuad = cropQuad ?? page.cropQuad;
      final newRotation = (rotationDegrees ?? page.rotationDegrees) % 360;
      final newFilter = filter ?? page.filter;
      final newAnnotations = annotations ?? page.annotations;

      final processedBytes = await visionService.processPageImage(
        originalImagePath: page.originalImagePath,
        cropQuad: newQuad,
        rotationDegrees: newRotation,
        filter: newFilter,
      );

      final oldProcessed = page.processedImagePath;
      final newProcessedPath =
          await storageService.saveProcessedBytes(page.id, processedBytes);
      await storageService.deleteProcessedFileIfExists(oldProcessed);

      OcrResult? updatedOcr = page.ocrResult;
      if (rerunOcr) {
        updatedOcr = await ocrService.recognizePageImage(
          newProcessedPath,
          enhanceHandwriting: true,
        );
      }

      final updatedPage = page.copyWith(
        processedImagePath: newProcessedPath,
        cropQuad: newQuad,
        rotationDegrees: newRotation,
        filter: newFilter,
        ocrResult: updatedOcr,
        annotations: newAnnotations,
        updatedAt: DateTime.now(),
      );

      await databaseService.upsertPage(updatedPage);
      await refreshLibrary();
      return updatedPage;
    } finally {
      _setBusy(false, null);
    }
  }

  /// Cho phép người dùng chỉnh sửa trực tiếp văn bản OCR hoặc chạy lại AI OCR.
  Future<ScanPage> updatePageOcrText({
    required ScanPage page,
    required String editedText,
  }) async {
    final normalized = OcrService.normalizeVietnameseText(editedText);
    final updatedOcr = OcrResult(
      fullText: normalized,
      boxes: page.ocrResult?.boxes ?? const [],
      recognizedAt: DateTime.now(),
      languageHint: 'vi-edited',
    );
    final updatedPage = page.copyWith(
      ocrResult: updatedOcr,
      updatedAt: DateTime.now(),
    );
    await databaseService.upsertPage(updatedPage);
    await refreshLibrary();
    return updatedPage;
  }

  /// Chạy lại AI OCR tăng cường (dành cho chữ viết tay & dấu Tiếng Việt mờ).
  Future<ScanPage> rerunPageAiOcr(ScanPage page) async {
    _setBusy(
      true,
      'Đang chạy AI OCR tăng cường (Tiếng Việt & Chữ viết tay)...',
    );
    try {
      final ocr = await ocrService.recognizePageImage(
        page.displayImagePath,
        enhanceHandwriting: true,
      );
      final updatedPage = page.copyWith(
        ocrResult: ocr,
        updatedAt: DateTime.now(),
      );
      await databaseService.upsertPage(updatedPage);
      await refreshLibrary();
      return updatedPage;
    } finally {
      _setBusy(false, null);
    }
  }

  Future<ScanPage> retakePage({
    required ScanPage oldPage,
    required String newSourceImagePath,
    bool alreadyCroppedByAi = false,
  }) async {
    _setBusy(true, 'Đang thay thế trang chụp lại...');
    try {
      final newOrigPath =
          await storageService.importOriginalImage(newSourceImagePath);
      final detectedQuad = alreadyCroppedByAi
          ? CropQuad.fullPage()
          : await visionService.detectDocumentCorners(newOrigPath);
      final processedBytes = await visionService.processPageImage(
        originalImagePath: newOrigPath,
        cropQuad: detectedQuad,
        rotationDegrees: 0,
        filter: alreadyCroppedByAi ? ScanFilterType.original : oldPage.filter,
      );
      final newProcPath =
          await storageService.saveProcessedBytes(oldPage.id, processedBytes);
      final ocr = await ocrService.recognizePageImage(
        newProcPath,
        enhanceHandwriting: true,
      );

      await storageService.deletePageFiles(
        originalPath: oldPage.originalImagePath,
        processedPath: oldPage.processedImagePath,
      );

      final replaced = oldPage.copyWith(
        originalImagePath: newOrigPath,
        processedImagePath: newProcPath,
        cropQuad: detectedQuad,
        rotationDegrees: 0,
        ocrResult: ocr,
        updatedAt: DateTime.now(),
      );
      await databaseService.upsertPage(replaced);
      await refreshLibrary();
      return replaced;
    } finally {
      _setBusy(false, null);
    }
  }

  Future<ScanDocument> reorderPages(
    ScanDocument doc,
    int oldIndex,
    int newIndex,
  ) async {
    final pages = List<ScanPage>.from(doc.pages)
      ..sort((a, b) => a.pageIndex.compareTo(b.pageIndex));
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final moved = pages.removeAt(oldIndex);
    pages.insert(newIndex, moved);

    final reindexed = <ScanPage>[];
    for (int i = 0; i < pages.length; i++) {
      reindexed.add(pages[i].copyWith(pageIndex: i));
    }

    await databaseService.replaceDocumentPages(doc.id, reindexed);
    await refreshLibrary();
    return (await databaseService.getDocumentById(doc.id))!;
  }

  Future<ScanDocument?> deletePage(
    ScanDocument doc,
    ScanPage pageToDelete,
  ) async {
    await storageService.deletePageFiles(
      originalPath: pageToDelete.originalImagePath,
      processedPath: pageToDelete.processedImagePath,
    );
    final remaining = doc.pages.where((p) => p.id != pageToDelete.id).toList()
      ..sort((a, b) => a.pageIndex.compareTo(b.pageIndex));

    if (remaining.isEmpty) {
      await deleteDocument(doc);
      return null;
    }

    await databaseService.replaceDocumentPages(doc.id, remaining);
    await refreshLibrary();
    return databaseService.getDocumentById(doc.id);
  }

  Future<ScanDocument> updateDocumentMetadata({
    required ScanDocument doc,
    String? title,
    String? folder,
    List<String>? tags,
  }) async {
    final updated = doc.copyWith(
      title: title?.trim().isNotEmpty == true ? title!.trim() : doc.title,
      folder: folder ?? doc.folder,
      tags: tags ?? doc.tags,
      isDraft: false,
      updatedAt: DateTime.now(),
    );
    await databaseService.upsertDocument(updated);
    await refreshLibrary();
    return updated;
  }

  Future<void> deleteDocument(ScanDocument doc) async {
    for (final page in doc.pages) {
      await storageService.deletePageFiles(
        originalPath: page.originalImagePath,
        processedPath: page.processedImagePath,
      );
    }
    await databaseService.deleteDocument(doc.id);
    if (_activeDraft?.id == doc.id) {
      _activeDraft = null;
    }
    await refreshLibrary();
  }

  // ===========================================================================
  // XUẤT FILE, LƯU VÀO MÁY, IN ẤN & CHIA SẺ ĐA ỨNG DỤNG (Zalo, Gmail, Drive...)
  // ===========================================================================

  /// Tạo PDF nhiều trang có lớp chữ OCR Tiếng Việt và mở bảng Chia sẻ sang ứng dụng khác.
  Future<String> exportSearchablePdf({
    required ScanDocument document,
    PaperSizePreset paperSize = PaperSizePreset.a4,
    PdfQualityPreset quality = PdfQualityPreset.medium,
    bool openShareSheet = true,
  }) async {
    _setBusy(true, 'Đang tạo tệp PDF nhiều trang chuẩn Tiếng Việt...');
    try {
      final latestDoc =
          await databaseService.getDocumentById(document.id) ?? document;
      final pdfBytes = await pdfService.buildSearchablePdf(
        document: latestDoc,
        paperSize: paperSize,
        quality: quality,
      );
      final savedPath =
          await storageService.saveExportedPdf(latestDoc.title, pdfBytes);

      final updatedDoc = latestDoc.copyWith(
        isDraft: false,
        lastExportedPdfPath: savedPath,
        updatedAt: DateTime.now(),
      );
      await databaseService.upsertDocument(updatedDoc);
      await refreshLibrary();

      if (openShareSheet) {
        await Share.shareXFiles(
          [
            XFile(
              savedPath,
              mimeType: 'application/pdf',
              name: '${_safeFileName(latestDoc.title)}.pdf',
            ),
          ],
          subject: latestDoc.title,
          text: latestDoc.title,
          sharePositionOrigin: const Rect.fromLTWH(0, 0, 300, 300),
        );
      }
      return savedPath;
    } finally {
      _setBusy(false, null);
    }
  }

  /// Lưu trực tiếp tệp PDF vào thư mục người dùng chọn trên máy (Downloads / Files).
  Future<String?> savePdfToDeviceFolder({
    required ScanDocument document,
    PaperSizePreset paperSize = PaperSizePreset.a4,
    PdfQualityPreset quality = PdfQualityPreset.medium,
  }) async {
    _setBusy(true, 'Đang chuẩn bị tệp PDF để lưu vào thiết bị...');
    try {
      final latestDoc =
          await databaseService.getDocumentById(document.id) ?? document;
      final pdfBytes = await pdfService.buildSearchablePdf(
        document: latestDoc,
        paperSize: paperSize,
        quality: quality,
      );
      final internalPath =
          await storageService.saveExportedPdf(latestDoc.title, pdfBytes);

      final fileName = '${_safeFileName(latestDoc.title)}.pdf';
      final userPickedPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Chọn nơi lưu tệp PDF',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        bytes: pdfBytes,
      );
      return userPickedPath ?? internalPath;
    } finally {
      _setBusy(false, null);
    }
  }

  /// Xem trước PDF trực quan hoặc In tài liệu qua trình in của hệ điều hành.
  Future<void> previewAndPrintPdf({
    required ScanDocument document,
    PaperSizePreset paperSize = PaperSizePreset.a4,
    PdfQualityPreset quality = PdfQualityPreset.medium,
  }) async {
    final latestDoc =
        await databaseService.getDocumentById(document.id) ?? document;
    await Printing.layoutPdf(
      name: '${_safeFileName(latestDoc.title)}.pdf',
      onLayout: (_) => pdfService.buildSearchablePdf(
        document: latestDoc,
        paperSize: paperSize,
        quality: quality,
      ),
    );
  }

  /// Chia sẻ bộ ảnh JPG của các trang sang Zalo, Messenger, Gmail, Photos...
  Future<void> shareDocumentImages(ScanDocument document) async {
    final sorted = List<ScanPage>.from(document.pages)
      ..sort((a, b) => a.pageIndex.compareTo(b.pageIndex));
    final files = <XFile>[];
    for (int i = 0; i < sorted.length; i++) {
      final path = sorted[i].displayImagePath;
      if (File(path).existsSync()) {
        files.add(
          XFile(
            path,
            mimeType: 'image/jpeg',
            name: '${_safeFileName(document.title)}_trang_${i + 1}.jpg',
          ),
        );
      }
    }
    if (files.isEmpty) return;
    await Share.shareXFiles(
      files,
      subject: document.title,
      text: '${document.title} (${files.length} trang)',
      sharePositionOrigin: const Rect.fromLTWH(0, 0, 300, 300),
    );
  }

  /// Chia sẻ toàn bộ nội dung văn bản OCR qua các ứng dụng nhắn tin/email/ghi chú.
  Future<void> shareOcrText(ScanDocument document) async {
    final text = document.combinedOcrText.trim();
    if (text.isEmpty) return;
    await Share.share(
      text,
      subject: '${document.title} - Văn bản OCR',
      sharePositionOrigin: const Rect.fromLTWH(0, 0, 300, 300),
    );
  }

  static String _safeFileName(String title) {
    final cleaned = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return cleaned.isEmpty ? 'Tai_lieu_scan' : cleaned;
  }

  // ===========================================================================
  // CÔNG CỤ PDF MỞ RỘNG (Nhập PDF, Gộp, Tách)
  // ===========================================================================

  Future<ScanDocument> importExistingPdf({
    required String pdfPath,
    required String customTitle,
    bool runOcr = true,
  }) async {
    _setBusy(true, 'Đang đọc và tách trang tệp PDF...');
    try {
      final pagePngs = await pdfService.rasterizeImportedPdf(pdfPath);
      final now = DateTime.now();
      final docId = _uuid.v4();
      final List<ScanPage> pages = [];

      for (int i = 0; i < pagePngs.length; i++) {
        _setBusy(
          true,
          'Đang nhập & OCR trang PDF ${i + 1}/${pagePngs.length}...',
        );
        final origPath =
            await storageService.saveOriginalBytes(pagePngs[i], ext: '.png');
        final pageId = _uuid.v4();
        OcrResult? ocr;
        if (runOcr) {
          ocr = await ocrService.recognizePageImage(origPath);
        }
        pages.add(
          ScanPage(
            id: pageId,
            documentId: docId,
            pageIndex: i,
            originalImagePath: origPath,
            processedImagePath: origPath,
            cropQuad: CropQuad.fullPage(),
            rotationDegrees: 0,
            filter: ScanFilterType.original,
            ocrResult: ocr,
            updatedAt: DateTime.now(),
          ),
        );
      }

      final importedDoc = ScanDocument(
        id: docId,
        title: customTitle,
        folder: 'Tất cả tài liệu',
        tags: const ['PDF Nhập'],
        createdAt: now,
        updatedAt: now,
        isDraft: false,
        pages: pages,
      );
      await databaseService.upsertDocument(importedDoc);
      await refreshLibrary();
      return importedDoc;
    } finally {
      _setBusy(false, null);
    }
  }

  Future<ScanDocument> mergeDocuments({
    required List<ScanDocument> sourceDocuments,
    required String mergedTitle,
  }) async {
    _setBusy(true, 'Đang gộp ${sourceDocuments.length} tài liệu...');
    try {
      final now = DateTime.now();
      final newDocId = _uuid.v4();
      final List<ScanPage> mergedPages = [];
      int pageCounter = 0;

      for (final doc in sourceDocuments) {
        final fullDoc = await databaseService.getDocumentById(doc.id) ?? doc;
        final sorted = List<ScanPage>.from(fullDoc.pages)
          ..sort((a, b) => a.pageIndex.compareTo(b.pageIndex));

        for (final srcPage in sorted) {
          final newOrigPath = await storageService
              .importOriginalImage(srcPage.originalImagePath);
          final newPageId = _uuid.v4();
          String? newProcPath;
          if (srcPage.processedImagePath != null) {
            newProcPath = await storageService
                .importOriginalImage(srcPage.processedImagePath!);
          }

          mergedPages.add(
            ScanPage(
              id: newPageId,
              documentId: newDocId,
              pageIndex: pageCounter++,
              originalImagePath: newOrigPath,
              processedImagePath: newProcPath,
              cropQuad: srcPage.cropQuad,
              rotationDegrees: srcPage.rotationDegrees,
              filter: srcPage.filter,
              ocrResult: srcPage.ocrResult,
              annotations: srcPage.annotations,
              updatedAt: DateTime.now(),
            ),
          );
        }
      }

      final mergedDoc = ScanDocument(
        id: newDocId,
        title: mergedTitle,
        folder: 'Tất cả tài liệu',
        tags: const ['Đã gộp'],
        createdAt: now,
        updatedAt: now,
        isDraft: false,
        pages: mergedPages,
      );
      await databaseService.upsertDocument(mergedDoc);
      await refreshLibrary();
      return mergedDoc;
    } finally {
      _setBusy(false, null);
    }
  }

  Future<ScanDocument> splitDocument({
    required ScanDocument sourceDocument,
    required List<int> selectedPageIndexes,
    required String newTitle,
  }) async {
    _setBusy(true, 'Đang tách ${selectedPageIndexes.length} trang...');
    try {
      final fullDoc =
          await databaseService.getDocumentById(sourceDocument.id) ??
              sourceDocument;
      final sorted = List<ScanPage>.from(fullDoc.pages)
        ..sort((a, b) => a.pageIndex.compareTo(b.pageIndex));

      final now = DateTime.now();
      final newDocId = _uuid.v4();
      final List<ScanPage> splitPages = [];
      int idxCounter = 0;

      for (final pageIdx in selectedPageIndexes) {
        if (pageIdx < 0 || pageIdx >= sorted.length) continue;
        final srcPage = sorted[pageIdx];
        final newOrigPath =
            await storageService.importOriginalImage(srcPage.originalImagePath);
        String? newProcPath;
        if (srcPage.processedImagePath != null) {
          newProcPath = await storageService
              .importOriginalImage(srcPage.processedImagePath!);
        }

        splitPages.add(
          ScanPage(
            id: _uuid.v4(),
            documentId: newDocId,
            pageIndex: idxCounter++,
            originalImagePath: newOrigPath,
            processedImagePath: newProcPath,
            cropQuad: srcPage.cropQuad,
            rotationDegrees: srcPage.rotationDegrees,
            filter: srcPage.filter,
            ocrResult: srcPage.ocrResult,
            annotations: srcPage.annotations,
            updatedAt: DateTime.now(),
          ),
        );
      }

      final splitDoc = ScanDocument(
        id: newDocId,
        title: newTitle,
        folder: fullDoc.folder,
        tags: [...fullDoc.tags, 'Đã tách'],
        createdAt: now,
        updatedAt: now,
        isDraft: false,
        pages: splitPages,
      );
      await databaseService.upsertDocument(splitDoc);
      await refreshLibrary();
      return splitDoc;
    } finally {
      _setBusy(false, null);
    }
  }

  void _setBusy(bool value, String? message) {
    _isLoading = value;
    _busyMessage = message;
    notifyListeners();
  }
}
