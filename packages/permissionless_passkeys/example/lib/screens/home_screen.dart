import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/credential_provider.dart';
import '../widgets/credential_card.dart';
import 'account_screen.dart';
import 'register_screen.dart';

enum AccountType { kernel, safe }

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final credentialState = ref.watch(credentialProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Passkeys Smart Account'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: credentialState.hasCredential
              ? _CredentialView(credential: credentialState.credential!)
              : const _NoCredentialView(),
        ),
      ),
    );
  }
}

class _NoCredentialView extends StatelessWidget {
  const _NoCredentialView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.fingerprint,
            size: 100,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 24),
          Text(
            'No Passkey Registered',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Register a passkey to create a smart account',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: () => _navigateToRegister(context),
            icon: const Icon(Icons.add),
            label: const Text('Register Passkey'),
          ),
        ],
      ),
    );
  }

  void _navigateToRegister(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const RegisterScreen(),
      ),
    );
  }
}

class _CredentialView extends ConsumerWidget {
  const _CredentialView({required this.credential});

  final dynamic credential;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CredentialCard(credential: credential),
          const SizedBox(height: 24),
          _AccountTypeCard(
            title: 'Kernel Account',
            subtitle: 'ZeroDev Kernel v0.3.x with WebAuthn validator',
            icon: Icons.memory,
            onTap: () => _navigateToAccount(
              context,
              AccountType.kernel,
              credential,
            ),
          ),
          const SizedBox(height: 12),
          _AccountTypeCard(
            title: 'Safe Account',
            subtitle: 'Safe v1.4.1 with WebAuthn shared signer',
            icon: Icons.security,
            onTap: () => _navigateToAccount(
              context,
              AccountType.safe,
              credential,
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () =>
                ref.read(credentialProvider.notifier).clearCredential(),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Clear Credential'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToAccount(
    BuildContext context,
    AccountType type,
    dynamic credential,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AccountScreen(
          credential: credential,
          accountType: type,
        ),
      ),
    );
  }
}

class _AccountTypeCard extends StatelessWidget {
  const _AccountTypeCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon, size: 32),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
