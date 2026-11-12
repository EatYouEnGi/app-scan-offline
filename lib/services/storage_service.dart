import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class StorageException implements Exception {
  final String message;
  const StorageException(this.message);

  @override
  String toString() => message;
}

/// Quản lý vùng lưu trữ riêng biệt của ứng dụng trên thiết bị (offline 100%).
/// Đảm bảo ảnh gốc trong thư mục `originals/` không bao giờ bị ghi đè khi chỉnh sửa.
class StorageService {
  final Uuid _uuid = const Uuid();
  Directory? _baseDir;

  late Directory _originalsDir;
  late Directory _processedDir;
  late Directory _exportsDir;
  late Directory _signaturesDir;

  bool _initialized = false;

  Future<void> initialize({Directory? overrideBaseDir}) async {
    if (_initialized && overrideBaseDir == null) return;
    try {
      _baseDir = overrideBaseDir ?? await getApplicationDocumentsDirectory();
      final root = Directory(p.join(_baseDir!.path, 'app_scan_vault'));
      _originalsDir = Directory(p.join(root.path, 'originals'));
      _processedDir = Directory(p.join(root.path, 'processed'));
      _exportsDir = Directory(p.join(root.path, 'exports'));
      _signaturesDir = Directory(p.join(root.path, 'signatures'));

      await _originalsDir.create(recursive: true);
      await _processedDir.create(recursive: true);
      await _exportsDir.create(recursive: true);
      await _signaturesDir.create(recursive: true);
      _initialized = true;
    } on FileSystemException catch (e) {
      throw StorageException(
        'Không thể khởi tạo vùng lưu trữ cục bộ (có thể bộ nhớ thiết bị đã đầy): ${e.message}',
      );
    }
  }

  Directory get originalsDir => _originalsDir;
  Directory get processedDir => _processedDir;
  Directory get exportsDir => _exportsDir;
  Directory get signaturesDir => _signaturesDir;

  /// Sao chép ảnh chụp hoặc ảnh nhập vào kho `originals/` bất biến.
  Future<String> importOriginalImage(String sourcePath) async {
    await initialize();
    final src = File(sourcePath);
    if (!await src.exists()) {
      throw const StorageException('Tệp ảnh nguồn không tồn tại hoặc đã bị xóa.');
    }
    final ext = p.extension(sourcePath).isNotEmpty
        ? p.extension(sourcePath).toLowerCase()
        : '.jpg';
    final fileName = 'orig_${_uuid.v4()}$ext';
    final destPath = p.join(_originalsDir.path, fileName);

    try {
      final copied = await src.copy(destPath);
      final len = await copied.length();
      if (len == 0) {
        await copied.delete();
        throw const StorageException('Ảnh nguồn bị rỗng hoặc thiếu dung lượng lưu trữ.');
      }
      return copied.path;
    } on FileSystemException catch (e) {
      throw StorageException(
        'Không đủ dung lượng bộ nhớ khi lưu ảnh gốc: ${e.message}',
      );
    }
  }

  /// Lưu dữ liệu byte ảnh gốc mới (ví dụ khi tách trang từ PDF nhập vào).
  Future<String> saveOriginalBytes(Uint8List bytes, {String ext = '.png'}) async {
    await initialize();
    if (bytes.isEmpty) {
      throw const StorageException('Dữ liệu ảnh trống.');
    }
    final fileName = 'orig_${_uuid.v4()}$ext';
    final destPath = p.join(_originalsDir.path, fileName);
    return _writeBytesAtomically(destPath, bytes);
  }

  /// Lưu ảnh đã qua cắt phối cảnh / xoay / lọc vào thư mục `processed/`
  /// mà KHÔNG chạm tới tệp trong `originals/`.
  Future<String> saveProcessedBytes(
    String pageId,
    Uint8List bytes, {
    String ext = '.jpg',
  }) async {
    await initialize();
    final fileName = 'proc_${pageId}_${DateTime.now().millisecondsSinceEpoch}$ext';
    final destPath = p.join(_processedDir.path, fileName);
    return _writeBytesAtomically(destPath, bytes);
  }

  /// Lưu chữ ký PNG trong suốt vào thư mục `signatures/`.
  Future<String> saveSignatureBytes(Uint8List pngBytes) async {
    await initialize();
    final fileName = 'sig_${_uuid.v4()}.png';
    final destPath = p.join(_signaturesDir.path, fileName);
    return _writeBytesAtomically(destPath, pngBytes);
  }

  /// Lưu tệp PDF xuất ra theo cơ chế ghi tạm (`.tmp`) rồi đổi tên nguyên tử
  /// để tránh hỏng file nếu ứng dụng bị đóng đột ngột giữa lúc xuất.
  Future<String> saveExportedPdf(String documentTitle, Uint8List pdfBytes) async {
    await initialize();
    final sanitized = documentTitle
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .trim();
    final baseName = sanitized.isEmpty ? 'Tai_lieu_scan' : sanitized;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final destPath = p.join(_exportsDir.path, '${baseName}_$timestamp.pdf');
    return _writeBytesAtomically(destPath, pdfBytes);
  }

  /// Ghi tệp an toàn qua file tạm `.tmp` rồi rename sang đích.
  Future<String> _writeBytesAtomically(String destPath, Uint8List bytes) async {
    final tmpPath = '$destPath.tmp';
    final tmpFile = File(tmpPath);
    try {
      await tmpFile.writeAsBytes(bytes, flush: true);
      final writtenLength = await tmpFile.length();
      if (writtenLength != bytes.length) {
        await tmpFile.delete();
        throw const StorageException(
          'Thiết bị thiếu dung lượng lưu trữ để hoàn tất ghi tệp.',
        );
      }
      final finalFile = await tmpFile.rename(destPath);
      return finalFile.path;
    } on FileSystemException catch (e) {
      if (await tmpFile.exists()) {
        try {
          await tmpFile.delete();
        } catch (_) {}
      }
      throw StorageException(
        'Lỗi ghi tệp (kiểm tra dung lượng trống trên thiết bị): ${e.message}',
      );
    }
  }

  /// Xóa tệp bộ nhớ đệm đã xử lý cũ khi cập nhật bộ lọc/cắt mới (không xóa ảnh gốc).
  Future<void> deleteProcessedFileIfExists(String? processedPath) async {
    if (processedPath == null || processedPath.isEmpty) return;
    await initialize();
    // Bảo vệ an toàn: không bao giờ xóa tệp nằm trong thư mục originals qua hàm này.
    if (p.isWithin(_originalsDir.path, processedPath)) {
      return;
    }
    final file = File(processedPath);
    if (await file.exists()) {
      try {
        await file.delete();
      } catch (_) {}
    }
  }

  /// Xóa toàn bộ tệp vật lý của một trang khi người dùng chủ động xóa trang/tài liệu.
  Future<void> deletePageFiles({
    required String originalPath,
    String? processedPath,
  }) async {
    await deleteProcessedFileIfExists(processedPath);
    final orig = File(originalPath);
    if (await orig.exists()) {
      try {
        await orig.delete();
      } catch (_) {}
    }
  }
}

