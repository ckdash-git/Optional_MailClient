import 'package:flutter/material.dart';
import 'package:optional_mail_client/ui/scope.dart';
import 'package:optional_mail_client/ui/widgets/avatar.dart';

/// App bar button to switch the selected account. Hidden with one account.
class AccountMenuButton extends StatelessWidget {
  const AccountMenuButton({super.key});

  @override
  Widget build(BuildContext context) {
    final state = SessionScope.watch(context);
    final selected = state.selectedAccount;
    if (state.accounts.length < 2 || selected == null) {
      return const SizedBox.shrink();
    }
    return PopupMenuButton<String>(
      tooltip: 'Switch account (${selected.email})',
      icon: InitialsAvatar(
        name: selected.label,
        seed: selected.email,
        radius: 14,
        coded: true,
      ),
      onSelected: state.selectAccount,
      itemBuilder: (context) => [
        for (final a in state.accounts)
          CheckedPopupMenuItem(
            value: a.id,
            checked: a.id == selected.id,
            child: Text(a.email, overflow: TextOverflow.ellipsis),
          ),
      ],
    );
  }
}

/// Two-line app bar title.
class AppBarTitle extends StatelessWidget {
  const AppBarTitle(this.title, {super.key, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, overflow: TextOverflow.ellipsis),
        if (subtitle != null && subtitle!.isNotEmpty)
          Text(
            subtitle!,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}
