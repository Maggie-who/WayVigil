import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_config.dart';
import 'dart:async';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
// supabase intialization
  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );

  runApp(const MyApp());
}

final ThemeData appTheme = ThemeData(
  brightness: Brightness.dark,
  scaffoldBackgroundColor: Colors.black,
  primaryColor: const Color(0xFF5A2A83),
  colorScheme: const ColorScheme.dark(
    primary: Color(0xFF5A2A83),
    secondary: Color(0xFFB11226),
    surface: Color(0xFF121212),
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: Color(0xFFB81111),
    elevation: 0,
    titleTextStyle: TextStyle(
      color: Color(0xFFEAEAEA),
      fontSize: 20,
      fontWeight: FontWeight.bold,
    ),
  ),
  cardColor: const Color(0xFF121212),
  textTheme: const TextTheme(
    bodyLarge: TextStyle(color: Color(0xFFEAEAEA)),
    bodyMedium: TextStyle(color: Color(0xFFEAEAEA)),
  ),
);

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WayVigil Police App',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: ThemeData.light(),
      darkTheme: appTheme,
      home: const ReportListPage(),
    );
  }
}

class ReportListPage extends StatefulWidget {
  const ReportListPage({super.key});

  @override
  State<ReportListPage> createState() => _ReportListPageState();
}

class _ReportListPageState extends State<ReportListPage> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> violations = [];
  bool isLoading = true;
  String? error;
  RealtimeChannel? _realtimeChannel;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    fetchViolations();
    setupRealtimeListener();
    setupPolling(); // Backup polling
  }

  @override
  void dispose() {
    _realtimeChannel?.unsubscribe();
    _pollingTimer?.cancel();
    super.dispose();
  }

  void setupRealtimeListener() {
    try {
      _realtimeChannel = supabase
          .channel('public:violations')
          .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'violations',
        callback: (payload) {
          print('Real-time update received: ${payload.eventType}');
          fetchViolations(); // Refresh on any change
        },
      )
          .subscribe();

      print(' Real-time listener active');
    } catch (e) {
      print(' Real-time setup failed: $e');
    }
  }

  void setupPolling() {
    // Backup: Poll every 5 seconds
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (mounted) {
        fetchViolations();
      }
    });
  }

  Future<void> fetchViolations() async {
    if (!mounted) return;

    setState(() {
      isLoading = true;
      error = null;
    });

    try {
      final response = await supabase
          .from('violations')
          .select()
          .order('created_at', ascending: false)
          .timeout(const Duration(seconds: 10));

      if (mounted) {
        setState(() {
          violations = List<Map<String, dynamic>>.from(response);
          isLoading = false;
        });
        print('✅ Loaded ${violations.length} violations');
      }
    } catch (e) {
      print('❌ Fetch error: $e');
      if (mounted) {
        setState(() {
          error = e.toString();
          isLoading = false;
        });
      }
    }
  }

  String _formatTimestamp(String timestamp) {
    try {
      if (timestamp.length >= 13) {
        final year = timestamp.substring(0, 4);
        final month = timestamp.substring(4, 6);
        final day = timestamp.substring(6, 8);
        final hour = timestamp.substring(9, 11);
        final minute = timestamp.substring(11, 13);

        return '$day/$month/$year $hour:$minute';
      }
      return timestamp;
    } catch (e) {
      return timestamp;
    }
  }

  String _getProblemType(String location) {
    if (location.toLowerCase().contains('parking')) {
      return 'vehicle stopped at restricted location';
    } else if (location.toLowerCase().contains('platform')) {
      return 'Vehicle using platform';
    } else {
      return 'parking violation';
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Colors.orange;
      case 'reviewed':
        return Colors.blue;
      case 'resolved':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('WayVigil Reports'),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.green,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'LIVE',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: fetchViolations,
          ),
        ],
      ),
      body: isLoading && violations.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : error != null && violations.isEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text('Error: $error',
                style: const TextStyle(color: Colors.white),
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: fetchViolations,
              child: const Text('Retry'),
            ),
          ],
        ),
      )
          : violations.isEmpty
          ? const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, size: 64, color: Colors.green),
            SizedBox(height: 16),
            Text('No violations found',
                style: TextStyle(color: Colors.white)),
          ],
        ),
      )
          : RefreshIndicator(
        onRefresh: fetchViolations,
        child: ListView.builder(
          itemCount: violations.length,
          physics: const AlwaysScrollableScrollPhysics(),
          itemBuilder: (context, index) {
            final violation = violations[index];
            final problemType = _getProblemType(
                violation['location'] ?? 'unknown');
            final timestamp = _formatTimestamp(
                violation['timestamp'] ?? '');

            return Card(
              margin: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
              elevation: 4,
              child: ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Image.network(
                    violation['image_url'] ?? '',
                    width: 50,
                    height: 50,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        width: 50,
                        height: 50,
                        color: Colors.grey.shade800,
                        child: const Icon(Icons.report,
                            color: Colors.white70),
                      );
                    },
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return Container(
                        width: 50,
                        height: 50,
                        color: Colors.grey.shade800,
                        child: const Center(
                          child: CircularProgressIndicator(
                              strokeWidth: 2),
                        ),
                      );
                    },
                  ),
                ),
                title: Text(
                  problemType,
                  style: const TextStyle(color: Color(0xFFEAEAEA)),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      timestamp,
                      style: TextStyle(color: Colors.grey.shade400),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _getStatusColor(
                            violation['status'] ?? 'pending')
                            .withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _getStatusColor(
                              violation['status'] ?? 'pending'),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        (violation['status'] ?? 'pending')
                            .toString()
                            .toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: _getStatusColor(
                              violation['status'] ?? 'pending'),
                        ),
                      ),
                    ),
                  ],
                ),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ReportDetailPage(
                        violation: violation,
                      ),
                    ),
                  ).then((_) => fetchViolations());
                },
              ),
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: fetchViolations,
        backgroundColor: const Color(0xFFB11226),
        child: const Icon(Icons.refresh),
      ),
    );
  }
}

class ReportDetailPage extends StatefulWidget {
  final Map<String, dynamic> violation;

  const ReportDetailPage({super.key, required this.violation});

  @override
  State<ReportDetailPage> createState() => _ReportDetailPageState();
}

class _ReportDetailPageState extends State<ReportDetailPage> {
  final supabase = Supabase.instance.client;
  late String currentStatus;
  bool isUpdating = false;

  @override
  void initState() {
    super.initState();
    currentStatus = widget.violation['status'] ?? 'pending';
  }

  Future<void> updateStatus(String newStatus) async {
    setState(() {
      isUpdating = true;
    });

    try {
      await supabase
          .from('violations')
          .update({'status': newStatus})
          .eq('violation_id', widget.violation['violation_id']);

      if (mounted) {
        setState(() {
          currentStatus = newStatus;
          isUpdating = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Status updated to $newStatus'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isUpdating = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatTimestamp(String timestamp) {
    try {
      if (timestamp.length >= 13) {
        final year = timestamp.substring(0, 4);
        final month = timestamp.substring(4, 6);
        final day = timestamp.substring(6, 8);
        final hour = timestamp.substring(9, 11);
        final minute = timestamp.substring(11, 13);

        return '$day/$month/$year at $hour:$minute';
      }
      return timestamp;
    } catch (e) {
      return timestamp;
    }
  }

  String _getProblemType(String location) {
    if (location.toLowerCase().contains('parking')) {
      return 'Stagnant Vehicle (No-Parking Zone)';
    } else if (location.toLowerCase().contains('platform')) {
      return 'Platform Intrusion';
    } else {
      return 'Parking Violation';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Report Details')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                widget.violation['image_url'] ?? '',
                width: double.infinity,
                height: 250,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    height: 250,
                    color: Colors.grey.shade800,
                    child: const Center(
                      child: Icon(Icons.image_not_supported, size: 80),
                    ),
                  );
                },
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return Container(
                    height: 250,
                    color: Colors.grey.shade800,
                    child: const Center(child: CircularProgressIndicator()),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),

            _buildDetailRow('Violation ID', widget.violation['violation_id'] ?? ''),
            _buildDetailRow('Problem Type',
                _getProblemType(widget.violation['location'] ?? '')),
            _buildDetailRow('Timestamp',
                _formatTimestamp(widget.violation['timestamp'] ?? '')),
            _buildDetailRow('Track ID',
                widget.violation['track_id']?.toString() ?? 'N/A'),
            _buildDetailRow('Dwell Time',
                '${widget.violation['dwell_time'] ?? 0}s',
                valueColor: Colors.red),
            _buildDetailRow('Frames Stopped',
                widget.violation['frames_stopped']?.toString() ?? '0'),
            _buildDetailRow('Location', widget.violation['location'] ?? ''),

            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 10),

            const Text(
              'Update Status:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: Color(0xFFEAEAEA),
              ),
            ),
            const SizedBox(height: 12),

            if (isUpdating)
              const Center(child: CircularProgressIndicator())
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildStatusChip('pending', Colors.orange),
                  _buildStatusChip('reviewed', Colors.blue),
                  _buildStatusChip('resolved', Colors.green),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Color(0xFFEAEAEA),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: valueColor ?? const Color(0xFFEAEAEA),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(String status, Color color) {
    final isSelected = currentStatus == status;
    return FilterChip(
      label: Text(
        status.toUpperCase(),
        style: TextStyle(
          color: isSelected ? Colors.white : color,
          fontWeight: FontWeight.bold,
        ),
      ),
      selected: isSelected,
      selectedColor: color,
      onSelected: (selected) {
        if (selected && !isUpdating) {
          updateStatus(status);
        }
      },
      backgroundColor: color.withOpacity(0.1),
      side: BorderSide(color: color, width: 1.5),
    );
  }
}