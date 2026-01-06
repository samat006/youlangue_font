// lib/presentation/widgets/voice_selector.dart

import 'package:flutter/material.dart';

class VoiceSelector extends StatelessWidget {
  final List<Map<String, String>> voices;
  final String selectedVoice;
  final Function(String) onChanged;

  const VoiceSelector({
    Key? key,
    required this.voices,
    required this.selectedVoice,
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
          value: selectedVoice,
          isExpanded: true,
          icon: Icon(Icons.arrow_drop_down, color: Color(0xFF667EEA)),
          style: TextStyle(
            color: Color(0xFF333333),
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          items: voices.map((voice) {
            return DropdownMenuItem<String>(
              value: voice['code'],
              child: Row(
                children: [
                  Text(
                    voice['icon']!,
                    style: TextStyle(fontSize: 18),
                  ),
                  SizedBox(width: 8),
                  Text(voice['name']!),
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