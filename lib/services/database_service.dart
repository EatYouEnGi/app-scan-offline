import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../models/scan_models.dart';

/// Dịch vụ cơ sở dữ liệu SQLite cục bộ.
/// Lưu trữ `Document` và `Page`, hỗ trợ tìm kiếm toàn văn (Full-Text Search)
/// cả có dấu và không dấu tiếng Việt, đồng thời lưu bản nháp (`is_draft = 1`)
/// để khôi phục ngay cả khi ứng dụng bị đóng giữa chừng.
class DatabaseService {
  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    final dbPath = await getDatabasesPath();
    final fullPath = p.join(dbPath, 'app_scan_offline.db');
    _db = await openDatabase(
      fullPath,
      version: 1,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await _createSchema(db);
      },
    );
    return _db!;
  }

  /// Cho phép khởi tạo SQLite trong bộ nhớ khi chạy kiểm thử tự động (Unit/Acceptance Test).
  Future<void> initializeWithDatabase(Database customDb) async {
    _db = customDb;
    await _createSchema(_db!);
  }

  Future<void> _createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS documents (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        folder TEXT NOT NULL DEFAULT 'Tất cả tài liệu',
        tags_json TEXT NOT NULL DEFAULT '[]',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        is_draft INTEGER NOT NULL DEFAULT 0,
        last_exported_pdf_path TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS pages (
        id TEXT PRIMARY KEY,
        document_id TEXT NOT NULL,
        page_index INTEGER NOT NULL,
        original_image_path TEXT NOT NULL,
        processed_image_path TEXT,
        crop_quad_json TEXT NOT NULL,
        rotation_degrees INTEGER NOT NULL DEFAULT 0,
        filter_name TEXT NOT NULL DEFAULT 'magicColor',
        ocr_text TEXT NOT NULL DEFAULT '',
        ocr_json TEXT,
        annotations_json TEXT NOT NULL DEFAULT '[]',
        updated_at TEXT NOT NULL,
        FOREIGN KEY (document_id) REFERENCES documents (id) ON DELETE CASCADE
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_pages_doc_order ON pages(document_id, page_index)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_docs_updated ON documents(is_draft, updated_at DESC)',
    );
  }

  /// Lưu hoặc cập nhật thông tin tài liệu cùng danh sách trang trong một giao dịch nguyên tử (transaction).
  Future<void> upsertDocument(ScanDocument doc) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert(
        'documents',
        doc.toDbMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      for (final page in doc.pages) {
        await txn.insert(
          'pages',
          page.toDbMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  /// Lưu hoặc cập nhật một trang đơn lẻ (ngay khi chụp, cắt, đổi bộ lọc hoặc OCR xong).
  Future<void> upsertPage(ScanPage page) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert(
        'pages',
        page.toDbMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.update(
        'documents',
        {'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [page.documentId],
      );
    });
  }

  /// Cập nhật lại toàn bộ thứ tự trang của một tài liệu (khi kéo thả đổi vị trí hoặc xóa trang).
  Future<void> replaceDocumentPages(
    String documentId,
    List<ScanPage> orderedPages,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete(
        'pages',
        where: 'document_id = ?',
        whereArgs: [documentId],
      );
      for (int i = 0; i < orderedPages.length; i++) {
        final reindexed = orderedPages[i].copyWith(
          documentId: documentId,
          pageIndex: i,
          updatedAt: DateTime.now(),
        );
        await txn.insert(
          'pages',
          reindexed.toDbMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await txn.update(
        'documents',
        {'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [documentId],
      );
    });
  }

  /// Tải tất cả tài liệu chính thức (`isDraft = false`) kèm theo các trang đúng thứ tự.
  Future<List<ScanDocument>> loadAllDocuments({bool includeDrafts = false}) async {
    final db = await database;
    final docRows = await db.query(
      'documents',
      where: includeDrafts ? null : 'is_draft = 0',
      orderBy: 'updated_at DESC',
    );

    final List<ScanDocument> result = [];
    for (final row in docRows) {
      final docId = row['id'] as String;
      final pageRows = await db.query(
        'pages',
        where: 'document_id = ?',
        whereArgs: [docId],
        orderBy: 'page_index ASC',
      );
      final pages = pageRows.map(ScanPage.fromDbMap).toList();
      result.add(ScanDocument.fromDbMap(row, pages: pages));
    }
    return result;
  }

  /// Tải danh sách bản nháp đang quét dở (`isDraft = true`) để khôi phục sau khi ứng dụng đóng.
  Future<List<ScanDocument>> loadDraftDocuments() async {
    final db = await database;
    final docRows = await db.query(
      'documents',
      where: 'is_draft = 1',
      orderBy: 'updated_at DESC',
    );
    final List<ScanDocument> drafts = [];
    for (final row in docRows) {
      final docId = row['id'] as String;
      final pageRows = await db.query(
        'pages',
        where: 'document_id = ?',
        whereArgs: [docId],
        orderBy: 'page_index ASC',
      );
      final pages = pageRows.map(ScanPage.fromDbMap).toList();
      if (pages.isNotEmpty) {
        drafts.add(ScanDocument.fromDbMap(row, pages: pages));
      }
    }
    return drafts;
  }

  /// Tải một tài liệu theo ID.
  Future<ScanDocument?> getDocumentById(String id) async {
    final db = await database;
    final rows = await db.query(
      'documents',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final pageRows = await db.query(
      'pages',
      where: 'document_id = ?',
      whereArgs: [id],
      orderBy: 'page_index ASC',
    );
    final pages = pageRows.map(ScanPage.fromDbMap).toList();
    return ScanDocument.fromDbMap(rows.first, pages: pages);
  }

  /// Xóa một tài liệu khỏi SQLite (cascade xóa các bản ghi `pages`).
  Future<void> deleteDocument(String id) async {
    final db = await database;
    await db.delete('documents', where: 'id = ?', whereArgs: [id]);
  }

  /// Tìm kiếm toàn văn trong thư viện (theo tên tài liệu, thư mục, thẻ, và toàn bộ nội dung OCR).
  /// Hỗ trợ khớp cả tiếng Việt có dấu và không dấu.
  Future<List<ScanDocument>> searchDocuments({
    required String query,
    String? folderFilter,
    String? tagFilter,
  }) async {
    final allDocs = await loadAllDocuments(includeDrafts: false);
    final normalizedQuery = _normalizeVietnamese(query.trim());

    return allDocs.where((doc) {
      if (folderFilter != null &&
          folderFilter.isNotEmpty &&
          folderFilter != 'Tất cả tài liệu' &&
          doc.folder != folderFilter) {
        return false;
      }
      if (tagFilter != null &&
          tagFilter.isNotEmpty &&
          !doc.tags.contains(tagFilter)) {
        return false;
      }
      if (normalizedQuery.isEmpty) return true;

      final titleMatch =
          _normalizeVietnamese(doc.title).contains(normalizedQuery);
      final folderMatch =
          _normalizeVietnamese(doc.folder).contains(normalizedQuery);
      final tagMatch = doc.tags
          .any((t) => _normalizeVietnamese(t).contains(normalizedQuery));
      final ocrMatch = doc.pages.any(
        (p) => _normalizeVietnamese(p.ocrResult?.fullText ?? '')
            .contains(normalizedQuery),
      );
      return titleMatch || folderMatch || tagMatch || ocrMatch;
    }).toList();
  }

  /// Trích đoạn văn bản OCR khớp với từ khóa tìm kiếm để hiển thị dưới kết quả tìm kiếm.
  static String? extractMatchingOcrSnippet(ScanDocument doc, String query) {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return null;
    final normQuery = _normalizeVietnamese(cleanQuery);

    for (final page in doc.pages) {
      final rawText = page.ocrResult?.fullText ?? '';
      if (rawText.isEmpty) continue;
      final normText = _normalizeVietnamese(rawText);
      final idx = normText.indexOf(normQuery);
      if (idx != -1) {
        final start = (idx - 30).clamp(0, rawText.length);
        final end = (idx + cleanQuery.length + 50).clamp(0, rawText.length);
        final prefix = start > 0 ? '...' : '';
        final suffix = end < rawText.length ? '...' : '';
        final snippet =
            rawText.substring(start, end).replaceAll(RegExp(r'\s+'), ' ');
        return 'Trang ${page.pageIndex + 1}: $prefix$snippet$suffix';
      }
    }
    return null;
  }

  /// Chuẩn hóa chuỗi tiếng Việt về chữ thường không dấu để tìm kiếm linh hoạt.
  static String _normalizeVietnamese(String input) {
    var str = input.toLowerCase();
    const vietnameseMap = <String, String>{
      'à': 'a', 'á': 'a', 'ạ': 'a', 'ả': 'a', 'ã': 'a',
      'â': 'a', 'ầ': 'a', 'ấ': 'a', 'ậ': 'a', 'ẩ': 'a', 'ẫ': 'a',
      'ă': 'a', 'ằ': 'a', 'ắ': 'a', 'ặ': 'a', 'ẳ': 'a', 'ẵ': 'a',
      'è': 'e', 'é': 'e', 'ẹ': 'e', 'ẻ': 'e', 'ẽ': 'e',
      'ê': 'e', 'ề': 'e', 'ế': 'e', 'ệ': 'e', 'ể': 'e', 'ễ': 'e',
      'ì': 'i', 'í': 'i', 'ị': 'i', 'ỉ': 'i', 'ĩ': 'i',
      'ò': 'o', 'ó': 'o', 'ọ': 'o', 'ỏ': 'o', 'õ': 'o',
      'ô': 'o', 'ồ': 'o', 'ố': 'o', 'ộ': 'o', 'ổ': 'o', 'ỗ': 'o',
      'ơ': 'o', 'ờ': 'o', 'ớ': 'o', 'ợ': 'o', 'ở': 'o', 'ỡ': 'o',
      'ù': 'u', 'ú': 'u', 'ụ': 'u', 'ủ': 'u', 'ũ': 'u',
      'ư': 'u', 'ừ': 'u', 'ứ': 'u', 'ự': 'u', 'ử': 'u', 'ữ': 'u',
      'ỳ': 'y', 'ý': 'y', 'ỵ': 'y', 'ỷ': 'y', 'ỹ': 'y',
      'đ': 'd',
    };
    final buffer = StringBuffer();
    for (int i = 0; i < str.length; i++) {
      final ch = str[i];
      buffer.write(vietnameseMap[ch] ?? ch);
    }
    return buffer.toString();
  }
}

