import 'package:flutter/material.dart';
import '../models/email_model.dart';

class EmailListWidget extends StatelessWidget {
  final List<EmailModel> emails;
  final Function(EmailModel) onEmailTap;
  final Function(EmailModel)? onEmailLongPress;
  final bool showCheckboxes;
  final Set<String> selectedEmails;
  final Function(String, bool)? onEmailSelected;

  const EmailListWidget({
    super.key,
    required this.emails,
    required this.onEmailTap,
    this.onEmailLongPress,
    this.showCheckboxes = false,
    this.selectedEmails = const {},
    this.onEmailSelected,
  });

  @override
  Widget build(BuildContext context) {
    if (emails.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 64,
              color: Colors.grey,
            ),
            SizedBox(height: 16),
            Text(
              'No emails found',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: emails.length,
      itemBuilder: (context, index) {
        final email = emails[index];
        return _buildEmailTile(context, email);
      },
    );
  }

  Widget _buildEmailTile(BuildContext context, EmailModel email) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isSelected = selectedEmails.contains(email.id);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      elevation: email.isRead ? 1 : 3,
      child: InkWell(
        onTap: () => onEmailTap(email),
        onLongPress: () => onEmailLongPress?.call(email),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: isSelected
                ? colorScheme.primaryContainer.withOpacity(0.3)
                : email.isRead
                    ? null
                    : colorScheme.surfaceVariant.withOpacity(0.3),
          ),
          child: Row(
            children: [
              // Checkbox (if enabled)
              if (showCheckboxes) ...[
                Checkbox(
                  value: isSelected,
                  onChanged: (value) {
                    onEmailSelected?.call(email.id, value ?? false);
                  },
                ),
                const SizedBox(width: 8),
              ],

              // Avatar
              _buildAvatar(email, colorScheme),
              const SizedBox(width: 12),

              // Email content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header row (sender, date, importance)
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _getSenderName(email.from),
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: email.isRead ? FontWeight.normal : FontWeight.bold,
                              color: email.isRead ? colorScheme.onSurface : colorScheme.primary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildImportanceIndicator(email, colorScheme),
                        const SizedBox(width: 8),
                        Text(
                          _formatDate(email.date),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),

                    // Subject
                    Text(
                      email.subject.isEmpty ? '(No Subject)' : email.subject,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: email.isRead ? FontWeight.normal : FontWeight.w600,
                        color: email.isRead ? colorScheme.onSurface : colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),

                    // Snippet
                    Text(
                      email.snippet,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface.withOpacity(0.7),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),

                    // Footer row (category, attachments, labels)
                    Row(
                      children: [
                        // Category chip
                        if (email.category != null && email.category!.isNotEmpty) ...[
                          _buildCategoryChip(email.category!, colorScheme),
                          const SizedBox(width: 8),
                        ],

                        // Attachment indicator
                        if (email.hasAttachments) ...[
                          Icon(
                            Icons.attach_file,
                            size: 16,
                            color: colorScheme.onSurface.withOpacity(0.6),
                          ),
                          const SizedBox(width: 8),
                        ],

                        const Spacer(),

                        // Star indicator
                        if (email.isStarred)
                          Icon(
                            Icons.star,
                            size: 16,
                            color: Colors.amber,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(EmailModel email, ColorScheme colorScheme) {
    final senderName = _getSenderName(email.from);
    final initials = _getInitials(senderName);

    return CircleAvatar(
      radius: 20,
      backgroundColor: _getAvatarColor(senderName, colorScheme),
      child: Text(
        initials,
        style: TextStyle(
          color: colorScheme.onPrimary,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      ),
    );
  }

  Widget _buildImportanceIndicator(EmailModel email, ColorScheme colorScheme) {
    if (email.importance <= 0) return const SizedBox.shrink();

    Color color;
    IconData icon;

    if (email.importance >= 3) {
      color = Colors.red;
      icon = Icons.priority_high;
    } else if (email.importance >= 2) {
      color = Colors.orange;
      icon = Icons.flag;
    } else {
      color = Colors.blue;
      icon = Icons.info_outline;
    }

    return Icon(
      icon,
      size: 16,
      color: color,
    );
  }

  Widget _buildCategoryChip(String category, ColorScheme colorScheme) {
    final color = _getCategoryColor(category);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.5), width: 1),
      ),
      child: Text(
        category,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: color,
        ),
      ),
    );
  }

  String _getSenderName(String fromField) {
    // Extract name from "Name <email@domain.com>" format
    final nameMatch = RegExp(r'^([^<]+)<').firstMatch(fromField);
    if (nameMatch != null) {
      return nameMatch.group(1)!.trim();
    }

    // If no name found, use email address
    final emailMatch = RegExp(r'[\w\.-]+@[\w\.-]+').firstMatch(fromField);
    if (emailMatch != null) {
      final email = emailMatch.group(0)!;
      return email.split('@')[0]; // Use part before @
    }

    return fromField;
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

  Color _getAvatarColor(String name, ColorScheme colorScheme) {
    final colors = [
      colorScheme.primary,
      colorScheme.secondary,
      colorScheme.tertiary,
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.teal,
    ];

    final hash = name.hashCode;
    return colors[hash.abs() % colors.length];
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

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      // Today - show time
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      // This week - show day name
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[date.weekday - 1];
    } else {
      // Older - show date
      return '${date.day}/${date.month}';
    }
  }
}