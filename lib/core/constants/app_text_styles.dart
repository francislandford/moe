import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:moe/core/constants/app_colors.dart';
import 'package:moe/core/constants/app_font.dart';

class AppTextStyles {
  static TextStyle heading1 = TextStyle(fontFamily: AppFont.primaryFont, fontSize: 24,
    fontWeight: FontWeight.bold,
    color: AppColors.textPrimary,);

  static TextStyle heading2 = TextStyle(fontFamily: AppFont.primaryFont, fontSize: 24,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,);

  static TextStyle bodyLarge = TextStyle(
    fontFamily: AppFont.primaryFont,
    fontSize: 16,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary,
  );

  static TextStyle bodyMedium = TextStyle(fontFamily: AppFont.primaryFont, fontSize: 14,
    color: AppColors.textPrimary,);

  static TextStyle label = TextStyle(
    fontFamily: AppFont.primaryFont,
    fontSize: 14,
    color: AppColors.textSecondary,
  );
}