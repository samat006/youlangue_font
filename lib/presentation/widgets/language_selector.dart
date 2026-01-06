// lib/presentation/widgets/language_selector.dart

import 'package:flutter/material.dart';

class LanguageSelector extends StatelessWidget {
  final List<Map<String, String>> languages;
  final String selectedLang;
  final Function(String) onChanged;

  const LanguageSelector({
    Key? key,
    required this.languages,
    required this.selectedLang,
    required this.onChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 5,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selectedLang,
          isExpanded: true,
          icon: Icon(Icons.arrow_drop_down, color: Color(0xFF667EEA)),
          style: TextStyle(
            color: Color(0xFF333333),
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          items: languages.map((lang) {
            return DropdownMenuItem<String>(
              value: lang['code'],
              child: Row(
                children: [
                  Text(
                    lang['flag']!,
                    style: TextStyle(fontSize: 20),
                  ),
                  SizedBox(width: 8),
                  Text(lang['name']!),
                ],
              ),
            );
          }).toList(),
          onChanged: (value) {
            if (value != null) onChanged(value);
          },
        ),
      ),
    );
  }
}