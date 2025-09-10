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
      final emails = await _gmailService.getEmails(
        maxResults: AppConstants.defaultEmailBatchSize,
      );
      
      // Analyze emails for categorization
      for (var email in emails) {
        final category = _analysisService.categorizeEmail(email);
        email = email.copyWith(category: category);
      }
      
      setState(() {
        _emails = emails;
        _filteredEmails = emails;
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
          // TODO: Handle this case.
          throw UnimplementedError();
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      key: _scaffoldKey,
      appBar: _buildAppBar(theme, colorScheme),
      drawer: FilterDrawer(
        selectedCategory: _selectedCategory,
        sortBy: _sortBy,
        sortAscending: _sortAscending,
        onCategoryChanged: _onCategoryChanged,
        onSortChanged: _onSortChanged,
      ),
      body: Column(
        children: [
          // Search Bar
          _buildSearchBar(theme, colorScheme),
          
          // Tab Bar
          _buildTabBar(theme, colorScheme),
          
          // Tab Content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildEmailListTab(),
                _buildAnalyticsTab(),
                _buildCategoriesTab(),
                _buildSettingsTab(),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: _buildFloatingActionButton(colorScheme),
    );
  }

  PreferredSizeWidget _buildAppBar(ThemeData theme, ColorScheme colorScheme) {
    return AppBar(
      title: Text(
        AppConstants.appName,
        style: theme.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.bold,
        ),
      ),
      backgroundColor: colorScheme.surface,
      foregroundColor: colorScheme.onSurface,
      elevation: 0,
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: _isRefreshing ? null : _refreshEmails,
          tooltip: 'Refresh emails',
        ),
        PopupMenuButton<String>(
          onSelected: (value) {
            switch (value) {
              case 'signout':
                _signOut();
                break;
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

  Widget _buildSearchBar(ThemeData theme, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(16),
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
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: colorScheme.surfaceVariant.withOpacity(0.5),
        ),
      ),
    );
  }

  Widget _buildTabBar(ThemeData theme, ColorScheme colorScheme) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outline.withOpacity(0.2),
            width: 1,
          ),
        ),
      ),
      child: TabBar(
        controller: _tabController,
        labelColor: colorScheme.primary,
        unselectedLabelColor: colorScheme.onSurface.withOpacity(0.6),
        indicatorColor: colorScheme.primary,
        tabs: const [
          Tab(icon: Icon(Icons.inbox), text: 'Inbox'),
          Tab(icon: Icon(Icons.analytics), text: 'Analytics'),
          Tab(icon: Icon(Icons.category), text: 'Categories'),
          Tab(icon: Icon(Icons.settings), text: 'Settings'),
        ],
      ),
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
              Icons.inbox,
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
          // TODO: Navigate to email detail screen
        },
      ),
    );
  }

  Widget _buildAnalyticsTab() {
    return EmailStatsWidget(
      emails: _emails,
      analysisService: _analysisService,
    );
  }

  Widget _buildCategoriesTab() {
    final categories = _analysisService.getCategoryStats(_emails);
    
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: categories.length,
      itemBuilder: (context, index) {
        final category = categories.keys.elementAt(index);
        final count = categories[category]!;
        final percentage = _emails.isNotEmpty ? (count / _emails.length * 100) : 0.0;
        
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: _getCategoryColor(category),
              child: Text(
                count.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            title: Text(
              category,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text('${percentage.toStringAsFixed(1)}% of total emails'),
            trailing: Icon(
              Icons.arrow_forward_ios,
              size: 16,
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
            ],
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.help),
                title: const Text('Help & Support'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  // TODO: Navigate to help
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.info),
                title: const Text('About'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  // TODO: Show about dialog
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: _signOut,
          icon: const Icon(Icons.logout),
          label: const Text('Sign Out'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
            minimumSize: const Size(double.infinity, 48),
          ),
        ),
      ],
    );
  }

  Widget _buildFloatingActionButton(ColorScheme colorScheme) {
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
}