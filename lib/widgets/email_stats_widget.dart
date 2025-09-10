import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/email_model.dart';
import '../services/email_analysis_service.dart';

class EmailStatsWidget extends StatefulWidget {
  final List<EmailModel> emails;
  final EmailAnalysisService analysisService;

  const EmailStatsWidget({
    super.key,
    required this.emails,
    required this.analysisService,
  });

  @override
  State<EmailStatsWidget> createState() => _EmailStatsWidgetState();
}

class _EmailStatsWidgetState extends State<EmailStatsWidget>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Map<String, dynamic>? _stats;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _generateStats();
  }

  void _generateStats() {
    setState(() {
      _stats = widget.analysisService.generateEmailStats(widget.emails);
    });
  }

  @override
  void didUpdateWidget(EmailStatsWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.emails != widget.emails) {
      _generateStats();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_stats == null) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return Column(
      children: [
        // Overview Cards
        _buildOverviewCards(context),
        const SizedBox(height: 16),
        
        // Tab Bar
        TabBar(
          controller: _tabController,
          labelColor: Theme.of(context).colorScheme.primary,
          unselectedLabelColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
          indicatorColor: Theme.of(context).colorScheme.primary,
          tabs: const [
            Tab(text: 'Categories'),
            Tab(text: 'Senders'),
            Tab(text: 'Timeline'),
          ],
        ),
        
        // Tab Content
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildCategoriesTab(context),
              _buildSendersTab(context),
              _buildTimelineTab(context),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOverviewCards(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: _buildStatCard(
              context,
              'Total Emails',
              _stats!['totalEmails'].toString(),
              Icons.email,
              colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildStatCard(
              context,
              'Unread',
              _stats!['unreadEmails'].toString(),
              Icons.mark_email_unread,
              Colors.orange,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildStatCard(
              context,
              'Avg/Day',
              _stats!['averageEmailsPerDay'].toStringAsFixed(1),
              Icons.trending_up,
              Colors.green,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    BuildContext context,
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    final theme = Theme.of(context);
    
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: color,
              size: 24,
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.7),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoriesTab(BuildContext context) {
    final categories = _stats!['categories'] as Map<String, int>;
    
    if (categories.isEmpty) {
      return const Center(
        child: Text('No category data available'),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Pie Chart
          Expanded(
            flex: 2,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(
                      'Email Categories Distribution',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: PieChart(
                        PieChartData(
                          sections: _buildPieChartSections(categories),
                          centerSpaceRadius: 40,
                          sectionsSpace: 2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Category List
          Expanded(
            flex: 1,
            child: Card(
              child: ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: categories.length,
                itemBuilder: (context, index) {
                  final category = categories.keys.elementAt(index);
                  final count = categories[category]!;
                  final percentage = (count / widget.emails.length * 100);
                  
                  return ListTile(
                    dense: true,
                    leading: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: _getCategoryColor(category),
                        shape: BoxShape.circle,
                      ),
                    ),
                    title: Text(category),
                    trailing: Text(
                      '$count (${percentage.toStringAsFixed(1)}%)',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSendersTab(BuildContext context) {
    final topSenders = _stats!['topSenders'] as Map<String, int>;
    
    if (topSenders.isEmpty) {
      return const Center(
        child: Text('No sender data available'),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Card(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Top Email Senders',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: topSenders.length,
                itemBuilder: (context, index) {
                  final sender = topSenders.keys.elementAt(index);
                  final count = topSenders[sender]!;
                  final percentage = (count / widget.emails.length * 100);
                  
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: _getSenderColor(sender),
                      child: Text(
                        _getInitials(sender),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    title: Text(
                      sender,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${percentage.toStringAsFixed(1)}% of emails',
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        count.toString(),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimelineTab(BuildContext context) {
    final emailsPerDay = _stats!['emailsPerDay'] as Map<String, int>;
    
    if (emailsPerDay.isEmpty) {
      return const Center(
        child: Text('No timeline data available'),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(
                'Email Volume Over Time',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: LineChart(
                  LineChartData(
                    gridData: const FlGridData(show: true),
                    titlesData: FlTitlesData(
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 40,
                          getTitlesWidget: (value, meta) {
                            return Text(
                              value.toInt().toString(),
                              style: const TextStyle(fontSize: 12),
                            );
                          },
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 30,
                          getTitlesWidget: (value, meta) {
                            final index = value.toInt();
                            if (index >= 0 && index < emailsPerDay.length) {
                              final date = emailsPerDay.keys.elementAt(index);
                              final parts = date.split('-');
                              return Text(
                                '${parts[2]}/${parts[1]}',
                                style: const TextStyle(fontSize: 10),
                              );
                            }
                            return const Text('');
                          },
                        ),
                      ),
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                    ),
                    borderData: FlBorderData(
                      show: true,
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                      ),
                    ),
                    lineBarsData: [
                      LineChartBarData(
                        spots: _buildLineChartSpots(emailsPerDay),
                        isCurved: true,
                        color: Theme.of(context).colorScheme.primary,
                        barWidth: 3,
                        dotData: const FlDotData(show: true),
                        belowBarData: BarAreaData(
                          show: true,
                          color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<PieChartSectionData> _buildPieChartSections(Map<String, int> categories) {
    final total = categories.values.fold(0, (sum, count) => sum + count);
    
    return categories.entries.map((entry) {
      final percentage = (entry.value / total * 100);
      return PieChartSectionData(
        color: _getCategoryColor(entry.key),
        value: entry.value.toDouble(),
        title: '${percentage.toStringAsFixed(1)}%',
        radius: 60,
        titleStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      );
    }).toList();
  }

  List<FlSpot> _buildLineChartSpots(Map<String, int> emailsPerDay) {
    final sortedEntries = emailsPerDay.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    
    return sortedEntries.asMap().entries.map((entry) {
      return FlSpot(
        entry.key.toDouble(),
        entry.value.value.toDouble(),
      );
    }).toList();
  }

  Color _getCategoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'work':
        return Colors.blue;
      case 'personal':
        return Colors.green;
      case 'promotions':
        return Colors.orange;
      case 'social':
        return Colors.purple;
      case 'spam':
        return Colors.red;
      case 'important':
        return Colors.amber;
      default:
        return Colors.grey;
    }
  }

  Color _getSenderColor(String sender) {
    final colors = [
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.teal,
      Colors.indigo,
      Colors.pink,
      Colors.cyan,
    ];
    
    final hash = sender.hashCode;
    return colors[hash.abs() % colors.length];
  }

  String _getInitials(String name) {
    final words = name.split(' ');
    if (words.length >= 2) {
      return '${words[0][0]}${words[1][0]}'.toUpperCase();
    } else if (words.isNotEmpty && words[0].isNotEmpty) {
      return words[0][0].toUpperCase();
    }
    return '?';
  }
}