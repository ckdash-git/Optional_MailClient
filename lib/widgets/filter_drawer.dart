import 'package:flutter/material.dart';
import '../models/email_model.dart';

class FilterDrawer extends StatelessWidget {
  final String selectedCategory;
  final EmailSortBy sortBy;
  final bool sortAscending;
  final Function(String) onCategoryChanged;
  final Function(EmailSortBy, bool) onSortChanged;

  const FilterDrawer({
    super.key,
    required this.selectedCategory,
    required this.sortBy,
    required this.sortAscending,
    required this.onCategoryChanged,
    required this.onSortChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.filter_list,
                    color: colorScheme.onPrimaryContainer,
                    size: 32,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Filters & Sorting',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Organize your emails',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onPrimaryContainer.withOpacity(0.8),
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Categories Section
                  _buildSectionHeader(context, 'Categories', Icons.category),
                  const SizedBox(height: 8),
                  _buildCategoriesSection(context),
                  
                  const SizedBox(height: 24),
                  
                  // Sort Section
                  _buildSectionHeader(context, 'Sort By', Icons.sort),
                  const SizedBox(height: 8),
                  _buildSortSection(context),
                  
                  const SizedBox(height: 24),
                  
                  // Sort Order Section
                  _buildSectionHeader(context, 'Sort Order', Icons.swap_vert),
                  const SizedBox(height: 8),
                  _buildSortOrderSection(context),
                  
                  const SizedBox(height: 32),
                  
                  // Reset Button
                  _buildResetButton(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title, IconData icon) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    return Row(
      children: [
        Icon(
          icon,
          size: 20,
          color: colorScheme.primary,
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _buildCategoriesSection(BuildContext context) {
    final categories = [
      {'name': 'All', 'icon': Icons.all_inbox, 'color': Colors.grey},
      {'name': 'Work', 'icon': Icons.work, 'color': Colors.blue},
      {'name': 'Personal', 'icon': Icons.person, 'color': Colors.green},
      {'name': 'Promotions', 'icon': Icons.local_offer, 'color': Colors.orange},
      {'name': 'Social', 'icon': Icons.people, 'color': Colors.purple},
      {'name': 'Important', 'icon': Icons.star, 'color': Colors.amber},
      {'name': 'Spam', 'icon': Icons.report, 'color': Colors.red},
    ];

    return Card(
      elevation: 1,
      child: Column(
        children: categories.map((category) {
          final isSelected = selectedCategory == category['name'];
          
          return ListTile(
            dense: true,
            leading: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: isSelected 
                    ? (category['color'] as Color)
                    : (category['color'] as Color).withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                category['icon'] as IconData,
                size: 18,
                color: isSelected 
                    ? Colors.white
                    : category['color'] as Color,
              ),
            ),
            title: Text(
              category['name'] as String,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected 
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
            ),
            trailing: isSelected 
                ? Icon(
                    Icons.check_circle,
                    color: Theme.of(context).colorScheme.primary,
                    size: 20,
                  )
                : null,
            onTap: () {
              onCategoryChanged(category['name'] as String);
              Navigator.of(context).pop();
            },
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSortSection(BuildContext context) {
    final sortOptions = [
      {'value': EmailSortBy.date, 'name': 'Date', 'icon': Icons.schedule},
      {'value': EmailSortBy.sender, 'name': 'Sender', 'icon': Icons.person},
      {'value': EmailSortBy.subject, 'name': 'Subject', 'icon': Icons.subject},
      {'value': EmailSortBy.importance, 'name': 'Importance', 'icon': Icons.priority_high},
      {'value': EmailSortBy.read, 'name': 'Read Status', 'icon': Icons.mark_email_read},
    ];

    return Card(
      elevation: 1,
      child: Column(
        children: sortOptions.map((option) {
          final isSelected = sortBy == option['value'];
          
          return ListTile(
            dense: true,
            leading: Icon(
              option['icon'] as IconData,
              color: isSelected 
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
            ),
            title: Text(
              option['name'] as String,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected 
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
            ),
            trailing: isSelected 
                ? Icon(
                    Icons.check_circle,
                    color: Theme.of(context).colorScheme.primary,
                    size: 20,
                  )
                : null,
            onTap: () {
              onSortChanged(option['value'] as EmailSortBy, sortAscending);
            },
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSortOrderSection(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    return Card(
      elevation: 1,
      child: Column(
        children: [
          ListTile(
            dense: true,
            leading: Icon(
              Icons.arrow_upward,
              color: sortAscending 
                  ? colorScheme.primary
                  : colorScheme.onSurface.withOpacity(0.6),
            ),
            title: Text(
              'Ascending',
              style: TextStyle(
                fontWeight: sortAscending ? FontWeight.w600 : FontWeight.normal,
                color: sortAscending ? colorScheme.primary : null,
              ),
            ),
            subtitle: Text(
              _getAscendingDescription(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
            trailing: sortAscending 
                ? Icon(
                    Icons.check_circle,
                    color: colorScheme.primary,
                    size: 20,
                  )
                : null,
            onTap: () {
              onSortChanged(sortBy, true);
            },
          ),
          const Divider(height: 1),
          ListTile(
            dense: true,
            leading: Icon(
              Icons.arrow_downward,
              color: !sortAscending 
                  ? colorScheme.primary
                  : colorScheme.onSurface.withOpacity(0.6),
            ),
            title: Text(
              'Descending',
              style: TextStyle(
                fontWeight: !sortAscending ? FontWeight.w600 : FontWeight.normal,
                color: !sortAscending ? colorScheme.primary : null,
              ),
            ),
            subtitle: Text(
              _getDescendingDescription(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
            trailing: !sortAscending 
                ? Icon(
                    Icons.check_circle,
                    color: colorScheme.primary,
                    size: 20,
                  )
                : null,
            onTap: () {
              onSortChanged(sortBy, false);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildResetButton(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () {
          onCategoryChanged('All');
          onSortChanged(EmailSortBy.date, false);
          Navigator.of(context).pop();
        },
        icon: const Icon(Icons.refresh),
        label: const Text('Reset Filters'),
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.primary,
          side: BorderSide(color: colorScheme.primary),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  String _getAscendingDescription() {
    switch (sortBy) {
      case EmailSortBy.date:
        return 'Oldest first';
      case EmailSortBy.sender:
        return 'A to Z';
      case EmailSortBy.subject:
        return 'A to Z';
      case EmailSortBy.importance:
        return 'Low to High';
      case EmailSortBy.read:
        return 'Unread first';
    }
  }

  String _getDescendingDescription() {
    switch (sortBy) {
      case EmailSortBy.date:
        return 'Newest first';
      case EmailSortBy.sender:
        return 'Z to A';
      case EmailSortBy.subject:
        return 'Z to A';
      case EmailSortBy.importance:
        return 'High to Low';
      case EmailSortBy.read:
        return 'Read first';
    }
  }
}