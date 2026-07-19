import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';

import 'package:lecture_companion_ui/infrastructure/supabase/supabase_client.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';

class ContactPage extends HookConsumerWidget {
  const ContactPage({super.key});

  static const _baseUrl = 'https://lefture-511705914929.us-west1.run.app';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final formKey = useMemoized(() => GlobalKey<FormState>());
    
    // Form fields
    final selectedCategory = useState<String>('bug');
    final messageController = useTextEditingController();
    
    // Attachment state
    final selectedFile = useState<PlatformFile?>(null);
    
    // Loading/Success states
    final isSubmitting = useState(false);
    final submissionSuccess = useState(false);
    final ticketCode = useState<String?>(null);
    final errorMessage = useState<String?>(null);

    // Pick file
    Future<void> pickAttachment() async {
      try {
        final result = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf', 'txt'],
        );
        if (result != null && result.files.isNotEmpty) {
          selectedFile.value = result.files.first;
        }
      } catch (e) {
        errorMessage.value = 'Failed to pick file: $e';
      }
    }

    // Submit inquiry
    Future<void> submitForm() async {
      if (!formKey.currentState!.validate()) return;

      isSubmitting.value = true;
      errorMessage.value = null;

      final jwt = supabase.auth.currentSession?.accessToken;
      if (jwt == null) {
        errorMessage.value = 'Authentication error. Please sign in again.';
        isSubmitting.value = false;
        return;
      }

      try {
        String? attachmentR2Path;

        // 1. If attachment is selected, upload to R2
        if (selectedFile.value != null) {
          final file = selectedFile.value!;
          
          // Request presigned URL from backend (with 10s timeout)
          final presignedRes = await http.post(
            Uri.parse('$_baseUrl/support/request-upload-url'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $jwt',
            },
            body: jsonEncode({
              'file_name': file.name,
              'content_type': _guessContentType(file.name),
            }),
          ).timeout(const Duration(seconds: 10));

          if (presignedRes.statusCode != 200) {
            throw Exception('Failed to request upload URL: ${presignedRes.body}');
          }

          final presignedData = jsonDecode(presignedRes.body);
          final uploadUrl = presignedData['upload_url'] as String;
          attachmentR2Path = presignedData['storage_path'] as String;

          // PUT file bytes to R2 (with 10s timeout)
          final fileBytes = file.bytes ?? await File(file.path!).readAsBytes();
          final putRes = await http.put(
            Uri.parse(uploadUrl),
            headers: {
              'Content-Type': _guessContentType(file.name),
            },
            body: fileBytes,
          ).timeout(const Duration(seconds: 10));

          if (putRes.statusCode != 200) {
            throw Exception('Failed to upload file to R2: ${putRes.body}');
          }
        }

        // Gather device info
        final deviceInfo = {
          'os': Platform.operatingSystem,
          'os_version': Platform.operatingSystemVersion,
          'app_version': '1.0.0+1',
          'locale': Platform.localeName,
        };

        // 2. Submit ticket metadata to backend (with 10s timeout)
        final submitRes = await http.post(
          Uri.parse('$_baseUrl/support/submit'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $jwt',
          },
          body: jsonEncode({
            'category': selectedCategory.value,
            'message': messageController.text,
            'attachment_urls': attachmentR2Path != null ? [attachmentR2Path] : [],
            'device_info': deviceInfo,
          }),
        ).timeout(const Duration(seconds: 10));

        if (submitRes.statusCode != 200) {
          throw Exception('Failed to submit support ticket: ${submitRes.body}');
        }

        final submitData = jsonDecode(submitRes.body);
        ticketCode.value = submitData['ticket_code'] as String;
        submissionSuccess.value = true;
      } catch (e) {
        if (e is TimeoutException || e.toString().contains('TimeoutException')) {
          errorMessage.value = 'Connection timed out. Please check your network and try again, or email us at support@lefture.com.';
        } else {
          errorMessage.value = 'Submission failed: ${e.toString().replaceAll('Exception: ', '')}. You can also email us at support@lefture.com.';
        }
      } finally {
        isSubmitting.value = false;
      }
    }

    InputDecoration inputDecoration(String label) {
      return InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: AppColors.universe.textComet),
        filled: true,
        fillColor: AppColors.universe.glassWhiteLow,
        border: OutlineInputBorder(
          borderSide: BorderSide.none,
          borderRadius: BorderRadius.circular(14),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: AppColors.universe.glassBorder),
          borderRadius: BorderRadius.circular(14),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: AppColors.starGold, width: 1.5),
          borderRadius: BorderRadius.circular(14),
        ),
        errorBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: AppColors.correctionRed),
          borderRadius: BorderRadius.circular(14),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.universe.voidBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          submissionSuccess.value ? 'Sent' : 'Contact Us',
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: submissionSuccess.value
                ? _buildSuccessUI(context, ticketCode.value ?? '')
                : Form(
                    key: formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 12),
                        Text(
                          'How can we help you?',
                          style: TextStyle(
                            color: AppColors.universe.textStarlight,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Please choose a category and specify your question or bug report below. We will reply to your email shortly.',
                          style: TextStyle(
                            color: AppColors.universe.textComet,
                            fontSize: 14,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 28),
                        
                        if (errorMessage.value != null) ...[
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppColors.correctionRed.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppColors.correctionRed.withValues(alpha: 0.3)),
                            ),
                            child: Text(
                              errorMessage.value!,
                              style: const TextStyle(color: AppColors.correctionRed),
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],

                        // Category Dropdown
                        DropdownButtonFormField<String>(
                          initialValue: selectedCategory.value,
                          dropdownColor: const Color(0xFF13131C),
                          style: TextStyle(color: AppColors.universe.textStarlight, fontSize: 15),
                          decoration: inputDecoration('Category'),
                          items: const [
                            DropdownMenuItem(value: 'bug', child: Text('Bug Report')),
                            DropdownMenuItem(value: 'feature_request', child: Text('Request / Feedback')),
                            DropdownMenuItem(value: 'account', child: Text('Account / Login')),
                            DropdownMenuItem(value: 'other', child: Text('Other')),
                          ],
                          onChanged: (val) {
                            if (val != null) selectedCategory.value = val;
                          },
                        ),
                        const SizedBox(height: 20),

                        // Message Input
                        TextFormField(
                          controller: messageController,
                          maxLines: 8,
                          style: TextStyle(color: AppColors.universe.textStarlight, fontSize: 15),
                          cursorColor: AppColors.starGold,
                          decoration: inputDecoration('Message Details').copyWith(
                            alignLabelWithHint: true,
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter your message details';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 20),

                        // Attachment Box
                        Text(
                          'Attachment (Optional)',
                          style: TextStyle(
                            color: AppColors.universe.textStarlight,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: selectedFile.value == null ? pickAttachment : null,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                            decoration: BoxDecoration(
                              color: AppColors.universe.glassWhiteLow,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppColors.universe.glassBorder),
                            ),
                            child: selectedFile.value != null
                                ? Row(
                                    children: [
                                      const Icon(Icons.insert_drive_file_outlined, color: AppColors.starGold),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          selectedFile.value!.name,
                                          style: TextStyle(color: AppColors.universe.textStarlight),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.close, color: AppColors.correctionRed),
                                        onPressed: () => selectedFile.value = null,
                                      ),
                                    ],
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.cloud_upload_outlined, color: AppColors.universe.textComet),
                                      const SizedBox(width: 12),
                                      Text(
                                        'Upload Screenshot or File',
                                        style: TextStyle(color: AppColors.universe.textComet, fontSize: 14),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                        
                        const SizedBox(height: 36),

                        // Submit Button
                        isSubmitting.value
                            ? const Center(
                                child: CircularProgressIndicator(color: AppColors.starGold),
                              )
                            : ElevatedButton(
                                onPressed: submitForm,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.starGold,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  minimumSize: const Size(double.infinity, 52),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: const Text(
                                  'Send Inquiry',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                              ),
                      ],
                    ),
                  ),
          ),
        ),
    );
  }

  Widget _buildSuccessUI(BuildContext context, String code) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 40),
          Center(
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.growthGreen.withValues(alpha: 0.15),
                border: Border.all(color: AppColors.growthGreen, width: 1.5),
              ),
              child: const Icon(
                Icons.check_rounded,
                color: AppColors.growthGreen,
                size: 36,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Inquiry Sent',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.universe.textStarlight,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Your inquiry has been successfully sent. A confirmation email has been sent to your inbox. We will review your message and reply via email.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.universe.textComet,
              fontSize: 14,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
            decoration: BoxDecoration(
              color: AppColors.universe.glassWhiteLow,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.universe.glassBorder),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Ticket Code',
                  style: TextStyle(color: AppColors.universe.textComet, fontWeight: FontWeight.bold),
                ),
                Text(
                  code,
                  style: const TextStyle(
                    color: AppColors.starGold,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
          ElevatedButton(
            onPressed: () => context.pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.starGold,
              foregroundColor: Colors.white,
              elevation: 0,
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text(
              'Back to Settings',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  String _guessContentType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.txt')) return 'text/plain';
    return 'application/octet-stream';
  }
}
