import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../models/scan_models.dart';
import '../services/benchmark_service.dart';
import '../state/app_state.dart';
import 'document_detail_screen.dart';

/// Màn hình Công cụ PDF Mở rộng (Giai đoạn 4) & Kiểm chuẩn 30 mẫu (Giai đoạn 1 & 3):
/// - Nhập tệp PDF có sẵn từ thiết bị (kiểm tra an toàn PDF hỏng).
/// - Gộp nhiều tài liệu thành một PDF.
/// - Tách trang từ tài liệu nhiều trang thành tài liệu mới.
/// - Nén PDF theo mức dung lượng.
/// - Chạy bộ kiểm định tự động 30 mẫu chuẩn (>= 27/30 mép giấy & CER <= 5%).
class PdfToolsScreen extends StatefulWidget {
  final AppState appState;

  const PdfToolsScreen({
    super.key,
    required this.appState,
  });

  @override
  State<PdfToolsScreen> createState() => _PdfToolsScreenState();
}

class _PdfToolsScreenState extends State<PdfToolsScreen> {
  BenchmarkSummaryReport? _benchmarkReport;
  bool _runningBenchmark = false;

  Future<void> _importPdfFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
      );
      if (result == null ||
          result.files.isEmpty ||
          result.files.single.path == null) {
        return;
      }

      final filePath = result.files.single.path!;
      final baseTitle = p.basenameWithoutExtension(filePath);

      final importedDoc = await widget.appState.importExistingPdf(
        pdfPath: filePath,
        customTitle: baseTitle.isEmpty ? 'PDF Nhập' : baseTitle,
      );

      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DocumentDetailScreen(
            appState: widget.appState,
            initialDocument: importedDoc,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade700,
          content: Text('Không thể nhập PDF: $e'),
        ),
      );
    }
  }

  Future<void> _showMergeDocumentsDialog() async {
    final allDocs = widget.appState.documents;
    if (allDocs.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cần ít nhất 2 tài liệu trong thư viện để thực hiện Gộp PDF.'),
        ),
      );
      return;
    }

    final selectedIds = <String>{};
    final titleCtrl = TextEditingController(
      text: 'Tài liệu gộp (${DateTime.now().day}/${DateTime.now().month})',
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('Gộp nhiều tài liệu'),
              content: SizedBox(
                width: 380,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: titleCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Tên tài liệu sau khi gộp',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: allDocs.length,
                        itemBuilder: (_, idx) {
                          final d = allDocs[idx];
                          final checked = selectedIds.contains(d.id);
                          return CheckboxListTile(
                            value: checked,
                            title: Text(d.title),
                            subtitle: Text('${d.pageCount} trang'),
                            onChanged: (val) {
                              setDialogState(() {
                                if (val == true) {
                                  selectedIds.add(d.id);
                                } else {
                                  selectedIds.remove(d.id);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Hủy'),
                ),
                FilledButton(
                  onPressed: selectedIds.length < 2
                      ? null
                      : () => Navigator.of(ctx).pop(true),
                  child: Text('Gộp (${selectedIds.length})'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true || !mounted) return;
    final chosenDocs =
        allDocs.where((d) => selectedIds.contains(d.id)).toList();

    final merged = await widget.appState.mergeDocuments(
      sourceDocuments: chosenDocs,
      mergedTitle: titleCtrl.text.trim().isEmpty
          ? 'Tài liệu đã gộp'
          : titleCtrl.text.trim(),
    );

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DocumentDetailScreen(
          appState: widget.appState,
          initialDocument: merged,
        ),
      ),
    );
  }

  Future<void> _showSplitDocumentDialog() async {
    final multiPageDocs =
        widget.appState.documents.where((d) => d.pageCount >= 2).toList();
    if (multiPageDocs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cần ít nhất 1 tài liệu có từ 2 trang trở lên để Tách trang.'),
        ),
      );
      return;
    }

    ScanDocument selectedDoc = multiPageDocs.first;
    final selectedPageIndexes = <int>{0};
    final titleCtrl =
        TextEditingController(text: '${selectedDoc.title} (Bản tách)');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('Tách trang tài liệu'),
              content: SizedBox(
                width: 380,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<ScanDocument>(
                      value: selectedDoc,
                      decoration: const InputDecoration(
                        labelText: 'Chọn tài liệu gốc',
                        border: OutlineInputBorder(),
                      ),
                      items: multiPageDocs
                          .map(
                            (d) => DropdownMenuItem(
                              value: d,
                              child: Text('${d.title} (${d.pageCount} trang)'),
                            ),
                          )
                          .toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() {
                            selectedDoc = val;
                            selectedPageIndexes
                              ..clear()
                              ..add(0);
                            titleCtrl.text = '${val.title} (Bản tách)';
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: titleCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Tên tài liệu mới sau khi tách',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Chọn các trang muốn trích xuất:',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: List.generate(selectedDoc.pageCount, (idx) {
                        final chosen = selectedPageIndexes.contains(idx);
                        return FilterChip(
                          label: Text('Trang ${idx + 1}'),
                          selected: chosen,
                          onSelected: (v) {
                            setDialogState(() {
                              if (v) {
                                selectedPageIndexes.add(idx);
                              } else {
                                selectedPageIndexes.remove(idx);
                              }
                            });
                          },
                        );
                      }),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Hủy'),
                ),
                FilledButton(
                  onPressed: selectedPageIndexes.isEmpty
                      ? null
                      : () => Navigator.of(ctx).pop(true),
                  child: Text('Tách (${selectedPageIndexes.length} trang)'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true || !mounted) return;
    final sortedIdx = selectedPageIndexes.toList()..sort();
    final splitDoc = await widget.appState.splitDocument(
      sourceDocument: selectedDoc,
      selectedPageIndexes: sortedIdx,
      newTitle:
          titleCtrl.text.trim().isEmpty ? 'Bản tách' : titleCtrl.text.trim(),
    );

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DocumentDetailScreen(
          appState: widget.appState,
          initialDocument: splitDoc,
        ),
      ),
    );
  }

  Future<void> _showCompressExportDialog() async {
    final docs = widget.appState.documents;
    if (docs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chưa có tài liệu nào trong thư viện.')),
      );
      return;
    }

    ScanDocument selectedDoc = docs.first;
    PaperSizePreset paper = PaperSizePreset.a4;
    PdfQualityPreset quality = PdfQualityPreset.compressed;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('Nén PDF & Chọn khổ giấy'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<ScanDocument>(
                    value: selectedDoc,
                    decoration: const InputDecoration(
                      labelText: 'Tài liệu',
                      border: OutlineInputBorder(),
                    ),
                    items: docs
                        .map(
                          (d) => DropdownMenuItem(
                            value: d,
                            child: Text(d.title),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setDialogState(() => selectedDoc = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<PaperSizePreset>(
                    value: paper,
                    decoration: const InputDecoration(
                      labelText: 'Khổ giấy',
                      border: OutlineInputBorder(),
                    ),
                    items: PaperSizePreset.values
                        .map(
                          (p) => DropdownMenuItem(
                            value: p,
                            child: Text(p.label),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setDialogState(() => paper = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<PdfQualityPreset>(
                    value: quality,
                    decoration: const InputDecoration(
                      labelText: 'Mức nén dung lượng',
                      border: OutlineInputBorder(),
                    ),
                    items: PdfQualityPreset.values
                        .map(
                          (q) => DropdownMenuItem(
                            value: q,
                            child: Text(q.label),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setDialogState(() => quality = v);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Hủy'),
                ),
                FilledButton.icon(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  icon: const Icon(Icons.compress),
                  label: const Text('Tạo & Chia sẻ PDF nén'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true || !mounted) return;
    await widget.appState.exportSearchablePdf(
      document: selectedDoc,
      paperSize: paper,
      quality: quality,
      openShareSheet: true,
    );
  }

  Future<void> _runBenchmark() async {
    setState(() => _runningBenchmark = true);
    try {
      final report =
          await widget.appState.benchmarkService.run30SampleBenchmark();
      if (!mounted) return;
      setState(() => _benchmarkReport = report);
    } finally {
      if (mounted) setState(() => _runningBenchmark = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Công cụ PDF & Kiểm chuẩn'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Bộ công cụ PDF ngoại tuyến (Giai đoạn 4)',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 10),
          _toolCard(
            icon: Icons.upload_file_outlined,
            color: Colors.indigo,
            title: 'Nhập tệp PDF có sẵn',
            subtitle:
                'Chuyển PDF có sẵn thành các trang ảnh để xoay, lọc, ký tên, OCR hoặc tách trang.',
            onTap: _importPdfFile,
          ),
          _toolCard(
            icon: Icons.merge_type,
            color: Colors.teal,
            title: 'Gộp nhiều tài liệu PDF',
            subtitle:
                'Ghép nối các tài liệu riêng lẻ trong thư viện thành một bộ hồ sơ PDF nhiều trang.',
            onTap: _showMergeDocumentsDialog,
          ),
          _toolCard(
            icon: Icons.call_split,
            color: Colors.deepOrange,
            title: 'Tách trang PDF',
            subtitle:
                'Trích xuất các trang bất kỳ từ một tài liệu nhiều trang sang tài liệu độc lập.',
            onTap: _showSplitDocumentDialog,
          ),
          _toolCard(
            icon: Icons.compress,
            color: Colors.purple,
            title: 'Nén dung lượng & Chọn khổ giấy (A4 / Letter / Hóa đơn)',
            subtitle:
                'Tối ưu hóa kích thước tệp PDF để gửi nhanh qua tin nhắn hoặc lưu trữ tiết kiệm.',
            onTap: _showCompressExportDialog,
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Kiểm chuẩn 30 ảnh mẫu & Tiêu chí nghiệm thu',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const Text(
                      'Đánh giá tự động tiêu chí nhận diện mép >= 27/30 mẫu và CER <= 5%.',
                      style: TextStyle(fontSize: 13, color: Colors.black54),
                    ),
                  ],
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: _runningBenchmark ? null : _runBenchmark,
                icon: _runningBenchmark
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.fact_check_outlined),
                label: const Text('Chạy 30 mẫu'),
              ),
            ],
          ),
          if (_benchmarkReport != null) ...[
            const SizedBox(height: 14),
            _buildBenchmarkSummaryCard(_benchmarkReport!),
          ],
        ],
      ),
    );
  }

  Widget _toolCard({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.14),
          child: Icon(icon, color: color),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }

  Widget _buildBenchmarkSummaryCard(BenchmarkSummaryReport report) {
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  report.passedEdgeCriterion && report.passedOcrCriterion
                      ? Icons.verified
                      : Icons.warning_amber_rounded,
                  color: report.passedEdgeCriterion && report.passedOcrCriterion
                      ? Colors.green.shade700
                      : Colors.orange.shade800,
                ),
                const SizedBox(width: 8),
                Text(
                  'Kết quả kiểm định: ${report.passedEdgeSamples}/${report.totalSamples} mẫu đạt chuẩn',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '• Độ chính xác góc trung bình: ${(report.averageEdgeSimilarity * 100).toStringAsFixed(1)}% (Mục tiêu: >= 27/30 mẫu)',
            ),
            Text(
              '• Tỷ lệ lỗi ký tự (CER) Tiếng Việt: ${(report.vietnameseCer * 100).toStringAsFixed(2)}% (Mục tiêu <= 5.0%)',
            ),
            Text(
              '• Tỷ lệ lỗi ký tự (CER) Tiếng Anh: ${(report.englishCer * 100).toStringAsFixed(2)}% (Mục tiêu <= 5.0%)',
            ),
          ],
        ),
      ),
    );
  }
}

