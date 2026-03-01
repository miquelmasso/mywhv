import 'package:flutter/material.dart';

import '../services/report_service.dart';

class ReportMessagePage extends StatefulWidget {
  const ReportMessagePage({super.key});

  @override
  State<ReportMessagePage> createState() => _ReportMessagePageState();
}

class _ReportMessagePageState extends State<ReportMessagePage> {
  final TextEditingController _messageController = TextEditingController();
  final ReportService _reportService = const ReportService();

  bool _isSending = false;
  String? _feedbackText;
  bool _feedbackIsError = false;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _handleSend() async {
    FocusScope.of(context).unfocus();

    setState(() {
      _isSending = true;
      _feedbackText = null;
      _feedbackIsError = false;
    });

    final result = await _reportService.sendReport(_messageController.text);
    if (!mounted) return;

    setState(() {
      _isSending = false;
      _feedbackText = result.message;
      _feedbackIsError = !result.success;
      if (result.success) {
        _messageController.clear();
      }
    });

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: result.success ? Colors.green.shade700 : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Send report')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Message',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: TextField(
                  controller: _messageController,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: InputDecoration(
                    hintText: 'Write your message...',
                    filled: true,
                    fillColor: const Color(0xFFF8F6F6),
                    counterText: '',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.all(16),
                  ),
                  maxLength: 2000,
                  onChanged: (_) {
                    setState(() {
                      if (_feedbackText != null) {
                        _feedbackText = null;
                      }
                    });
                  },
                ),
              ),
              if (_feedbackText != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _feedbackIsError
                        ? const Color(0xFFFFF1F0)
                        : const Color(0xFFEAF8EC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _feedbackIsError
                          ? const Color(0xFFFFC9C4)
                          : const Color(0xFFB8E3BE),
                    ),
                  ),
                  child: Text(
                    _feedbackText!,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _feedbackIsError
                          ? const Color(0xFFB5342E)
                          : const Color(0xFF267B37),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSending ? null : _handleSend,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 52),
                    backgroundColor: const Color(0xFFFF9800),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _isSending
                      ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              theme.colorScheme.onPrimary,
                            ),
                          ),
                        )
                      : const Text(
                          'Send',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Between 5 and 2000 characters.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'This report is sent through the secure WorkyDay backend.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
              const SizedBox(height: 2),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '${_messageController.text.trim().length}/2000',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
