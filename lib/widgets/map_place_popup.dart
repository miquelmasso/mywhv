import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

String smartTruncate(String text, int maxChars) {
  if (text.length <= maxChars) return text;
  String truncated = text.substring(0, maxChars);
  final lastSpace = truncated.lastIndexOf(' ');
  if (lastSpace > 0) truncated = truncated.substring(0, lastSpace);
  truncated = truncated.replaceAll(RegExp(r'[\\s,\\.&@\\-_\\/]+$'), '');
  truncated = truncated.trim();
  if (!RegExp(r'[a-zA-Z0-9]$').hasMatch(truncated) && truncated.isNotEmpty) {
    truncated = truncated.replaceAll(RegExp(r'[^a-zA-Z0-9]+$'), '');
  }
  if (truncated.isEmpty) return '${text.substring(0, maxChars).trim()}…';
  return '$truncated…';
}

class MapRestaurantPopup extends StatelessWidget {
  const MapRestaurantPopup({
    super.key,
    required this.data,
    required this.workedCount,
    required this.isFavorite,
    required this.onClose,
    required this.onWorkedHere,
    required this.onCopyPhone,
    required this.onEmail,
    required this.onFacebook,
    required this.onCareers,
    required this.onInstagram,
    required this.onFavorite,
  });

  final Map<String, dynamic> data;
  final int workedCount;
  final bool isFavorite;
  final VoidCallback onClose;
  final VoidCallback onWorkedHere;
  final VoidCallback onCopyPhone;
  final VoidCallback onEmail;
  final VoidCallback onFacebook;
  final VoidCallback onCareers;
  final VoidCallback onInstagram;
  final VoidCallback onFavorite;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    smartTruncate(data['name'] ?? 'Sense nom', 50),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Stack(
                  alignment: Alignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.person, color: Colors.grey),
                      tooltip: 'I worked here',
                      onPressed: onWorkedHere,
                    ),
                    if (workedCount > 0)
                      Positioned(
                        right: 8,
                        top: 8,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '$workedCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if ((data['phone'] ?? '').toString().isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.phone, color: Colors.blueAccent),
                    tooltip: 'Copy phone',
                    onPressed: onCopyPhone,
                  ),
                if ((data['email'] ?? '').toString().isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.email_outlined, color: Colors.redAccent),
                    tooltip: 'Email options',
                    onPressed: onEmail,
                  ),
                if ((data['facebook_url'] ?? '').toString().isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.facebook, color: Colors.blue),
                    tooltip: 'Open Facebook',
                    onPressed: onFacebook,
                  ),
                if ((data['careers_page'] ?? '').toString().isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.work_outline, color: Colors.green),
                    tooltip: 'View job offers',
                    onPressed: onCareers,
                  ),
                if ((data['instagram_url'] ?? '').toString().isNotEmpty)
                  IconButton(
                    icon: const FaIcon(FontAwesomeIcons.instagram, color: Colors.purple),
                    tooltip: 'open instagram',
                    onPressed: onInstagram,
                  ),
                const Spacer(),
                IconButton(
                  icon: Icon(
                    isFavorite ? Icons.favorite : Icons.favorite_border,
                    color: isFavorite ? Colors.red : Colors.grey,
                    size: 28,
                  ),
                  tooltip: 'Preferit',
                  onPressed: onFavorite,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class MapHarvestPopup extends StatelessWidget {
  const MapHarvestPopup({
    super.key,
    required this.name,
    required this.postcode,
    required this.state,
    this.description,
    required this.onClose,
  });

  final String name;
  final String postcode;
  final String state;
  final String? description;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    smartTruncate(name, 50),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: onClose,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Postcode: $postcode • $state',
              style: const TextStyle(color: Colors.black54),
            ),
            if ((description ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                description!,
                style: const TextStyle(color: Colors.black87),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
