import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permissionless/permissionless.dart';
import 'package:permissionless_passkeys/permissionless_passkeys.dart';

import 'home_screen.dart';
import 'send_transaction_screen.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({
    super.key,
    required this.credential,
    required this.accountType,
  });

  final WebAuthnCredential credential;
  final AccountType accountType;

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  late final SmartAccount _account;
  late final WebAuthnAccount _webAuthnAccount;

  // Sepolia testnet
  static final _chainId = BigInt.from(11155111);

  @override
  void initState() {
    super.initState();
    _initializeAccount();
  }

  void _initializeAccount() {
    // Create WebAuthn account from credential (this is the owner for smart accounts)
    _webAuthnAccount = createWebAuthnAccount(
      credential: widget.credential,
      rpId: '28fc478be30e2f.lhr.life', // localhost.run for testing
    );

    if (widget.accountType == AccountType.kernel) {
      // Kernel v0.3.x supports WebAuthn validators
      _account = createKernelSmartAccount(
        owner: _webAuthnAccount, // WebAuthnAccount IS an AccountOwner
        chainId: _chainId,
        version: KernelVersion.v0_3_1,
      );
    } else {
      // Safe with WebAuthn shared signer
      _account = createSafeSmartAccount(
        owners: [_webAuthnAccount], // WebAuthnAccount IS an AccountOwner
        chainId: _chainId,
        version: SafeVersion.v1_4_1,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.accountType == AccountType.kernel
              ? 'Kernel Account'
              : 'Safe Account',
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSendTransactionCard(context),
              const SizedBox(height: 16),
              _buildAccountInfoCard(context),
              const SizedBox(height: 16),
              _buildCredentialInfoCard(context),
              const SizedBox(height: 16),
              _buildEncodingDemoCard(context),
              const SizedBox(height: 16),
              _buildExportCard(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSendTransactionCard(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => SendTransactionScreen(
              credential: widget.credential,
              accountType: widget.accountType,
            ),
          ),
        ),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.send,
                  color: Theme.of(context).colorScheme.onPrimary,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Send Transaction',
                      style:
                          Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Send ETH with sponsored or self-funded gas',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAccountInfoCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  widget.accountType == AccountType.kernel
                      ? Icons.memory
                      : Icons.security,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Account Info',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const Divider(),
            _buildInfoRow(
              'Type',
              widget.accountType == AccountType.kernel
                  ? 'Kernel v0.3.1'
                  : 'Safe v1.4.1',
            ),
            _buildInfoRow('Chain ID', _chainId.toString()),
            _buildInfoRow(
              'Entry Point',
              _formatAddress(_account.entryPoint.with0x),
            ),
            _buildInfoRow(
                'Nonce Key', '0x${_account.nonceKey.toRadixString(16)}'),
          ],
        ),
      ),
    );
  }

  Widget _buildCredentialInfoCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.key,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Passkey Credential',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const Divider(),
            _buildInfoRow('ID', _truncate(widget.credential.id, 24)),
            _buildInfoRow(
              'Public Key X',
              _truncate('0x${widget.credential.x.toRadixString(16)}', 24),
            ),
            _buildInfoRow(
              'Public Key Y',
              _truncate('0x${widget.credential.y.toRadixString(16)}', 24),
            ),
            _buildInfoRow('Owner Type', _webAuthnAccount.type),
          ],
        ),
      ),
    );
  }

  Widget _buildEncodingDemoCard(BuildContext context) {
    // Demo: encode a simple ETH transfer call
    final call = Call(
      to: EthereumAddress.fromHex('0x0000000000000000000000000000000000000001'),
      value: BigInt.from(1000000000000000), // 0.001 ETH
      data: '0x',
    );
    final encodedCall = _account.encodeCall(call);
    final stubSignature = _account.getStubSignature();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.code,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Encoding Demo',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const Divider(),
            Text(
              'Sample Call (0.001 ETH transfer):',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            _buildCopyableField(
              context,
              'Encoded Call',
              _truncate(encodedCall, 40),
              encodedCall,
            ),
            const SizedBox(height: 8),
            _buildCopyableField(
              context,
              'Stub Signature',
              _truncate(stubSignature, 40),
              stubSignature,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExportCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.file_download,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Export Credential',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const Divider(),
            Text(
              'Export your credential as JSON for backup or import into another app.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => _exportCredential(context),
              icon: const Icon(Icons.copy),
              label: const Text('Copy JSON to Clipboard'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCopyableField(
    BuildContext context,
    String label,
    String displayValue,
    String fullValue,
  ) {
    return InkWell(
      onTap: () => _copyToClipboard(context, label, fullValue),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    displayValue,
                    style:
                        const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.copy, size: 16),
          ],
        ),
      ),
    );
  }

  void _copyToClipboard(BuildContext context, String label, String value) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copied to clipboard')),
    );
  }

  void _exportCredential(BuildContext context) {
    // toJson() returns a compact JSON string, decode and re-encode with indentation
    final jsonString = widget.credential.toJson();
    final decoded = jsonDecode(jsonString);
    final prettyJson = const JsonEncoder.withIndent('  ').convert(decoded);

    Clipboard.setData(ClipboardData(text: prettyJson));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Credential JSON copied to clipboard')),
    );
  }

  String _formatAddress(String address) {
    if (address.length < 12) return address;
    return '${address.substring(0, 8)}...${address.substring(address.length - 6)}';
  }

  String _truncate(String value, int maxLength) {
    if (value.length <= maxLength) return value;
    return '${value.substring(0, maxLength)}...';
  }
}
