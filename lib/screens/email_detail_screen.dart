import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_html/flutter_html.dart';
import '../models/email_model.dart';

class EmailDetailScreen extends StatelessWidget {
  final EmailModel email;

  const EmailDetailScreen({super.key, required this.email});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Email Details'),
        actions: [
          IconButton(
            icon: Icon(email.isStarred ? Icons.star : Icons.star_border),
            onPressed: () {
              // TODO: Toggle star status
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Star toggle not implemented yet')),
              );
            },
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'reply':
                  _showNotImplemented(context, 'Reply');
                  break;
                case 'forward':
                  _showNotImplemented(context, 'Forward');
                  break;
                case 'delete':
                  _showNotImplemented(context, 'Delete');
                  break;
                case 'copy':
                  _copyEmailContent(context);
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'reply',
                child: Row(
                  children: [
                    Icon(Icons.reply),
                    SizedBox(width: 8),
                    Text('Reply'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'forward',
                child: Row(
                  children: [
                    Icon(Icons.forward),
                    SizedBox(width: 8),
                    Text('Forward'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'copy',
                child: Row(
                  children: [
                    Icon(Icons.copy),
                    SizedBox(width: 8),
                    Text('Copy Content'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Delete', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Email Header Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Subject
                    Text(
                      email.subject.isEmpty ? '(No Subject)' : email.subject,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // From
                    _buildInfoRow(
                      context,
                      'From',
                      email.from,
                      Icons.person,
                    ),
                    const SizedBox(height: 8),
                    
                    // To
                    if (email.to?.isNotEmpty == true)
                      _buildInfoRow(
                        context,
                        'To',
                        email.to!,
                        Icons.person_outline,
                      ),
                    if (email.to?.isNotEmpty == true) const SizedBox(height: 8),
                    
                    // CC
                    if (email.cc?.isNotEmpty == true)
                      _buildInfoRow(
                        context,
                        'CC',
                        email.cc!,
                        Icons.people_outline,
                      ),
                    if (email.cc?.isNotEmpty == true) const SizedBox(height: 8),
                    
                    // Date
                    _buildInfoRow(
                      context,
                      'Date',
                      _formatDate(email.date),
                      Icons.schedule,
                    ),
                    const SizedBox(height: 8),
                    
                    // Labels/Category
                    if (email.category != null || email.labels.isNotEmpty)
                      _buildLabelsRow(context),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            // Email Body Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Message',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    
                    // Email body
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceVariant.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Html(
                        data: email.body.isEmpty ? email.snippet : email.body,
                        style: {
                          "body": Style(
                            margin: Margins.zero,
                            padding: HtmlPaddings.zero,
                            fontSize: FontSize(theme.textTheme.bodyMedium?.fontSize ?? 14),
                            color: theme.textTheme.bodyMedium?.color,
                          ),
                        },
                        onLinkTap: (url, _, __) {
                          if (url != null) {
                            launchUrl(Uri.parse(url));
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            // Attachments (if any)
            if (email.hasAttachments)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.attach_file,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Attachments',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'This email has attachments (viewing not implemented yet)',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurface.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(
    BuildContext context,
    String label,
    String value,
    IconData icon,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 16,
          color: colorScheme.primary,
        ),
        const SizedBox(width: 8),
        Text(
          '$label:',
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface.withOpacity(0.7),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }

  Widget _buildLabelsRow(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.label,
          size: 16,
          color: colorScheme.primary,
        ),
        const SizedBox(width: 8),
        Text(
          'Labels:',
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface.withOpacity(0.7),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              if (email.category != null)
                Chip(
                  label: Text(
                    email.category!,
                    style: const TextStyle(fontSize: 12),
                  ),
                  backgroundColor: colorScheme.primaryContainer,
                  labelStyle: TextStyle(color: colorScheme.onPrimaryContainer),
                ),
              ...email.labels.take(3).map(
                (label) => Chip(
                  label: Text(
                    label,
                    style: const TextStyle(fontSize: 12),
                  ),
                  backgroundColor: colorScheme.secondaryContainer,
                  labelStyle: TextStyle(color: colorScheme.onSecondaryContainer),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      // Today - show time
      final hour = date.hour.toString().padLeft(2, '0');
      final minute = date.minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      // This week - show day name
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[date.weekday - 1];
    } else {
      // Older - show date
      final day = date.day.toString().padLeft(2, '0');
      final month = date.month.toString().padLeft(2, '0');
      final year = date.year.toString();
      return '$day/$month/$year';
    }
  }

  void _showNotImplemented(BuildContext context, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature functionality not implemented yet')),
    );
  }

  void _copyEmailContent(BuildContext context) {
    final content = '''
Subject: ${email.subject}
From: ${email.from}
To: ${email.to}
Date: ${_formatDate(email.date)}

${email.body.isEmpty ? email.snippet : email.body}
''';
    
    Clipboard.setData(ClipboardData(text: content));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Email content copied to clipboard')),
    );
  }
}