import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
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

  /// Danh sách thư mục sẵn có và các thư mục do người dùng tạo.
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

  /// Danh sách tất cả các thẻ (tags) đang có trong thư viện.
  List<String> get availableTags {
    final set = <String>{};
    for (final doc in _documents) {
      set.addAll(doc.tags);
    }
    final list = set.toList()..sort();
    return list;
  }

  /// Khởi tạo dữ liệu, kiểm tra khóa sinh trắc học và tìm bản nháp chưa hoàn tất.
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

  /// Làm mới danh sách tài liệu theo bộ lọc tìm kiếm và kiểm tra các bản nháp.
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

  /// Khởi tạo phiên quét nháp mới (tự động lưu SQLite với `isDraft = true`).
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

  /// Khôi phục một bản nháp bị đóng giữa chừng để tiếp tục chỉnh sửa.
  Future<ScanDocument> resumeDraft(ScanDocument draft) async {
    final latest = await databaseService.getDocumentById(draft.id) ?? draft;
    _activeDraft = latest;
    notifyListeners();
    return latest;
  }

  /// Chuyển bản nháp thành tài liệu chính thức trong thư viện.
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

  /// Thêm một hoặc nhiều ảnh chụp / ảnh chọn từ thư viện vào tài liệu.
  /// Tự động:
  /// 1) Sao chép ảnh vào kho `originals/` bất biến
  /// 2) Nhận diện 4 góc giấy
  /// 3) Cắt phối cảnh + áp bộ lọc mặc định (`magicColor`)
  /// 4) Chạy OCR ngoại tuyến tiếng Việt/Anh
  /// 5) Lưu tức thì vào SQLite để không mất dữ liệu nếu ứng dụng đóng.
  Future<ScanDocument> addImagesToDocument({
    required ScanDocument document,
    required List<String> sourceImagePaths,
    ScanFilterType defaultFilter = ScanFilterType.magicColor,
    bool runOcrImmediately = true,
  }) async {
    var currentDoc =
        await databaseService.getDocumentById(document.id) ?? document;
    final existingPages = List<ScanPage>.from(currentDoc.pages);

    for (int i = 0; i < sourceImagePaths.length; i++) {
      _setBusy(
        true,
        'Đang xử lý trang ${i + 1}/${sourceImagePaths.length} (Nhận diện mép & OCR)...',
      );
      try {
        final origPath =
            await storageService.importOriginalImage(sourceImagePaths[i]);
        final detectedQuad =
            await visionService.detectDocumentCorners(origPath);
        final pageId = _uuid.v4();

        final processedBytes = await visionService.processPageImage(
          originalImagePath: origPath,
          cropQuad: detectedQuad,
          rotationDegrees: 0,
          filter: defaultFilter,
        );
        final procPath =
            await storageService.saveProcessedBytes(pageId, processedBytes);

        OcrResult? ocr;
        if (runOcrImmediately) {
          ocr = await ocrService.recognizePageImage(procPath);
        }

        final newPage = ScanPage(
          id: pageId,
          documentId: currentDoc.id,
          pageIndex: existingPages.length,
          originalImagePath: origPath,
          processedImagePath: procPath,
          cropQuad: detectedQuad,
          rotationDegrees: 0,
          filter: defaultFilter,
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

  /// Chỉnh sửa không phá hủy (non-destructive) một trang:
  /// Đọc lại từ `originalImagePath`, áp dụng `cropQuad`, `rotationDegrees`, `filter` mới,
  /// cập nhật ảnh `processed/` và chạy lại OCR nếu hình học trang thay đổi.
  Future<ScanPage> updatePageTransform({
    required ScanPage page,
    CropQuad? cropQuad,
    int? rotationDegrees,
    ScanFilterType? filter,
    List<PageAnnotation>? annotations,
    bool rerunOcr = true,
  }) async {
    _setBusy(true, 'Đang áp dụng chỉnh sửa trang & cập nhật OCR...');
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
        updatedOcr = await ocrService.recognizePageImage(newProcessedPath);
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

  /// Chụp lại (Retake) một trang tại đúng vị trí `pageIndex` hiện tại.
  Future<ScanPage> retakePage({
    required ScanPage oldPage,
    required String newSourceImagePath,
  }) async {
    _setBusy(true, 'Đang thay thế trang chụp lại...');
    try {
      final newOrigPath =
          await storageService.importOriginalImage(newSourceImagePath);
      final detectedQuad =
          await visionService.detectDocumentCorners(newOrigPath);
      final processedBytes = await visionService.processPageImage(
        originalImagePath: newOrigPath,
        cropQuad: detectedQuad,
        rotationDegrees: 0,
        filter: oldPage.filter,
      );
      final newProcPath =
          await storageService.saveProcessedBytes(oldPage.id, processedBytes);
      final ocr = await ocrService.recognizePageImage(newProcPath);

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

  /// Đổi thứ tự trang trong tài liệu (kéo thả).
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

  /// Xóa một trang khỏi tài liệu và đánh lại số thứ tự các trang còn lại.
  Future<ScanDocument?> deletePage(ScanDocument doc, ScanPage pageToDelete) async {
    await storageService.deletePageFiles(
      originalPath: pageToDelete.originalImagePath,
      processedPath: pageToDelete.processedImagePath,
    );
    final remaining = doc.pages
        .where((p) => p.id != pageToDelete.id)
        .toList()
      ..sort((a, b) => a.pageIndex.compareTo(b.pageIndex));

    if (remaining.isEmpty) {
      await deleteDocument(doc);
      return null;
    }

    await databaseService.replaceDocumentPages(doc.id, remaining);
    await refreshLibrary();
    return databaseService.getDocumentById(doc.id);
  }

  /// Cập nhật tên, thư mục và thẻ (tags) của tài liệu.
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

  /// Xóa toàn bộ tài liệu và các tệp ảnh vật lý đi kèm.
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

  /// Tạo PDF nhiều trang có lớp chữ OCR ẩn (searchable PDF) và lưu vào vùng xuất cục bộ.
  Future<String> exportSearchablePdf({
    required ScanDocument document,
    PaperSizePreset paperSize = PaperSizePreset.a4,
    PdfQualityPreset quality = PdfQualityPreset.medium,
    bool openShareSheet = true,
  }) async {
    _setBusy(true, 'Đang tạo PDF nhiều trang kèm lớp văn bản tìm kiếm...');
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
          [XFile(savedPath, mimeType: 'application/pdf')],
          subject: latestDoc.title,
        );
      }
      return savedPath;
    } finally {
      _setBusy(false, null);
    }
  }

  /// Xuất các trang của tài liệu dưới dạng tệp ảnh JPG qua trình chia sẻ hệ điều hành.
  Future<void> shareDocumentImages(ScanDocument document) async {
    final sorted = List<ScanPage>.from(document.pages)
      ..sort((a, b) => a.pageIndex.compareTo(b.pageIndex));
    final files = sorted
        .map((p) => XFile(p.displayImagePath, mimeType: 'image/jpeg'))
        .toList();
    if (files.isEmpty) return;
    await Share.shareXFiles(files, subject: document.title);
  }

  // ===========================================================================
  // CÔNG CỤ PDF MỞ RỘNG (GIAI ĐOẠN 4: Nhập PDF, Gộp, Tách)
  // ===========================================================================

  /// Nhập một tệp PDF có sẵn trên thiết bị thành tài liệu `ScanDocument` có thể chỉnh sửa và OCR.
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
          'Đang nhập trang PDF ${i + 1}/${pagePngs.length}...',
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

  /// Gộp (Merge) nhiều tài liệu đã chọn thành một tài liệu nhiều trang mới.
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

  /// Tách (Split) các trang được chọn từ một tài liệu thành một tài liệu độc lập.
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

