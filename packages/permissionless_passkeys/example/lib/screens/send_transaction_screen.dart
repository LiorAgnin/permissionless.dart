import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permissionless/permissionless.dart';
import 'package:permissionless_passkeys/permissionless_passkeys.dart';

import 'home_screen.dart';

/// Transaction funding mode
enum FundingMode {
  sponsored,
  selfFunded,
}

class SendTransactionScreen extends StatefulWidget {
  const SendTransactionScreen({
    super.key,
    required this.credential,
    required this.accountType,
  });

  final WebAuthnCredential credential;
  final AccountType accountType;

  @override
  State<SendTransactionScreen> createState() => _SendTransactionScreenState();
}

class _SendTransactionScreenState extends State<SendTransactionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _recipientController = TextEditingController();
  final _amountController = TextEditingController();
  final _apiKeyController = TextEditingController();

  FundingMode _fundingMode = FundingMode.sponsored;
  bool _isLoading = false;
  String? _errorMessage;
  String? _txHash;
  String? _userOpHash;
  TransactionStatus _status = TransactionStatus.idle;

  // Sepolia testnet
  static final _chainId = BigInt.from(11155111);
  static const _chainName = 'sepolia';

  late final SmartAccount _account;
  late final WebAuthnAccount _webAuthnAccount;

  @override
  void initState() {
    super.initState();
    _initializeAccount();
    _amountController.text = '0'; // Self-ping with no ETH transfer
  }

  @override
  void dispose() {
    _recipientController.dispose();
    _amountController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _initializeAccount() async {
    _webAuthnAccount = createWebAuthnAccount(
      credential: widget.credential,
      rpId: '28fc478be30e2f.lhr.life', // localhost.run - match registration
    );

    if (widget.accountType == AccountType.kernel) {
      // Kernel account needs a publicClient to compute address via RPC
      final publicClient = createPublicClient(
        url: 'https://eth-sepolia.g.alchemy.com/v2/YOUR_KEY',
      );
      _account = createKernelSmartAccount(
        owner: _webAuthnAccount,
        chainId: _chainId,
        version: KernelVersion.v0_3_1,
        publicClient: publicClient,
      );
    } else {
      // Safe account can compute address locally
      _account = createSafeSmartAccount(
        owners: [_webAuthnAccount],
        chainId: _chainId,
        version: SafeVersion.v1_4_1,
      );
    }

    // Pre-fill recipient with account address (send to self like examples)
    final address = await _account.getAddress();
    if (mounted) {
      setState(() {
        _recipientController.text = address.hex;
      });
    }
  }

  Future<void> _sendTransaction() async {
    if (!_formKey.currentState!.validate()) return;

    final apiKey = _apiKeyController.text.trim();
    if (apiKey.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter your Pimlico API key';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _txHash = null;
      _userOpHash = null;
      _status = TransactionStatus.preparing;
    });

    try {
      final recipient =
          EthereumAddress.fromHex(_recipientController.text.trim());
      final amountEth = double.parse(_amountController.text.trim());
      final amountWei = BigInt.from(amountEth * 1e18); // Convert ETH to wei

      // Create bundler client (Pimlico)
      final bundlerUrl =
          'https://api.pimlico.io/v2/$_chainName/rpc?apikey=$apiKey';
      final pimlicoClient = createPimlicoClient(
        url: bundlerUrl,
        entryPoint: _account.entryPoint,
      );

      // Create public client for nonce queries
      final publicClient = createPublicClient(
        url: 'https://eth-sepolia.g.alchemy.com/v2/YOUR_KEY',
        // url: 'https://rpc.sepolia.org',
      );

      // Create paymaster client if sponsored
      PaymasterClient? paymasterClient;
      if (_fundingMode == FundingMode.sponsored) {
        final paymasterUrl =
            'https://api.pimlico.io/v2/$_chainName/rpc?apikey=$apiKey';
        paymasterClient = createPaymasterClient(
          url: paymasterUrl,
        );
      }

      // Create smart account client
      // Use conservative gas multipliers for WebAuthn/P256 signature verification
      final client = createSmartAccountClient(
        account: _account,
        bundler: pimlicoClient,
        publicClient: publicClient,
        paymaster: paymasterClient,
        gasMultipliers: GasMultipliers.conservative,
      );

      // Get gas prices
      setState(() => _status = TransactionStatus.estimatingGas);
      final gasPrices = await pimlicoClient.getUserOperationGasPrice();

      // Create the call
      final call = Call(
        to: recipient,
        value: amountWei,
        data: '0x',
      );

      // Send the UserOperation
      setState(() => _status = TransactionStatus.signing);

      final userOpHash = await client.sendUserOperation(
        calls: [call],
        maxFeePerGas: gasPrices.fast.maxFeePerGas,
        maxPriorityFeePerGas: gasPrices.fast.maxPriorityFeePerGas,
      );

      setState(() {
        _userOpHash = userOpHash;
        _status = TransactionStatus.pending;
      });

      // Wait for receipt
      final receipt = await client.waitForReceipt(
        userOpHash,
        timeout: const Duration(seconds: 120),
      );

      if (receipt != null) {
        setState(() {
          _txHash = receipt.receipt?.transactionHash ?? _userOpHash;
          _status = receipt.success
              ? TransactionStatus.success
              : TransactionStatus.failed;
        });
      } else {
        setState(() {
          _status = TransactionStatus.timeout;
          _errorMessage = 'Transaction timed out waiting for confirmation';
        });
      }

      // Clean up
      client.close();
      publicClient.close();
    } catch (e) {
      setState(() {
        _status = TransactionStatus.failed;
        _errorMessage = _formatError(e);
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  String _formatError(Object error) {
    final message = error.toString();

    if (message.contains('AA13')) {
      return 'Account deployment failed (initCode error). '
          'This can happen if the WebAuthn validator configuration is invalid. '
          'Try using ${widget.accountType == AccountType.kernel ? 'Safe' : 'Kernel'} type instead of ${widget.accountType == AccountType.kernel ? 'Kernel' : 'Safe'}.';
    }
    if (message.contains('AA21')) {
      return 'Account not deployed and no funds for deployment. '
          'Try sponsored mode or fund your account first.';
    }
    if (message.contains('AA23')) {
      return 'Account deployment reverted. Check that the passkey credentials '
          'are valid and the account type supports WebAuthn.';
    }
    if (message.contains('AA31')) {
      return 'Paymaster stake or deposit too low.';
    }
    if (message.contains('AA41')) {
      return 'Paymaster expired or invalid.';
    }
    if (message.contains('insufficient funds')) {
      return 'Insufficient funds for gas. Try sponsored mode.';
    }
    if (message.contains('invalid apikey')) {
      return 'Invalid Pimlico API key.';
    }

    return 'Transaction failed: $message';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Send Transaction'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildAccountInfoCard(context),
                const SizedBox(height: 16),
                _buildApiKeyCard(context),
                const SizedBox(height: 16),
                _buildFundingModeCard(context),
                const SizedBox(height: 16),
                _buildTransactionForm(context),
                const SizedBox(height: 16),
                if (_status != TransactionStatus.idle)
                  _buildStatusCard(context),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 16),
                  _buildErrorCard(context),
                ],
                const SizedBox(height: 24),
                _buildSendButton(context),
              ],
            ),
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
                  widget.accountType == AccountType.kernel
                      ? 'Kernel Account'
                      : 'Safe Account',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Chain: Sepolia (${_chainId.toString()})',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            FutureBuilder<EthereumAddress>(
              future: _account.getAddress(),
              builder: (context, snapshot) {
                final address = snapshot.data?.hex ?? 'Loading...';
                return Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Address: ${_truncateAddress(address)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                            ),
                      ),
                    ),
                    if (snapshot.hasData)
                      IconButton(
                        icon: const Icon(Icons.copy, size: 16),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: address));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Address copied to clipboard')),
                          );
                        },
                        tooltip: 'Copy address',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildApiKeyCard(BuildContext context) {
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
                  'Pimlico API Key',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Get a free API key at dashboard.pimlico.io',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _apiKeyController,
              decoration: const InputDecoration(
                labelText: 'API Key',
                hintText: 'pim_...',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.vpn_key),
              ),
              obscureText: true,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'API key is required';
                }
                return null;
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFundingModeCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.account_balance_wallet,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Gas Payment',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 12),
            SegmentedButton<FundingMode>(
              segments: const [
                ButtonSegment(
                  value: FundingMode.sponsored,
                  label: Text('Sponsored'),
                  icon: Icon(Icons.card_giftcard),
                ),
                ButtonSegment(
                  value: FundingMode.selfFunded,
                  label: Text('Self-Funded'),
                  icon: Icon(Icons.payments),
                ),
              ],
              selected: {_fundingMode},
              onSelectionChanged: (selected) {
                setState(() => _fundingMode = selected.first);
              },
            ),
            const SizedBox(height: 8),
            Text(
              _fundingMode == FundingMode.sponsored
                  ? 'Gas fees paid by Pimlico paymaster (free on testnets)'
                  : 'Gas fees paid from your account balance',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionForm(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.send,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Transaction Details',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _recipientController,
              decoration: const InputDecoration(
                labelText: 'Recipient Address',
                hintText: '0x...',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Recipient address is required';
                }
                if (!value.trim().startsWith('0x') ||
                    value.trim().length != 42) {
                  return 'Invalid Ethereum address';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _amountController,
              decoration: const InputDecoration(
                labelText: 'Amount (ETH)',
                hintText: '0.001',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.attach_money),
                suffixText: 'ETH',
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Amount is required';
                }
                final amount = double.tryParse(value.trim());
                if (amount == null || amount < 0) {
                  return 'Invalid amount';
                }
                return null;
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(BuildContext context) {
    return Card(
      color: _getStatusColor(context),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _getStatusIcon(),
                const SizedBox(width: 8),
                Text(
                  _getStatusTitle(),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(_getStatusDescription()),
            if (_userOpHash != null) ...[
              const SizedBox(height: 8),
              _buildCopyableField(
                context,
                'UserOp Hash',
                _userOpHash!,
              ),
            ],
            if (_txHash != null) ...[
              const SizedBox(height: 8),
              _buildCopyableField(
                context,
                'Transaction Hash',
                _txHash!,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Icon(
              Icons.error_outline,
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _errorMessage!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSendButton(BuildContext context) {
    return FilledButton.icon(
      onPressed: _isLoading ? null : _sendTransaction,
      icon: _isLoading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.send),
      label: Text(_isLoading ? 'Sending...' : 'Send Transaction'),
    );
  }

  Widget _buildCopyableField(
    BuildContext context,
    String label,
    String value,
  ) {
    return InkWell(
      onTap: () {
        Clipboard.setData(ClipboardData(text: value));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$label copied to clipboard')),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(4),
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
                  Text(
                    _truncateHash(value),
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

  Color _getStatusColor(BuildContext context) {
    switch (_status) {
      case TransactionStatus.success:
        return Colors.green.shade100;
      case TransactionStatus.failed:
      case TransactionStatus.timeout:
        return Theme.of(context).colorScheme.errorContainer;
      default:
        return Theme.of(context).colorScheme.primaryContainer;
    }
  }

  Widget _getStatusIcon() {
    switch (_status) {
      case TransactionStatus.success:
        return const Icon(Icons.check_circle, color: Colors.green);
      case TransactionStatus.failed:
      case TransactionStatus.timeout:
        return Icon(Icons.error, color: Colors.red.shade700);
      case TransactionStatus.pending:
        return const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      default:
        return const Icon(Icons.hourglass_empty);
    }
  }

  String _getStatusTitle() {
    switch (_status) {
      case TransactionStatus.preparing:
        return 'Preparing Transaction';
      case TransactionStatus.estimatingGas:
        return 'Estimating Gas';
      case TransactionStatus.signing:
        return 'Signing with Passkey';
      case TransactionStatus.pending:
        return 'Transaction Pending';
      case TransactionStatus.success:
        return 'Transaction Successful';
      case TransactionStatus.failed:
        return 'Transaction Failed';
      case TransactionStatus.timeout:
        return 'Transaction Timeout';
      case TransactionStatus.idle:
        return '';
    }
  }

  String _getStatusDescription() {
    switch (_status) {
      case TransactionStatus.preparing:
        return 'Building the UserOperation...';
      case TransactionStatus.estimatingGas:
        return 'Fetching gas prices and estimates...';
      case TransactionStatus.signing:
        return 'Please authenticate with your passkey...';
      case TransactionStatus.pending:
        return 'Waiting for transaction to be included in a block...';
      case TransactionStatus.success:
        return 'Your transaction was successfully executed!';
      case TransactionStatus.failed:
        return 'The transaction failed to execute.';
      case TransactionStatus.timeout:
        return 'Timed out waiting for transaction confirmation.';
      case TransactionStatus.idle:
        return '';
    }
  }

  String _truncateAddress(String address) {
    if (address.length < 20) return address;
    return '${address.substring(0, 10)}...${address.substring(address.length - 8)}';
  }

  String _truncateHash(String hash) {
    if (hash.length < 20) return hash;
    return '${hash.substring(0, 14)}...${hash.substring(hash.length - 10)}';
  }
}

enum TransactionStatus {
  idle,
  preparing,
  estimatingGas,
  signing,
  pending,
  success,
  failed,
  timeout,
}
