// lib/core/theme/app_colors.dart
import 'package:flutter/material.dart';

class AppColors {
  // Couleurs principales
  static const Color primary = Color.fromARGB(255, 23, 8, 8);
  static const Color secondary = Color.fromARGB(255, 13, 12, 12);
  
  // Arrière-plans
  static const Color background = Color(0xFFF5F5F5);
  static const Color cardBackground = Color(0xFFFFFFFF);
  
  // Textes
  static const Color textPrimary = Color(0xFF333333);
  static const Color textSecondary = Color(0xFF888888);
  static const Color textLight = Color(0xFFFFFFFF);
  
  // États
  static const Color success = Color(0xFF4CAF50);
  static const Color error = Color(0xFFFF5252);
  static const Color warning = Color(0xFFFFC107);
  static const Color info = Color.fromARGB(255, 25, 11, 11);
  
  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color.fromARGB(255, 7, 6, 6), Color.fromARGB(255, 30, 9, 10)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  
  // Ombres
  static BoxShadow cardShadow = BoxShadow(
    color: Colors.black.withOpacity(0.1),
    blurRadius: 10,
    offset: const Offset(0, 5),
  );
  
  static BoxShadow lightShadow = BoxShadow(
    color: Colors.black.withOpacity(0.05),
    blurRadius: 5,
    offset: const Offset(0, 2),
  );
}