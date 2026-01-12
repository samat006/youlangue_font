// lib/presentation/widgets/transcript_view.dart

import 'package:flutter/material.dart';
import '../../data/models/translation_model.dart';

class TranscriptView extends StatefulWidget {
  final List<AudioChunk> transcripts;

  const TranscriptView({
    Key? key,
    required this.transcripts,
  }) : super(key: key);

  @override
  State<TranscriptView> createState() => _TranscriptViewState();
}

class _TranscriptViewState extends State<TranscriptView> {
  final ScrollController _scrollController = ScrollController();
  
  @override
  void didUpdateWidget(TranscriptView oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // Auto-scroll vers le bas
    if (widget.transcripts.length > oldWidget.transcripts.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    if (widget.transcripts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.subtitles_outlined,
              size: 60,
              color: Colors.grey[600],
            ),
            SizedBox(height: 16),
            Text(
              'Les transcriptions apparaîtront ici',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }
    
    return Container(
      color: Color(0xFFF5F5F5),
      child: ListView.builder(
        controller: _scrollController,
        padding: EdgeInsets.all(16),
        itemCount: widget.transcripts.length,
        itemBuilder: (context, index) {
          final chunk = widget.transcripts[index];
          
          return Card(
            margin: EdgeInsets.only(bottom: 12),
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Numéro du chunk
                  Row(
                    children: [
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFF668EEA), Color(0xFF734BA2)],
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '#${chunk.sequence + 1}',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  
                  // Transcription originale
                  if (chunk.transcript.isNotEmpty) ...[
                    Text(
                      'Original:',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      chunk.transcript,
                      style: TextStyle(
                        fontSize: 13,
                        color: Color(0xFF333333),
                      ),
                    ),
                    SizedBox(height: 8),
                  ],
                  
                  // Traduction
                  if (chunk.translation.isNotEmpty) ...[
                    Text(
                      'Traduit:',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      chunk.translation,
                      style: TextStyle(
                        fontSize: 14,
                        color: Color(0xFF667EEA),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
  
  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}