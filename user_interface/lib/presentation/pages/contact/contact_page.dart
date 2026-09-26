import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:lefture/core/config/app_config.dart';
import 'package:lefture/infrastructure/auth/authed_http.dart';
import 'package:lefture/infrastructure/repositories/backend_warmup.dart';
import 'package:lefture/infrastructure/supabase/supabase_client.dart';
import 'package:lefture/presentation/themes/app_colors.dart';
import 'package:lefture/presentation/widgets/app_error_dialog.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/widgets/snag_panel.dart';

class ContactPage extends HookConsumerWidget {
  const ContactPage({super.key});

  static const _baseUrl = AppConfig.backendBaseUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final formKey = useMemoized(() => GlobalKey<FormState>());
    
    // 画面が開いた瞬間にバックグラウンドでウォームアップ開始。
    final warmupFuture = useMemoized(() => BackendWarmup.waitUntilReady());

    // Form fields
    final selectedCategory = useState<String>('bug');
    final messageController = useTextEditingController();
    
    // Attachment state. Holds the final bytes/name/content-type to upload,
    // which may differ from what the user picked (e.g. a HEIC photo gets
    // converted to JPEG, see pickAttachment below).
    final attachmentBytes = useState<Uint8List?>(null);
    final attachmentFileName = useState<String?>(null);
    final attachmentContentType = useState<String?>(null);
    final isCompressingAttachment = useState(false);

    // Loading/Success states
    final isSubmitting = useState(false);
    final submissionSuccess = useState(false);
    final ticketCode = useState<String?>(null);
    final errorMessage = useState<String?>(null);
    final statusMessage = useState<String?>(null);

    void clearAttachment() {
      attachmentBytes.value = null;
      attachmentFileName.value = null;
      attachmentContentType.value = null;
    }

    // Pick file
    Future<void> pickAttachment() async {
      try {
        final result = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['jpg', 'jpeg', 'png', 'heic', 'heif', 'pdf', 'txt'],
          withData: true,
        );
        if (result == null || result.files.isEmpty) return;

        final picked = result.files.first;
        final rawBytes = picked.bytes ?? await File(picked.path!).readAsBytes();
        final lowerName = picked.name.toLowerCase();
        final isImage = lowerName.endsWith('.png') ||
            lowerName.endsWith('.jpg') ||
            lowerName.endsWith('.jpeg') ||
            lowerName.endsWith('.heic') ||
            lowerName.endsWith('.heif');

        if (!isImage) {
          attachmentBytes.value = rawBytes;
          attachmentFileName.value = picked.name;
          attachmentContentType.value = _guessContentType(picked.name);
          return;
        }

        isCompressingAttachment.value = true;
        try {
          // Resize + re-encode as JPEG. This also converts HEIC/HEIF (the
          // default format for iPhone photos) into something every mail
          // client and browser can actually render.
          final compressedBytes = await FlutterImageCompress.compressWithList(
            rawBytes,
            minWidth: 1920,
            minHeight: 1920,
            quality: 80,
          );
          // The plugin doesn't always throw when a device can't decode the
          // source (e.g. HEIC on an Android without a hardware codec, or a
          // desktop platform it doesn't support) - it can also just return an
          // empty list. Treat that the same as a thrown error.
          if (compressedBytes.isEmpty) {
            throw StateError('flutter_image_compress returned no bytes');
          }
          final dotIndex = picked.name.lastIndexOf('.');
          final baseName = dotIndex == -1 ? picked.name : picked.name.substring(0, dotIndex);
          attachmentBytes.value = compressedBytes;
          attachmentFileName.value = '$baseName.jpg';
          attachmentContentType.value = 'image/jpeg';
        } catch (e) {
          // Compression/conversion unavailable here - upload the original
          // file as-is rather than blocking the attachment entirely.
          attachmentBytes.value = rawBytes;
          attachmentFileName.value = picked.name;
          attachmentContentType.value = _guessContentType(picked.name);
        } finally {
          isCompressingAttachment.value = false;
        }
      } catch (e) {
        errorMessage.value = l10n.contactFailedToPickFile(
          snagMessageFor(l10n, e, origin: 'contact_page.pickFile'),
        );
      }
    }

    // Submit inquiry
    Future<void> submitForm() async {
      if (!formKey.currentState!.validate()) return;

      isSubmitting.value = true;
      errorMessage.value = null;

      if (supabase.auth.currentSession == null) {
        errorMessage.value = l10n.contactAuthError;
        isSubmitting.value = false;
        return;
      }
      // トークンの事前リフレッシュ・401時の再試行・再ログイン誘導はここが担う。
      final authedHttp = AuthedHttpClient(supabase);

      try {
        statusMessage.value = l10n.contactConnecting;
        final isServerReady = await warmupFuture;
        if (!isServerReady) {
          errorMessage.value = l10n.contactSlowService;
          return;
        }
        statusMessage.value = l10n.contactSending;

        String? attachmentR2Path;

        // 1. If attachment is selected, upload to R2
        if (attachmentBytes.value != null && attachmentFileName.value != null) {
          final fileName = attachmentFileName.value!;
          final contentType = attachmentContentType.value ?? _guessContentType(fileName);
          final fileBytes = attachmentBytes.value!;

          statusMessage.value = l10n.contactPreparingUpload;

          // Request presigned URL from backend (with 30s timeout)
          final presignedRes = await authedHttp.post(
            Uri.parse('$_baseUrl/support/request-upload-url'),
            payload: {
              'file_name': fileName,
              'content_type': contentType,
            },
            timeout: const Duration(seconds: 30),
          );

          if (presignedRes.statusCode != 200) {
            throw Exception('Failed to request upload URL: ${presignedRes.body}');
          }

          final presignedData = jsonDecode(presignedRes.body);
          final uploadUrl = presignedData['upload_url'] as String;
          attachmentR2Path = presignedData['storage_path'] as String;

          statusMessage.value = l10n.contactUploadingAttachment;

          // PUT file bytes to R2 (with 30s timeout)
          final putRes = await http.put(
            Uri.parse(uploadUrl),
            headers: {
              'Content-Type': contentType,
            },
            body: fileBytes,
          ).timeout(const Duration(seconds: 30));

          if (putRes.statusCode != 200) {
            throw Exception('Failed to upload file to R2: ${putRes.body}');
          }
        }

        statusMessage.value = l10n.contactSubmittingTicket;

        // Gather device info
        final packageInfo = await PackageInfo.fromPlatform();
        final deviceInfo = {
          'os': Platform.operatingSystem,
          'os_version': Platform.operatingSystemVersion,
          'app_version': '${packageInfo.version} (${packageInfo.buildNumber})',
          'locale': Platform.localeName,
        };

        // 2. Submit ticket metadata to backend (with 30s timeout)
        final submitRes = await authedHttp.post(
          Uri.parse('$_baseUrl/support/submit'),
          payload: {
            'category': selectedCategory.value,
            'message': messageController.text,
            'attachment_urls': attachmentR2Path != null ? [attachmentR2Path] : [],
            'device_info': deviceInfo,
          },
          timeout: const Duration(seconds: 30),
        );

        if (submitRes.statusCode != 200) {
          throw Exception('Failed to submit support ticket: ${submitRes.body}');
        }

        final submitData = jsonDecode(submitRes.body);
        ticketCode.value = submitData['ticket_code'] as String;
        submissionSuccess.value = true;
      } catch (e) {
        if (e is TimeoutException || e.toString().contains('TimeoutException')) {
          errorMessage.value = l10n.contactTimeoutError;
        } else {
          errorMessage.value = l10n.contactSubmissionError(
            snagMessageFor(l10n, e, origin: 'contact_page.submit'),
          );
        }
      } finally {
        isSubmitting.value = false;
        statusMessage.value = null;
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
          submissionSuccess.value ? l10n.contactTitleSent : l10n.contactTitle,
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
                          l10n.contactHelpTitle,
                          style: TextStyle(
                            color: AppColors.universe.textStarlight,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          l10n.contactHelpSubtitle,
                          style: TextStyle(
                            color: AppColors.universe.textComet,
                            fontSize: 14,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 28),
                        
                        if (errorMessage.value != null) ...[
                          AppErrorBox(
                            actionName: 'submitting your inquiry',
                            rawError: errorMessage.value,
                          ),
                          const SizedBox(height: 20),
                        ],

                        // Category Dropdown
                        DropdownButtonFormField<String>(
                          initialValue: selectedCategory.value,
                          isExpanded: true,
                          dropdownColor: const Color(0xFF13131C),
                          style: TextStyle(color: AppColors.universe.textStarlight, fontSize: 15),
                          decoration: inputDecoration(l10n.contactCategoryLabel),
                          items: [
                            DropdownMenuItem(
                              value: 'bug',
                              child: Text(l10n.contactCategoryBug, overflow: TextOverflow.ellipsis),
                            ),
                            DropdownMenuItem(
                              value: 'feature_request',
                              child: Text(l10n.contactCategoryFeedback, overflow: TextOverflow.ellipsis),
                            ),
                            DropdownMenuItem(
                              value: 'account',
                              child: Text(l10n.contactCategoryAccount, overflow: TextOverflow.ellipsis),
                            ),
                            DropdownMenuItem(
                              value: 'other',
                              child: Text(l10n.contactCategoryOther, overflow: TextOverflow.ellipsis),
                            ),
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
                          decoration: inputDecoration(l10n.contactMessageDetailsLabel).copyWith(
                            alignLabelWithHint: true,
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return l10n.contactMessageRequired;
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 20),

                        // Attachment Box
                        Text(
                          l10n.contactAttachmentLabel,
                          style: TextStyle(
                            color: AppColors.universe.textStarlight,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: (attachmentFileName.value == null && !isCompressingAttachment.value)
                              ? pickAttachment
                              : null,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                            decoration: BoxDecoration(
                              color: AppColors.universe.glassWhiteLow,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppColors.universe.glassBorder),
                            ),
                            child: isCompressingAttachment.value
                                ? Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.starGold),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        l10n.contactCompressingAttachment,
                                        style: TextStyle(color: AppColors.universe.textComet, fontSize: 14),
                                      ),
                                    ],
                                  )
                                : attachmentFileName.value != null
                                ? Row(
                                    children: [
                                      const Icon(Icons.insert_drive_file_outlined, color: AppColors.starGold),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          attachmentFileName.value!,
                                          style: TextStyle(color: AppColors.universe.textStarlight),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.close, color: AppColors.correctionRed),
                                        onPressed: clearAttachment,
                                      ),
                                    ],
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.cloud_upload_outlined, color: AppColors.universe.textComet),
                                      const SizedBox(width: 12),
                                      Flexible(
                                        child: Text(
                                          l10n.contactUploadButton,
                                          style: TextStyle(color: AppColors.universe.textComet, fontSize: 14),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                        
                        const SizedBox(height: 36),

                        // Submit Button
                        isSubmitting.value
                            ? Center(
                                child: Column(
                                  children: [
                                    const CircularProgressIndicator(color: AppColors.starGold),
                                    if (statusMessage.value != null) ...[
                                      const SizedBox(height: 12),
                                      Text(
                                        statusMessage.value!,
                                        style: TextStyle(
                                          color: AppColors.universe.textComet,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
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
                                child: Text(
                                  l10n.contactSubmitButton,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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
    final l10n = AppLocalizations.of(context);
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
            l10n.contactSuccessTitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.universe.textStarlight,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.contactSuccessDescription,
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
                  l10n.contactTicketCodeLabel,
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
            child: Text(
              l10n.contactBackToSettingsButton,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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
    if (lower.endsWith('.heic')) return 'image/heic';
    if (lower.endsWith('.heif')) return 'image/heif';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.txt')) return 'text/plain';
    return 'application/octet-stream';
  }
}
