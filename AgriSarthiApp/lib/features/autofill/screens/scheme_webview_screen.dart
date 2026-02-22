import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/services/farmer_service.dart';
import '../services/smart_form_mapper.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SchemeWebViewScreen
// The 5-phase AutoFill pipeline orchestrator.
// ─────────────────────────────────────────────────────────────────────────────

class SchemeWebViewScreen extends StatefulWidget {
  final String schemeId;
  final String schemeName;
  final String portalUrl;

  const SchemeWebViewScreen({
    super.key,
    required this.schemeId,
    required this.schemeName,
    required this.portalUrl,
  });

  @override
  State<SchemeWebViewScreen> createState() => _SchemeWebViewScreenState();
}

class _SchemeWebViewScreenState extends State<SchemeWebViewScreen> {
  // ── State ──
  late WebViewController _webController;
  final FarmerService _farmerService = FarmerService();

  bool _pageLoaded = false;
  bool _isProcessing = false;
  bool _formFilled = false;

  String _statusText = 'Loading portal...';
  double _progress = 0.0;

  List<FormMapping> _mappings = [];

  // ── JS scripts (loaded from assets once) ──
  String? _domExtractorJs;
  String? _formFillerJs;

  @override
  void initState() {
    super.initState();
    _loadAssets();
    _initWebView();
  }

  Future<void> _loadAssets() async {
    _domExtractorJs =
        await rootBundle.loadString('assets/scripts/dom_extractor.js');
    _formFillerJs =
        await rootBundle.loadString('assets/scripts/form_filler.js');
  }

  void _initWebView() {
    _webController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) {
          setState(() {
            _pageLoaded = false;
            _formFilled = false;
            _statusText = 'Loading portal...';
            _progress = 0.1;
          });
        },
        onProgress: (p) => setState(() => _progress = p / 100.0),
        onPageFinished: (_) {
          setState(() {
            _pageLoaded = true;
            _progress = 1.0;
            _statusText = 'Portal loaded. Tap Auto Fill to begin.';
          });
        },
        onWebResourceError: (err) {
          setState(() => _statusText = 'Load error: ${err.description}');
        },
      ))
      ..addJavaScriptChannel(
        'AutofillChannel',
        onMessageReceived: _handleJsMessage,
      )
      ..loadRequest(Uri.parse(widget.portalUrl));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Phase 1 → Phase 3 → Phase 4
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _runAutoFillPipeline() async {
    if (!_pageLoaded || _isProcessing) return;

    setState(() {
      _isProcessing = true;
      _statusText = 'Phase 1: Extracting form fields...';
      _progress = 0.15;
    });

    // Phase 1: inject DOM extractor
    if (_domExtractorJs == null) {
      _domExtractorJs =
          await rootBundle.loadString('assets/scripts/dom_extractor.js');
    }
    await _webController.runJavaScript(_domExtractorJs!);

    // Wait for JS callback (_handleJsMessage will continue the pipeline)
  }

  void _handleJsMessage(JavaScriptMessage msg) {
    try {
      final json = jsonDecode(msg.message) as Map<String, dynamic>;

      // Fill-complete event
      if (json['event'] == 'fill_complete') {
        final filled = json['filled'] ?? 0;
        setState(() {
          _formFilled = true;
          _isProcessing = false;
          _statusText =
              'Phase 4 complete: $filled field(s) filled. Review below.';
          _progress = 1.0;
        });
        _showReviewSheet();
        return;
      }

      // DOM extraction result
      final fieldsList = json['fields'] as List<dynamic>? ?? [];
      final fields = fieldsList
          .map((f) => DomField.fromJson(f as Map<String, dynamic>))
          .toList();

      debugPrint('AutoFill Phase 1: Extracted ${fields.length} fields');

      // Phase 2 + 3: Smart mapping (runs on isolate to avoid UI jank)
      _runMappingPhase(fields);
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _statusText = 'Error during auto-fill: $e';
      });
      debugPrint('AutofillChannel error: $e\nRaw: ${msg.message}');
    }
  }

  Future<void> _runMappingPhase(List<DomField> fields) async {
    setState(() {
      _statusText = 'Phase 2–3: Mapping your data...';
      _progress = 0.5;
    });

    // Phase 2: Fetch farmer profile
    final profile = await _farmerService.getFarmerProfile();
    if (profile == null) {
      setState(() {
        _isProcessing = false;
        _statusText =
            'Could not load your profile. Please complete your profile first.';
      });
      return;
    }

    // Phase 3: Smart mapping (Stage 1 + 2)
    final mappings = SmartFormMapper.map(fields, profile);
    setState(() {
      _mappings = mappings;
      _statusText = 'Phase 4: Injecting values into form...';
      _progress = 0.75;
    });

    // Phase 4: Inject values via form_filler.js
    await _injectMappings(mappings);
  }

  Future<void> _injectMappings(List<FormMapping> mappings) async {
    if (_formFillerJs == null) {
      _formFillerJs =
          await rootBundle.loadString('assets/scripts/form_filler.js');
    }

    // Build the JSON array for the filler
    final injectList =
        mappings.where((m) => m.isMapped).map((m) => m.toJson()).toList();
    final jsonStr = jsonEncode(injectList).replaceAll("'", "\\'");

    // Replace placeholder and inject
    final fillerJs =
        _formFillerJs!.replaceAll("'MAPPINGS_PLACEHOLDER'", "'$jsonStr'");
    await _webController.runJavaScript(fillerJs);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Phase 5: Review sheet
  // ═══════════════════════════════════════════════════════════════════════════

  void _showReviewSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReviewSheet(
        mappings: _mappings,
        onEdit: (id, newVal) {
          setState(() {
            _mappings = _mappings.map((m) {
              if (m.id == id) {
                return FormMapping(
                  id: m.id,
                  name: m.name,
                  label: m.label,
                  type: m.type,
                  section: m.section,
                  value: newVal,
                  options: m.options,
                );
              }
              return m;
            }).toList();
          });
        },
        onConfirm: () {
          Navigator.pop(context);
          _injectMappings(_mappings);
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // UI
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      appBar: _buildAppBar(),
      body: Stack(
        children: [
          // ── WebView ──
          Column(
            children: [
              // Status bar
              _buildStatusBar(),
              // WebView fills remaining space
              Expanded(child: WebViewWidget(controller: _webController)),
            ],
          ),

          // ── Processing overlay ──
          if (_isProcessing) _buildProcessingOverlay(),

          // ── Persistent review banner after fill ──
          if (_formFilled && !_isProcessing) _buildReviewBanner(),
        ],
      ),
      // ── Auto Fill FAB ──
      floatingActionButton: _pageLoaded && !_formFilled
          ? FloatingActionButton.extended(
              onPressed: _runAutoFillPipeline,
              backgroundColor: const Color(0xFF1A237E),
              icon: const Icon(Icons.auto_fix_high, color: Colors.white),
              label: const Text(
                'Auto Fill',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          : null,
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF1A237E),
      foregroundColor: Colors.white,
      elevation: 0,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.schemeName,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            widget.portalUrl,
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withOpacity(0.7),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Reload',
          onPressed: () {
            setState(() {
              _formFilled = false;
              _mappings = [];
              _statusText = 'Reloading...';
            });
            _webController.reload();
          },
        ),
        IconButton(
          icon: const Icon(Icons.open_in_browser),
          tooltip: 'Open in browser',
          onPressed: () {
            // Could launch external browser if needed
          },
        ),
      ],
    );
  }

  Widget _buildStatusBar() {
    return Container(
      color: const Color(0xFFEEF0FB),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _statusText,
              style: TextStyle(
                fontSize: 12,
                color: const Color(0xFF1A237E).withOpacity(0.8),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          if (_progress < 1.0 || _isProcessing)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                value: _progress < 1.0 ? _progress : null,
                strokeWidth: 2,
                color: const Color(0xFF1A237E),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildProcessingOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.45),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 40),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 56,
                height: 56,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: Color(0xFF1A237E),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'AutoFill Agent Running',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A237E),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _statusText,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: _progress,
                backgroundColor: Colors.grey.shade200,
                color: const Color(0xFF1A237E),
                minHeight: 4,
                borderRadius: BorderRadius.circular(4),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReviewBanner() {
    final mapped = _mappings.where((m) => m.isMapped).length;
    final total = _mappings.length;
    return Positioned(
      bottom: 16,
      left: 16,
      right: 16,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Form filled!',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      '$mapped/$total fields filled automatically',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.85),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              OutlinedButton(
                onPressed: _showReviewSheet,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white70),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: const Size(0, 32),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'Review',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Review Sheet — Phase 5
// ═══════════════════════════════════════════════════════════════════════════

class _ReviewSheet extends StatefulWidget {
  final List<FormMapping> mappings;
  final void Function(String id, String newVal) onEdit;
  final VoidCallback onConfirm;

  const _ReviewSheet({
    required this.mappings,
    required this.onEdit,
    required this.onConfirm,
  });

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  late List<FormMapping> _items;

  @override
  void initState() {
    super.initState();
    _items = List.of(widget.mappings);
  }

  @override
  Widget build(BuildContext context) {
    final mapped = _items.where((m) => m.isMapped).length;
    final total = _items.length;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A237E).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.rate_review_outlined,
                      color: Color(0xFF1A237E),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Review Auto-Filled Fields',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1B1B1B),
                          ),
                        ),
                        Text(
                          '$mapped of $total fields filled',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: Colors.grey.shade500),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 20),
            // Fields
            Expanded(
              child: ListView.separated(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                itemCount: _items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _FieldTile(
                  mapping: _items[i],
                  onEdit: (newVal) {
                    setState(() {
                      _items[i] = FormMapping(
                        id: _items[i].id,
                        name: _items[i].name,
                        label: _items[i].label,
                        type: _items[i].type,
                        section: _items[i].section,
                        value: newVal,
                        options: _items[i].options,
                      );
                    });
                    widget.onEdit(_items[i].id, newVal);
                  },
                ),
              ),
            ),
            // Confirm button
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: widget.onConfirm,
                  icon: const Icon(Icons.send_rounded, size: 20),
                  label: const Text(
                    'Confirm and Re-fill Form',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A237E),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldTile extends StatefulWidget {
  final FormMapping mapping;
  final void Function(String) onEdit;

  const _FieldTile({required this.mapping, required this.onEdit});

  @override
  State<_FieldTile> createState() => _FieldTileState();
}

class _FieldTileState extends State<_FieldTile> {
  late TextEditingController _ctrl;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
      text: widget.mapping.isMapped ? widget.mapping.value.toString() : '',
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.mapping;
    final isMapped = m.isMapped;

    return Container(
      decoration: BoxDecoration(
        color: isMapped ? const Color(0xFFF8FFFE) : const Color(0xFFFFF8F0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isMapped ? const Color(0xFFC8E6C9) : const Color(0xFFFFCCBC),
          width: 1,
        ),
      ),
      child: _editing
          ? Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    m.label.isNotEmpty ? m.label : m.name,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade500,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _ctrl,
                          autofocus: true,
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.check, color: Color(0xFF2E7D32)),
                        onPressed: () {
                          widget.onEdit(_ctrl.text);
                          setState(() => _editing = false);
                        },
                      ),
                    ],
                  ),
                ],
              ),
            )
          : ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              leading: Icon(
                isMapped ? Icons.check_circle : Icons.error_outline,
                color: isMapped
                    ? const Color(0xFF2E7D32)
                    : const Color(0xFFE65100),
                size: 20,
              ),
              title: Text(
                m.label.isNotEmpty ? m.label : m.name,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1B1B1B),
                ),
              ),
              subtitle: Text(
                isMapped ? m.value.toString() : 'Not filled — tap to add',
                style: TextStyle(
                  fontSize: 12,
                  color:
                      isMapped ? Colors.grey.shade600 : const Color(0xFFE65100),
                ),
              ),
              trailing: IconButton(
                icon: Icon(Icons.edit_outlined,
                    size: 18, color: Colors.grey.shade500),
                onPressed: () => setState(() => _editing = true),
              ),
            ),
    );
  }
}
