// lib/presentation/screens/home_screen.dart

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../../data/services/youtube_service.dart';
import '../../data/services/upload_service.dart';
import '../../data/models/video_model.dart';
import '../widgets/video_card.dart';
import 'player_screen.dart';
import 'about_screen.dart'; // ✅ NOUVEL IMPORT
class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final YouTubeService _youtubeService = YouTubeService();
  final UploadService _uploadService = UploadService();
  final TextEditingController _searchController = TextEditingController();
  
  List<VideoModel> _videos = [];
  bool _isLoading = false;
  bool _isUploading = false;
  String _selectedLang = 'fr';
  String _selectedVoice = 'auto';

  final Color ytBlack = const Color(0xFF0F0F0F);
  final Color ytRed = const Color(0xFFFF0000);
  final Color ytSurface = const Color(0xFF272727);

  final List<Map<String, String>> _languages = [
    {'code': 'fr', 'name': 'Français', 'flag': '🇫🇷'},
    {'code': 'wo', 'name': 'Wolof', 'flag': '🇸🇳'},
    {'code': 'en', 'name': 'English', 'flag': '🇬🇧'},
    {'code': 'ar', 'name': 'العربية', 'flag': '🇸🇦'},
    {'code': 'es', 'name': 'Español', 'flag': '🇪🇸'},
    {'code': 'de', 'name': 'Deutsch', 'flag': '🇩🇪'},
    {'code': 'it', 'name': 'Italiano', 'flag': '🇮🇹'},
    {'code': 'pt', 'name': 'Português', 'flag': '🇵🇹'},
    {'code': 'ru', 'name': 'Русский', 'flag': '🇷🇺'},
    {'code': 'zh', 'name': '中文', 'flag': '🇨🇳'},
    {'code': 'ja', 'name': '日本語', 'flag': '🇯🇵'},
  ];
  
  final List<Map<String, String>> _voices = [
    {'code': 'auto', 'name': 'Automatique', 'icon': '🤖'},
    {'code': 'male', 'name': 'Voix Homme', 'icon': '👨'},
    {'code': 'female', 'name': 'Voix Femme', 'icon': '👩'},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ytBlack,
      appBar: AppBar(
        backgroundColor: ytBlack,
        elevation: 0,
        title: Row(
          children: [
            Icon(Icons.translate, color: ytRed, size: 28),
            const SizedBox(width: 10),
            const Text(
              'VoxTube', 
              style: TextStyle(
                color: Colors.white, 
                fontWeight: FontWeight.bold, 
                letterSpacing: -1
              ),
            ),
          ],
        ),
      // ✅ AJOUT DE L'ACTION BOUTON (À PROPOS)
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline, color: Colors.white),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AboutScreen()),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Barre de recherche YouTube
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Container(
              decoration: BoxDecoration(
                color: ytSurface,
                borderRadius: BorderRadius.circular(25),
              ),
              child: TextField(
                controller: _searchController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Rechercher sur YouTube...',
                  hintStyle: TextStyle(color: Colors.grey[500]),
                  prefixIcon: Icon(Icons.search, color: Colors.grey[400]),
                  suffixIcon: IconButton(
                    icon: Icon(Icons.send, color: ytRed),
                    onPressed: _searchVideos,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onSubmitted: (_) => _searchVideos(),
              ),
            ),
          ),

          // ✅ BOUTON UPLOAD
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: InkWell(
              onTap: _isUploading ? null : _pickAndUploadFile,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: _isUploading 
                      ? [Colors.grey[800]!, Colors.grey[700]!]
                      : [ytRed, const Color(0xFFCC0000)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: ytRed.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_isUploading)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    else
                      const Icon(Icons.upload_file, color: Colors.white),
                    const SizedBox(width: 10),
                    Text(
                      _isUploading 
                        ? 'Upload en cours...' 
                        : '📤 Uploader Vidéo/Audio (MP4, MP3)',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Sélecteurs langue/voix
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: _buildActionButton(
                    label: _languages.firstWhere((l) => l['code'] == _selectedLang)['name']!,
                    icon: Icons.language,
                    onTap: _showLanguagePicker,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildActionButton(
                    label: _voices.firstWhere((v) => v['code'] == _selectedVoice)['name']!,
                    icon: Icons.record_voice_over,
                    onTap: _showVoicePicker,
                  ),
                ),
              ],
            ),
          ),

          const Divider(color: Colors.white10, thickness: 1),

          // Liste des vidéos
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator(color: ytRed))
                : _videos.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: _videos.length,
                        itemBuilder: (context, index) => VideoCard(
                          video: _videos[index],
                          onTap: () => _playVideo(_videos[index]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required String label, 
    required IconData icon, 
    required VoidCallback onTap
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: ytSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: ytRed, size: 18),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label, 
                style: const TextStyle(
                  color: Colors.white, 
                  fontSize: 13, 
                  fontWeight: FontWeight.w500
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.slow_motion_video, size: 80, color: ytSurface),
          const SizedBox(height: 16),
          Text(
            '🔍 Recherchez une vidéo',
            style: TextStyle(color: Colors.grey[600], fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            'ou',
            style: TextStyle(color: Colors.grey[700], fontSize: 14),
          ),
          const SizedBox(height: 8),
          Text(
            '📤 Uploadez votre fichier',
            style: TextStyle(color: Colors.grey[600], fontSize: 16),
          ),
        ],
      ),
    );
  }

  // ✅ MÉTHODE UPLOAD
  Future<void> _pickAndUploadFile() async {
    try {
      // 1. Sélectionner fichier
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp4', 'mp3', 'mov', 'avi', 'mkv', 'wav', 'm4a'],
      );
      
      if (result == null) {
        print('❌ Aucun fichier sélectionné');
        return;
      }
      
      final file = File(result.files.single.path!);
      final fileName = result.files.single.name;
      final fileSize = result.files.single.size;
      
      print('📁 Fichier: $fileName (${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB)');
      
      // Vérifier taille (max 500MB)
      if (fileSize > 500 * 1024 * 1024) {
        _showError('Fichier trop volumineux (max 500 MB)');
        return;
      }
      
      setState(() => _isUploading = true);
      
      // 2. Upload
      final uploadResult = await _uploadService.uploadFile(file);
      
      setState(() => _isUploading = false);
      
      if (uploadResult['success'] == true) {
        // 3. Aller au PlayerScreen
        _playUploadedFile(fileName);
      } else {
        _showError(uploadResult['error'] ?? 'Erreur upload');
      }
      
    } catch (e) {
      setState(() => _isUploading = false);
      _showError('Erreur: $e');
    }
  }

  void _playUploadedFile(String filename) {
    final video = VideoModel(
      id: 'uploaded_${DateTime.now().millisecondsSinceEpoch}',
      title: filename,
      thumbnail: '',
      url: 'uploaded://$filename',
      duration: '',
      channelTitle: 'Local File',  // ✅ AJOUTER CETTE LIGNE

    );
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PlayerScreen(
          video: video,
          targetLang: _selectedLang,
          voiceType: _selectedVoice,
        ),
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red[700],
      ),
    );
  }

  void _showLanguagePicker() {
    showModalBottomSheet(
      backgroundColor: ytSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))
      ),
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: ListView(
          children: _languages.map((lang) => ListTile(
            leading: Text(lang['flag']!, style: const TextStyle(fontSize: 24)),
            title: Text(lang['name']!, style: const TextStyle(color: Colors.white)),
            onTap: () {
              setState(() => _selectedLang = lang['code']!);
              Navigator.pop(context);
            },
          )).toList(),
        ),
      ),
    );
  }

  void _showVoicePicker() {
    showModalBottomSheet(
      backgroundColor: ytSurface,
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: _voices.map((v) => ListTile(
          leading: Text(v['icon']!, style: const TextStyle(fontSize: 24)),
          title: Text(v['name']!, style: const TextStyle(color: Colors.white)),
          onTap: () {
            setState(() => _selectedVoice = v['code']!);
            Navigator.pop(context);
          },
        )).toList(),
      ),
    );
  }

  Future<void> _searchVideos() async {
    if (_searchController.text.trim().isEmpty) return;
    
    setState(() => _isLoading = true);
    
    try {
      final videos = await _youtubeService.searchVideos(_searchController.text.trim());
      setState(() {
        _videos = videos;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Erreur recherche: $e');
    }
  }

  void _playVideo(VideoModel video) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PlayerScreen(
          video: video,
          targetLang: _selectedLang,
          voiceType: _selectedVoice,
        ),
      ),
    );
  }
}