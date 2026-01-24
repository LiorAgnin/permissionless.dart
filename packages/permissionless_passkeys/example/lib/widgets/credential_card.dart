import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permissionless_passkeys/permissionless_passkeys.dart';

class CredentialCard extends StatelessWidget {
  const CredentialCard({
    super.key,
    required this.credential,
  });

  final WebAuthnCredential credential;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.fingerprint,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Passkey Credential',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                      ),
                      Text(
                        'P-256 (secp256r1)',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy),
                  tooltip: 'Copy credential ID',
                  onPressed: () => _copyCredentialId(context),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildField(
              context,
              'Credential ID',
              _truncateMiddle(credential.id, 32),
            ),
            const SizedBox(height: 8),
            _buildField(
              context,
              'Public Key Hash',
              _truncateMiddle(credential.publicKeyHex, 24),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField(BuildContext context, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 2),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            value,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }

  void _copyCredentialId(BuildContext context) {
    Clipboard.setData(ClipboardData(text: credential.id));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Credential ID copied to clipboard')),
    );
  }

  String _truncateMiddle(String value, int maxLength) {
    if (value.length <= maxLength) return value;
    final half = (maxLength - 3) ~/ 2;
    return '${value.substring(0, half)}...${value.substring(value.length - half)}';
  }
}
