// lib/presentation/screens/home_screen.dart
import 'package:flutter/material.dart';
import '../../data/services/youtube_service.dart';
import '../../data/models/video_model.dart';
import '../widgets/video_card.dart';
import '../widgets/language_selector.dart';
import '../widgets/voice_selector.dart';
import 'player_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final YouTubeService _youtubeService = YouTubeService();
  final TextEditingController _searchController = TextEditingController();
  
  List<VideoModel> _videos = [];
  bool _isLoading = false;
  String _selectedLang = 'fr';
  String _selectedVoice = 'auto';
  
  // ✅ Liste exhaustive synchronisée avec le backend NLLB/Edge-TTS
  final List<Map<String, String>> _languages = [
    {'code': 'fr', 'name': 'Français', 'flag': '🇫🇷'},
    {'code': 'en', 'name': 'English', 'flag': '🇬🇧'},
    {'code': 'ar', 'name': 'العربية', 'flag': '🇸🇦'},
    {'code': 'es', 'name': 'Español', 'flag': '🇪🇸'},
    {'code': 'de', 'name': 'Deutsch', 'flag': '🇩🇪'},
    {'code': 'it', 'name': 'Italiano', 'flag': '🇮🇹'},
    {'code': 'pt', 'name': 'Português', 'flag': '🇵🇹'},
    {'code': 'ru', 'name': 'Русский', 'flag': '🇷🇺'},
    {'code': 'tr', 'name': 'Türkçe', 'flag': '🇹🇷'},
    {'code': 'zh', 'name': '中文', 'flag': '🇨🇳'},
    {'code': 'ja', 'name': '日本語', 'flag': '🇯🇵'},
    {'code': 'ko', 'name': '한국어', 'flag': '🇰🇷'},
    {'code': 'hi', 'name': 'हिन्दी', 'flag': '🇮🇳'},
    {'code': 'wo', 'name': 'Wolof', 'flag': '🇸🇳'},
    {'code': 'sw', 'name': 'Swahili', 'flag': '🇰🇪'},
  ];
  
  final List<Map<String, String>> _voices = [
    {'code': 'auto', 'name': 'Auto', 'icon': '🤖'},
    {'code': 'male', 'name': 'Homme', 'icon': '👨'},
    {'code': 'female', 'name': 'Femme', 'icon': '👩'},
  ];

  // ... (Le reste des méthodes _searchVideos, _playVideo, dispose reste identique)

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Column(
          children: [
            // Header avec gradient
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    const Text(
                      '🌍 Video Translator',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),
                    
                    // Barre de recherche
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(15),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 10,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Rechercher une vidéo YouTube...',
                          prefixIcon: const Icon(Icons.search, color: Color(0xFF667EEA)),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.send, color: Color(0xFF667EEA)),
                            onPressed: _searchVideos,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                        ),
                        onSubmitted: (_) => _searchVideos(),
                      ),
                    ),
                    const SizedBox(height: 15),
                    
                    // Sélecteurs langue et voix
                    Row(
                      children: [
                        Expanded(
                          child: LanguageSelector(
                            languages: _languages,
                            selectedLang: _selectedLang,
                            onChanged: (lang) => setState(() => _selectedLang = lang!),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: VoiceSelector(
                            voices: _voices,
                            selectedVoice: _selectedVoice,
                            onChanged: (voice) => setState(() => _selectedVoice = voice!),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            
            // Liste des résultats
            Expanded(
              child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _videos.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.video_library_outlined, size: 100, color: Colors.grey[300]),
                          const SizedBox(height: 20),
                          Text(
                            'Recherchez une vidéo pour commencer',
                            style: TextStyle(color: Colors.grey[600], fontSize: 16),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(15),
                      itemCount: _videos.length,
                      itemBuilder: (context, index) {
                        return VideoCard(
                          video: _videos[index],
                          onTap: () => _playVideo(_videos[index]),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Mêmes méthodes qu'avant ---
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}