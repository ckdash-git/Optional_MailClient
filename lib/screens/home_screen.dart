import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/app_constants.dart';
import '../services/auth_service.dart';
import '../services/gmail_service.dart';
import '../services/email_analysis_service.dart';
import '../models/email_model.dart';
import '../widgets/email_list_widget.dart';
import '../widgets/email_stats_widget.dart';
import '../widgets/filter_drawer.dart';
import 'email_detail_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with TickerProviderStateMixin {
  final AuthService _authService = AuthService();
  final GmailService _gmailService = GmailService();
  final EmailAnalysisService _analysisService = EmailAnalysisService();
  
  late TabController _tabController;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  
  List<EmailModel> _emails = [];
  List<EmailModel> _filteredEmails = [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  String _selectedCategory = 'All';
  EmailSortBy _sortBy = EmailSortBy.date;
  bool _sortAscending = false;
  String _searchQuery = '';
  
  final TextEditingController _searchController = TextEditingController();
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _initializeData();
  }

  Future<void> _initializeData() async {
    try {
      await _gmailService.initialize();
      await _loadEmails();
    } catch (e) {
      _showErrorSnackBar('Failed to initialize: ${e.toString()}');
    }
  }

  Future<void> _loadEmails() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final rawEmails = await _gmailService.getEmails(
        maxResults: AppConstants.defaultEmailBatchSize,
      );
      
      // Analyze emails for categorization and create new list
      final List<EmailModel> categorizedEmails = [];
      for (var email in rawEmails) {
        final category = _analysisService.categorizeEmail(email);
        final categorizedEmail = email.copyWith(category: category);
        categorizedEmails.add(categorizedEmail);
      }
      
      setState(() {
        _emails = categorizedEmails;
        _filteredEmails = categorizedEmails;
        _isLoading = false;
      });
      
      _applyFilters();
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showErrorSnackBar('Failed to load emails: ${e.toString()}');
    }
  }

  Future<void> _refreshEmails() async {
    setState(() {
      _isRefreshing = true;
    });
    
    await _loadEmails();
    
    setState(() {
      _isRefreshing = false;
    });
  }

  void _applyFilters() {
    List<EmailModel> filtered = List.from(_emails);
    
    // Apply category filter
    if (_selectedCategory != 'All') {
      filtered = filtered.where((email) => email.category == _selectedCategory).toList();
    }
    
    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((email) {
        return email.subject.toLowerCase().contains(_searchQuery.toLowerCase()) ||
               email.sender.toLowerCase().contains(_searchQuery.toLowerCase()) ||
               email.snippet.toLowerCase().contains(_searchQuery.toLowerCase());
      }).toList();
    }
    
    // Apply sorting
    filtered.sort((a, b) {
      int comparison;
      switch (_sortBy) {
          case EmailSortBy.date:
            comparison = a.date.compareTo(b.date);
            break;
          case EmailSortBy.sender:
            comparison = a.sender.compareTo(b.sender);
            break;
          case EmailSortBy.subject:
            comparison = a.subject.compareTo(b.subject);
            break;
          case EmailSortBy.importance:
            comparison = a.importance.compareTo(b.importance);
            break;
          case EmailSortBy.read:
            comparison = a.isRead.toString().compareTo(b.isRead.toString());
            break;
        }
      return _sortAscending ? comparison : -comparison;
    });
    
    setState(() {
      _filteredEmails = filtered;
    });
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query;
    });
    _applyFilters();
  }

  void _onCategoryChanged(String category) {
    setState(() {
      _selectedCategory = category;
    });
    _applyFilters();
  }

  void _onSortChanged(EmailSortBy sortBy, bool ascending) {
    setState(() {
      _sortBy = sortBy;
      _sortAscending = ascending;
    });
    _applyFilters();
  }

  Future<void> _signOut() async {
    try {
      await _authService.signOut();
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/auth');
      }
    } catch (e) {
      _showErrorSnackBar('Failed to sign out: ${e.toString()}');
    }
  }

  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isSmallScreen = constraints.maxWidth < 600;
        
        return Scaffold(
          key: _scaffoldKey,
          appBar: _buildAppBar(context, isSmallScreen),
          drawer: FilterDrawer(
            selectedCategory: _selectedCategory,
            sortBy: _sortBy,
            sortAscending: _sortAscending,
            onCategoryChanged: _onCategoryChanged,
            onSortChanged: _onSortChanged,
          ),
          body: Column(
            children: [
              _buildSearchBar(context, isSmallScreen),
              _buildTabBar(context, isSmallScreen),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildEmailListTab(),
                    _buildAnalyticsTab(),
                    _buildCategoriesTab(isSmallScreen),
                    _buildSettingsTab(),
                  ],
                ),
              ),
            ],
          ),
          floatingActionButton: _buildFloatingActionButton(context),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, bool isSmallScreen) {
    return AppBar(
      title: Text(
        'AI Mail Client',
        style: TextStyle(
          fontSize: isSmallScreen ? 18 : 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: _isRefreshing ? null : _refreshEmails,
        ),
        PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'signout') {
              _signOut();
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'signout',
              child: Row(
                children: [
                  Icon(Icons.logout),
                  SizedBox(width: 8),
                  Text('Sign Out'),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSearchBar(BuildContext context, bool isSmallScreen) {
    return Container(
      padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
      child: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        decoration: InputDecoration(
          hintText: 'Search emails...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    _onSearchChanged('');
                  },
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(isSmallScreen ? 8 : 12),
          ),
          contentPadding: EdgeInsets.symmetric(
            horizontal: isSmallScreen ? 12 : 16,
            vertical: isSmallScreen ? 8 : 12,
          ),
        ),
      ),
    );
  }

  Widget _buildTabBar(BuildContext context, bool isSmallScreen) {
    return TabBar(
      controller: _tabController,
      isScrollable: isSmallScreen,
      labelStyle: TextStyle(
        fontSize: isSmallScreen ? 12 : 14,
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelStyle: TextStyle(
        fontSize: isSmallScreen ? 11 : 13,
      ),
      tabs: [
        Tab(
          icon: Icon(Icons.inbox, size: isSmallScreen ? 18 : 24),
          text: 'Inbox',
        ),
        Tab(
          icon: Icon(Icons.analytics, size: isSmallScreen ? 18 : 24),
          text: 'Analytics',
        ),
        Tab(
          icon: Icon(Icons.category, size: isSmallScreen ? 18 : 24),
          text: 'Categories',
        ),
        Tab(
          icon: Icon(Icons.settings, size: isSmallScreen ? 18 : 24),
          text: 'Settings',
        ),
      ],
    );
  }

  Widget _buildEmailListTab() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_filteredEmails.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isNotEmpty || _selectedCategory != 'All'
                  ? 'No emails match your filters'
                  : 'No emails found',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshEmails,
      child: EmailListWidget(
        emails: _filteredEmails,
        onEmailTap: (email) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => EmailDetailScreen(email: email),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAnalyticsTab() {
    if (_emails.isEmpty) {
      return const Center(
        child: Text('No data available for analytics'),
      );
    }

    return EmailStatsWidget(
      emails: _emails,
      analysisService: _analysisService,
    );
  }

  Widget _buildCategoriesTab(bool isSmallScreen) {
    if (_emails.isEmpty) {
      return const Center(
        child: Text('No emails to categorize'),
      );
    }

    final categoryStats = <String, int>{};
    for (final email in _emails) {
      final category = email.category ?? 'Other';
      categoryStats[category] = (categoryStats[category] ?? 0) + 1;
    }

    return ListView.builder(
      padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
      itemCount: categoryStats.length,
      itemBuilder: (context, index) {
        final category = categoryStats.keys.elementAt(index);
        final count = categoryStats[category]!;
        final percentage = (count / _emails.length) * 100;

        return Card(
          margin: EdgeInsets.only(bottom: isSmallScreen ? 8 : 12),
          child: ListTile(
            contentPadding: EdgeInsets.all(isSmallScreen ? 12 : 16),
            leading: Container(
              width: isSmallScreen ? 32 : 40,
              height: isSmallScreen ? 32 : 40,
              decoration: BoxDecoration(
                color: _getCategoryColor(category),
                borderRadius: BorderRadius.circular(isSmallScreen ? 6 : 8),
              ),
              child: Icon(
                _getCategoryIcon(category),
                color: Colors.white,
                size: isSmallScreen ? 16 : 20,
              ),
            ),
            title: Text(
              category,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: isSmallScreen ? 14 : 16,
              ),
            ),
            subtitle: Text(
              '${percentage.toStringAsFixed(1)}% of total emails',
              style: TextStyle(
                fontSize: isSmallScreen ? 12 : 14,
              ),
            ),
            trailing: Icon(
              Icons.arrow_forward_ios,
              size: isSmallScreen ? 14 : 16,
              color: Theme.of(context).colorScheme.outline,
            ),
            onTap: () {
              _onCategoryChanged(category);
              _tabController.animateTo(0); // Switch to inbox tab
            },
          ),
        );
      },
    );
  }

  Widget _buildSettingsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.account_circle),
                title: const Text('Account'),
                subtitle: Text(_authService.currentUser?.email ?? 'Not signed in'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.security),
                title: const Text('Privacy & Security'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  // TODO: Navigate to privacy settings
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.notifications),
                title: const Text('Notifications'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  // TODO: Navigate to notification settings
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title: const Text('Sign Out', style: TextStyle(color: Colors.red)),
                onTap: _signOut,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFloatingActionButton(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return FloatingActionButton(
      onPressed: () {
        _scaffoldKey.currentState?.openDrawer();
      },
      backgroundColor: colorScheme.primary,
      foregroundColor: colorScheme.onPrimary,
      child: const Icon(Icons.filter_list),
    );
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

  IconData _getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'work':
        return Icons.work;
      case 'personal':
        return Icons.person;
      case 'promotions':
        return Icons.local_offer;
      case 'social':
        return Icons.people;
      case 'spam':
        return Icons.block;
      case 'important':
        return Icons.star;
      default:
        return Icons.mail;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }
}