import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_text_styles.dart';

/// Campo de foto opcional (tirar ou escolher da galeria), com preview.
class FotoPickerField extends StatelessWidget {
  final File? arquivo;
  final ValueChanged<File?> onChanged;
  final String label;

  const FotoPickerField({
    super.key,
    required this.arquivo,
    required this.onChanged,
    this.label = 'Adicionar foto (opcional)',
  });

  Future<void> _escolher(BuildContext context) async {
    final picker = ImagePicker();
    final origem = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Tirar foto'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Escolher da galeria'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (origem == null) return;
    final foto = await picker.pickImage(source: origem, imageQuality: 80);
    if (foto != null) onChanged(File(foto.path));
  }

  @override
  Widget build(BuildContext context) {
    if (arquivo != null) {
      return Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.file(arquivo!, height: 160, width: double.infinity, fit: BoxFit.cover),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: GestureDetector(
              onTap: () => onChanged(null),
              child: const CircleAvatar(
                radius: 14,
                backgroundColor: AppColors.topBarDark,
                child: Icon(Icons.close, size: 16, color: AppColors.white),
              ),
            ),
          ),
        ],
      );
    }

    return InkWell(
      onTap: () => _escolher(context),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 100,
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.cardBorder, style: BorderStyle.solid),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add_a_photo_outlined, color: AppColors.textSecondary),
            const SizedBox(height: 6),
            Text(label, style: AppTextStyles.bodySecondary),
          ],
        ),
      ),
    );
  }
}
