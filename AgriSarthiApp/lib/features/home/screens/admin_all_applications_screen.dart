import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/services/admin_service.dart';
import '../../../core/theme/app_theme.dart';

class AdminAllApplicationsScreen extends StatefulWidget {
  const AdminAllApplicationsScreen({super.key});

  @override
  State<AdminAllApplicationsScreen> createState() =>
      _AdminAllApplicationsScreenState();
}

class _AdminAllApplicationsScreenState extends State<AdminAllApplicationsScreen>
    with SingleTickerProviderStateMixin {
  final AdminService _adminService = AdminService();
  late TabController _tabController;

  List<Map<String, dynamic>> _allApplications = [];
  bool _isLoading = true;
  String? _errorMessage;

  static const _tabs = [
    {'label': 'All', 'status': null},
    {'label': 'Pending', 'status': 'PENDING'},
    {'label': 'Under Review', 'status': 'UNDER_REVIEW'},
    {'label': 'Approved', 'status': 'APPROVED'},
    {'label': 'Rejected', 'status': 'REJECTED'},
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        _loadApplications();
      }
    });
    _loadApplications();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadApplications() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final status = _tabs[_tabController.index]['status'];
      final data = await _adminService.getAllApplications(status: status);
      if (mounted) {
        setState(() {
          _allApplications = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load applications';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _navigateToView(String applicationId) async {
    final result = await context
        .push<bool>('${AppRouter.adminApplicationView}/$applicationId');
    if (result == true && mounted) {
      _loadApplications();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        title: const Text(
          'All Applications',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _loadApplications,
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          labelStyle: const TextStyle(fontWeight: FontWeight.w600),
          tabs: _tabs.map((t) => Tab(text: t['label'] as String)).toList(),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF1A237E)))
          : _errorMessage != null
              ? _buildError()
              : _allApplications.isEmpty
                  ? _buildEmpty()
                  : RefreshIndicator(
                      onRefresh: _loadApplications,
                      color: const Color(0xFF1A237E),
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _allApplications.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) =>
                            _buildApplicationCard(_allApplications[i]),
                      ),
                    ),
    );
  }

  Widget _buildApplicationCard(Map<String, dynamic> app) {
    final farmerName = app['farmers']?['name'] ?? 'Unknown Farmer';
    final farmerPhone = app['farmers']?['phone'] ?? '';
    final schemeName = app['schemes']?['name'] ?? 'Unknown Scheme';
    final trackingId = app['tracking_id'] ?? 'N/A';
    final status = (app['status'] ?? '').toString().toUpperCase();
    final createdAt = app['created_at'] ?? '';
    final applicationId = app['id']?.toString() ?? '';

    Color statusColor;
    Color statusBg;
    IconData statusIcon;
    switch (status) {
      case 'APPROVED':
        statusColor = const Color(0xFF2E7D32);
        statusBg = const Color(0xFFE8F5E9);
        statusIcon = Icons.check_circle_outline;
        break;
      case 'REJECTED':
        statusColor = const Color(0xFFC62828);
        statusBg = const Color(0xFFFFEBEE);
        statusIcon = Icons.cancel_outlined;
        break;
      case 'UNDER_REVIEW':
        statusColor = const Color(0xFF1565C0);
        statusBg = const Color(0xFFE3F2FD);
        statusIcon = Icons.search_outlined;
        break;
      default: // PENDING
        statusColor = const Color(0xFFE65100);
        statusBg = const Color(0xFFFFF3E0);
        statusIcon = Icons.hourglass_empty_outlined;
    }

    // Date formatting
    String dateStr = '';
    try {
      final dt = DateTime.parse(createdAt).toLocal();
      dateStr = '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {}

    // Avatar color
    final avatarColors = [
      const Color(0xFFE8EAF6),
      const Color(0xFFE0F2F1),
      const Color(0xFFFCE4EC),
      const Color(0xFFFFF3E0),
      const Color(0xFFEDE7F6),
    ];
    final textColors = [
      const Color(0xFF283593),
      const Color(0xFF00695C),
      const Color(0xFFC2185B),
      const Color(0xFFE65100),
      const Color(0xFF4527A0),
    ];
    final idx = farmerName.hashCode.abs() % avatarColors.length;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _navigateToView(applicationId),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade100),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Avatar
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: avatarColors[idx],
                    child: Text(
                      farmerName.isNotEmpty ? farmerName[0].toUpperCase() : '?',
                      style: TextStyle(
                        color: textColors[idx],
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Name + Scheme
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          farmerName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Color(0xFF1B1B1B),
                          ),
                        ),
                        if (farmerPhone.isNotEmpty)
                          Text(
                            farmerPhone,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade500,
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Status Chip
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: statusBg,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(statusIcon, size: 13, color: statusColor),
                        const SizedBox(width: 4),
                        Text(
                          status,
                          style: TextStyle(
                            fontSize: 11,
                            color: statusColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 10),
              Row(
                children: [
                  _buildMeta(Icons.article_outlined, schemeName),
                  const Spacer(),
                  _buildMeta(Icons.tag, trackingId),
                  const Spacer(),
                  _buildMeta(Icons.calendar_today_outlined, dateStr),
                ],
              ),
              if (status == 'PENDING' || status == 'UNDER_REVIEW') ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 38,
                  child: ElevatedButton.icon(
                    onPressed: () => _navigateToView(applicationId),
                    icon: const Icon(Icons.verified_outlined, size: 16),
                    label: const Text('Review & Verify'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A237E),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      textStyle: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMeta(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: Colors.grey.shade500),
        const SizedBox(width: 3),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade600,
          ),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
      ],
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox_outlined, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(
            'No applications found',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 15),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_off_rounded,
              size: 56, color: AppColors.error.withOpacity(0.6)),
          const SizedBox(height: 12),
          Text(_errorMessage ?? 'Error',
              style: TextStyle(color: Colors.grey.shade600)),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _loadApplications,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A237E),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }
}
