// lib/presentation/screens/home_screen.dart

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../../data/services/youtube_service.dart';
import '../../data/services/upload_service.dart';
import '../../data/models/video_model.dart';
import '../../data/services/ad_manager.dart';
import '../widgets/video_card.dart';
import '../widgets/ad_banner_widget.dart';
import 'player_screen.dart';
import 'about_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final YouTubeService _youtubeService = YouTubeService();
  final UploadService _uploadService = UploadService();
  final AdManager _adManager = AdManager();
  final TextEditingController _searchController = TextEditingController();
  
  List<VideoModel> _videos = [];
  bool _isLoading = false;
  bool _isUploading = false;
  String _selectedLang = 'fr';
  String _selectedVoice = 'auto';
  
  int _freeUploadsRemaining = 0; // ✅ 3 uploads gratuits

  final Color ytBlack = const Color(0xFF0F0F0F);
  final Color ytRed = const Color(0xFFFF0000);
  final Color ytSurface = const Color(0xFF272727);

  // ✅ TOUTES LES LANGUES EDGE TTS
  final List<Map<String, String>> _languages = [
    {'code': 'af', 'name': 'Afrikaans', 'flag': '🇿🇦'},
    {'code': 'am', 'name': 'አማርኛ', 'flag': '🇪🇹'},
    {'code': 'ar', 'name': 'العربية', 'flag': '🇸🇦'},
    {'code': 'az', 'name': 'Azərbaycan', 'flag': '🇦🇿'},
    {'code': 'bg', 'name': 'Български', 'flag': '🇧🇬'},
    {'code': 'bn', 'name': 'বাংলা', 'flag': '🇧🇩'},
    {'code': 'bs', 'name': 'Bosanski', 'flag': '🇧🇦'},
    {'code': 'ca', 'name': 'Català', 'flag': '🇪🇸'},
    {'code': 'cs', 'name': 'Čeština', 'flag': '🇨🇿'},
    {'code': 'cy', 'name': 'Cymraeg', 'flag': '🏴󠁧󠁢󠁷󠁬󠁳󠁿'},
    {'code': 'da', 'name': 'Dansk', 'flag': '🇩🇰'},
    {'code': 'de', 'name': 'Deutsch', 'flag': '🇩🇪'},
    {'code': 'el', 'name': 'Ελληνικά', 'flag': '🇬🇷'},
    {'code': 'en', 'name': 'English', 'flag': '🇬🇧'},
    {'code': 'es', 'name': 'Español', 'flag': '🇪🇸'},
    {'code': 'et', 'name': 'Eesti', 'flag': '🇪🇪'},
    {'code': 'eu', 'name': 'Euskara', 'flag': '🇪🇸'},
    {'code': 'fa', 'name': 'فارسی', 'flag': '🇮🇷'},
    {'code': 'fi', 'name': 'Suomi', 'flag': '🇫🇮'},
    {'code': 'fil', 'name': 'Filipino', 'flag': '🇵🇭'},
    {'code': 'fr', 'name': 'Français', 'flag': '🇫🇷'},
    {'code': 'ga', 'name': 'Gaeilge', 'flag': '🇮🇪'},
    {'code': 'gl', 'name': 'Galego', 'flag': '🇪🇸'},
    {'code': 'gu', 'name': 'ગુજરાતી', 'flag': '🇮🇳'},
    {'code': 'he', 'name': 'עברית', 'flag': '🇮🇱'},
    {'code': 'hi', 'name': 'हिन्दी', 'flag': '🇮🇳'},
    {'code': 'hr', 'name': 'Hrvatski', 'flag': '🇭🇷'},
    {'code': 'hu', 'name': 'Magyar', 'flag': '🇭🇺'},
    {'code': 'hy', 'name': 'Հայերեն', 'flag': '🇦🇲'},
    {'code': 'id', 'name': 'Indonesia', 'flag': '🇮🇩'},
    {'code': 'is', 'name': 'Íslenska', 'flag': '🇮🇸'},
    {'code': 'it', 'name': 'Italiano', 'flag': '🇮🇹'},
    {'code': 'ja', 'name': '日本語', 'flag': '🇯🇵'},
    {'code': 'jv', 'name': 'Basa Jawa', 'flag': '🇮🇩'},
    {'code': 'ka', 'name': 'ქართული', 'flag': '🇬🇪'},
    {'code': 'kk', 'name': 'Қазақ', 'flag': '🇰🇿'},
    {'code': 'km', 'name': 'ខ្មែរ', 'flag': '🇰🇭'},
    {'code': 'kn', 'name': 'ಕನ್ನಡ', 'flag': '🇮🇳'},
    {'code': 'ko', 'name': '한국어', 'flag': '🇰🇷'},
    {'code': 'lo', 'name': 'ລາວ', 'flag': '🇱🇦'},
    {'code': 'lt', 'name': 'Lietuvių', 'flag': '🇱🇹'},
    {'code': 'lv', 'name': 'Latviešu', 'flag': '🇱🇻'},
    {'code': 'mk', 'name': 'Македонски', 'flag': '🇲🇰'},
    {'code': 'ml', 'name': 'മലയാളം', 'flag': '🇮🇳'},
    {'code': 'mn', 'name': 'Монгол', 'flag': '🇲🇳'},
    {'code': 'mr', 'name': 'मराठी', 'flag': '🇮🇳'},
    {'code': 'ms', 'name': 'Melayu', 'flag': '🇲🇾'},
    {'code': 'mt', 'name': 'Malti', 'flag': '🇲🇹'},
    {'code': 'my', 'name': 'မြန်မာ', 'flag': '🇲🇲'},
    {'code': 'nb', 'name': 'Norsk', 'flag': '🇳🇴'},
    {'code': 'ne', 'name': 'नेपाली', 'flag': '🇳🇵'},
    {'code': 'nl', 'name': 'Nederlands', 'flag': '🇳🇱'},
    {'code': 'pl', 'name': 'Polski', 'flag': '🇵🇱'},
    {'code': 'ps', 'name': 'پښتو', 'flag': '🇦🇫'},
    {'code': 'pt', 'name': 'Português', 'flag': '🇵🇹'},
    {'code': 'ro', 'name': 'Română', 'flag': '🇷🇴'},
    {'code': 'ru', 'name': 'Русский', 'flag': '🇷🇺'},
    {'code': 'si', 'name': 'සිංහල', 'flag': '🇱🇰'},
    {'code': 'sk', 'name': 'Slovenčina', 'flag': '🇸🇰'},
    {'code': 'sl', 'name': 'Slovenščina', 'flag': '🇸🇮'},
    {'code': 'so', 'name': 'Soomaali', 'flag': '🇸🇴'},
    {'code': 'sq', 'name': 'Shqip', 'flag': '🇦🇱'},
    {'code': 'sr', 'name': 'Српски', 'flag': '🇷🇸'},
    {'code': 'su', 'name': 'Sunda', 'flag': '🇮🇩'},
    {'code': 'sv', 'name': 'Svenska', 'flag': '🇸🇪'},
    {'code': 'sw', 'name': 'Kiswahili', 'flag': '🇰🇪'},
    {'code': 'ta', 'name': 'தமிழ்', 'flag': '🇮🇳'},
    {'code': 'te', 'name': 'తెలుగు', 'flag': '🇮🇳'},
    {'code': 'th', 'name': 'ไทย', 'flag': '🇹🇭'},
    {'code': 'tr', 'name': 'Türkçe', 'flag': '🇹🇷'},
    {'code': 'uk', 'name': 'Українська', 'flag': '🇺🇦'},
    {'code': 'ur', 'name': 'اردو', 'flag': '🇵🇰'},
    {'code': 'uz', 'name': 'Oʻzbek', 'flag': '🇺🇿'},
    {'code': 'vi', 'name': 'Tiếng Việt', 'flag': '🇻🇳'},
    {'code': 'wo', 'name': 'Wolof', 'flag': '🇸🇳'},
    {'code': 'zh', 'name': '中文', 'flag': '🇨🇳'},
    {'code': 'zu', 'name': 'isiZulu', 'flag': '🇿🇦'},
  ];
  
  final List<Map<String, String>> _voices = [
    {'code': 'auto', 'name': 'Automatique', 'icon': '🤖'},
    {'code': 'male', 'name': 'Voix Homme', 'icon': '👨'},
    {'code': 'female', 'name': 'Voix Femme', 'icon': '👩'},
  ];

  @override
  void initState() {
    super.initState();
    _adManager.loadRewardedAd();
  }

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
          // Barre de recherche
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

          // ✅ BOUTON UPLOAD avec compteur
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
                  boxShadow: _isUploading ? [] : [
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
                      const Icon(Icons.upload_file, color: Colors.white, size: 24),
                    
                    const SizedBox(width: 10),
                    
                    Text(
                      _isUploading 
                        ? 'Upload en cours...' 
                        : '📤 Uploader Vidéo/Audio',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    
                    // ✅ COMPTEUR UPLOADS GRATUITS
                    if (!_isUploading && _freeUploadsRemaining > 0)
                      Container(
                        margin: const EdgeInsets.only(left: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '$_freeUploadsRemaining',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    
                    // ✅ ICÔNE REWARDED SI ÉPUISÉ
                    if (!_isUploading && _freeUploadsRemaining <= 0)
                      Container(
                        margin: const EdgeInsets.only(left: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.orange,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: const [
                            Icon(Icons.card_giftcard, color: Colors.white, size: 14),
                            SizedBox(width: 4),
                            Text(
                              'Pub',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // Sélecteurs langue/voix avec drapeaux
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: _buildActionButton(
                    label: _languages.firstWhere((l) => l['code'] == _selectedLang)['name']!,
                    emoji: _languages.firstWhere((l) => l['code'] == _selectedLang)['flag']!, // ✅ DRAPEAU
                    onTap: _showLanguagePicker,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildActionButton(
                    label: _voices.firstWhere((v) => v['code'] == _selectedVoice)['name']!,
                    emoji: _voices.firstWhere((v) => v['code'] == _selectedVoice)['icon']!,
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
          
          // ✅ BANNIÈRE FIXE EN BAS
          const AdBannerWidget(),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required String label, 
    required String emoji, 
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
            Text(emoji, style: const TextStyle(fontSize: 20)), // ✅ EMOJI au lieu d'icon
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

  // ✅ MÉTHODE UPLOAD AVEC REWARDED
  Future<void> _pickAndUploadFile() async {
    // Vérifier uploads gratuits
    if (_freeUploadsRemaining <= 0) {
      _showUploadRewardedDialog();
      return;
    }
    
    await _performUpload();
  }

  // ✅ DIALOG REWARDED
  Future<void> _showUploadRewardedDialog() async {
    final shouldWatch = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.upload_file, color: ytRed, size: 30),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Upload Vidéo',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.video_library, color: ytRed, size: 60),
            const SizedBox(height: 16),
            const Text(
              'Uploads gratuits épuisés',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Regarde une pub pour débloquer 3 uploads supplémentaires !',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.play_circle_outline),
            label: const Text('🎁 Regarder Pub'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );

    if (shouldWatch == true) {
      await _watchRewardedForUpload();
    }
  }

  // ✅ AFFICHER REWARDED
  Future<void> _watchRewardedForUpload() async {
    if (!_adManager.isRewardedReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⏳ Chargement pub...')),
      );
      await _adManager.loadRewardedAd();
      
      if (!_adManager.isRewardedReady) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Pub indisponible. Réessaye plus tard.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    final rewarded = await _adManager.showRewardedAd();

    if (rewarded) {
      setState(() {
        _freeUploadsRemaining += 1;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🎉 +3 uploads débloqués ! Total: $_freeUploadsRemaining'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );

      await _performUpload();
    }
  }

  // ✅ UPLOAD EFFECTIF
  Future<void> _performUpload() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp4', 'mp3', 'mov', 'avi', 'mkv', 'wav', 'm4a'],
      );
      
      if (result == null) return;
      
      final file = File(result.files.single.path!);
      final fileName = result.files.single.name;
      final fileSize = result.files.single.size;
      
      print('📁 Fichier: $fileName (${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB)');
      
      if (fileSize > 500 * 1024 * 1024) {
        _showError('Fichier trop volumineux (max 500 MB)');
        return;
      }
      
      setState(() => _isUploading = true);
      
      final uploadResult = await _uploadService.uploadFile(file);
      
      setState(() => _isUploading = false);
      
      if (uploadResult['success'] == true) {
        // ✅ DÉCRÉMENTER
        setState(() {
          if (_freeUploadsRemaining > 0) {
            _freeUploadsRemaining--;
          }
        });
        
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
      channelTitle: 'Local File',
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
        height: MediaQuery.of(context).size.height * 0.7, // ✅ Hauteur fixe pour scroll
        child: Column(
          children: [
            Text(
              'Choisir la langue',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: _languages.length,
                itemBuilder: (context, index) {
                  final lang = _languages[index];
                  return ListTile(
                    leading: Text(lang['flag']!, style: const TextStyle(fontSize: 24)),
                    title: Text(lang['name']!, style: const TextStyle(color: Colors.white)),
                    trailing: _selectedLang == lang['code'] 
                      ? Icon(Icons.check, color: ytRed) 
                      : null,
                    onTap: () {
                      setState(() => _selectedLang = lang['code']!);
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showVoicePicker() {
    showModalBottomSheet(
      backgroundColor: ytSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))
      ),
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Type de voix',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ..._voices.map((v) => ListTile(
              leading: Text(v['icon']!, style: const TextStyle(fontSize: 24)),
              title: Text(v['name']!, style: const TextStyle(color: Colors.white)),
              trailing: _selectedVoice == v['code'] 
                ? Icon(Icons.check, color: ytRed) 
                : null,
              onTap: () {
                setState(() => _selectedVoice = v['code']!);
                Navigator.pop(context);
              },
            )).toList(),
          ],
        ),
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
