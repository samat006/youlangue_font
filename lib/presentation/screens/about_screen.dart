// lib/presentation/screens/about_screen.dart

import 'package:flutter/material.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({Key? key}) : super(key: key);

  final Color ytBlack = const Color(0xFF0F0F0F);
  final Color ytRed = const Color(0xFFFF0000);
  final Color ytSurface = const Color(0xFF272727);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ytBlack,
      appBar: AppBar(
        backgroundColor: ytBlack,
        elevation: 0,
        title: const Text(
          'À propos de VoxTube',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // 🔥 LOGO + TITRE
            Center(
              child: Column(
                children: [
                  Image.asset(
                    'assets/images/voxtube_logo.png',
                    height: 80,
                  ),
                  const SizedBox(height: 15),
                  const Text(
                    'VoxTube',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                    ),
                  ),
                  Text(
                    'Version 1.0 (Alpha)',
                    style: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),

            // 🎯 MISSION
            _buildSectionTitle(' Notre Mission'),
            _buildInfoCard(
              'VoxTube est une application innovante de traduction et de redoublage vocal des vidéos. '
              'Notre objectif est de rendre le contenu vidéo accessible à tous, en supprimant les barrières linguistiques, '
              'notamment pour les langues africaines et internationales.',
              Icons.public,
            ),
            const SizedBox(height: 20),

            // 🤝 COLLAB / INVEST
            _buildSectionTitle('🤝 Investissement & Collaboration'),
            _buildInfoCard(
              'VoxTube est ouvert aux opportunités de collaboration, de partenariat et d’investissement '
              'dans le domaine des technologies, de l’intelligence artificielle et des plateformes numériques.',
              Icons.handshake,
            ),
            const SizedBox(height: 20),

            // 👨‍💻 DÉVELOPPEUR
            _buildSectionTitle('👨‍💻 Développement'),
            _buildDeveloperInfo(),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: TextStyle(
          color: ytRed,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildInfoCard(String content, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: ytSurface,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white70, size: 24),
          const SizedBox(width: 15),
          Expanded(
            child: Text(
              content,
              style: const TextStyle(color: Colors.white70, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeveloperInfo() {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: ytSurface,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          _DetailRow(icon: Icons.business, title: 'Développé par', value: 'Touba7G'),
          SizedBox(height: 10),
          _DetailRow(icon: Icons.phone, title: 'Téléphone', value: '🇫🇷 +33652420028 ou 🇸🇳+221 77 840 03 22'),
          
          _DetailRow(icon: Icons.email, title: 'Email', value: 'asamathseck@gmail.com'),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;

  const _DetailRow({
    required this.icon,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: const Color(0xFFFF0000), size: 18),
        const SizedBox(width: 10),
        SizedBox(
          width: 90,
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(color: Colors.white70),
          ),
        ),
      ],
    );
  }
}
