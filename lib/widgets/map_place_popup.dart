import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

const double kMapPopupDockOffset = 104;
const double kMapRestaurantPopupBottomOffset = kMapPopupDockOffset + 18;

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
    this.bottomOffset = 0,
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
  final double bottomOffset;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 14,
      right: 14,
      bottom: bottomOffset,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF8EF),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.14),
              blurRadius: 24,
              spreadRadius: -4,
              offset: const Offset(0, 10),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              spreadRadius: -2,
              offset: const Offset(0, -2),
            ),
          ],
          borderRadius: BorderRadius.circular(26),
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
                      color: Color(0xFF2E2E2E),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Stack(
                  alignment: Alignment.center,
                  children: [
                    _SmallCircleIconButton(
                      icon: Icons.person,
                      iconColor: Colors.grey,
                      tooltip: 'I worked here',
                      onPressed: onWorkedHere,
                    ),
                    if (workedCount > 0)
                      Positioned(
                        right: 1,
                        top: 1,
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
                    icon: const Icon(
                      Icons.email_outlined,
                      color: Colors.redAccent,
                    ),
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
                    icon: const FaIcon(
                      FontAwesomeIcons.instagram,
                      color: Colors.purple,
                    ),
                    tooltip: 'open instagram',
                    onPressed: onInstagram,
                  ),
                const Spacer(),
                _SmallCircleIconButton(
                  icon: isFavorite ? Icons.favorite : Icons.favorite_border,
                  iconColor: isFavorite ? Colors.red : Colors.grey,
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

class _SmallCircleIconButton extends StatelessWidget {
  const _SmallCircleIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.iconColor = Colors.grey,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.grey.shade100,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: 38,
          height: 38,
          child: Tooltip(
            message: tooltip,
            child: Icon(icon, color: iconColor, size: 23),
          ),
        ),
      ),
    );
  }
}

class MapHarvestPopup extends StatefulWidget {
  const MapHarvestPopup({
    super.key,
    required this.name,
    required this.postcode,
    required this.state,
    this.description,
    this.activeMonths = const [],
    this.crops = const [],
    this.cropsByMonth = const {},
    required this.onClose,
    this.bottomOffset = 0,
  });

  final String name;
  final String postcode;
  final String state;
  final String? description;
  final List<int> activeMonths;
  final List<String> crops;
  final Map<int, List<String>> cropsByMonth;
  final VoidCallback onClose;
  final double bottomOffset;

  @override
  State<MapHarvestPopup> createState() => _MapHarvestPopupState();
}

class _MapHarvestPopupState extends State<MapHarvestPopup> {
  late int _selectedMonth;

  static const _monthLabels = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  @override
  void initState() {
    super.initState();
    _selectedMonth = DateTime.now().month;
  }

  @override
  void didUpdateWidget(covariant MapHarvestPopup oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.name != widget.name ||
        oldWidget.postcode != widget.postcode ||
        oldWidget.state != widget.state) {
      _selectedMonth = DateTime.now().month;
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentMonth = DateTime.now().month;
    final hasSeasonData =
        widget.activeMonths.isNotEmpty || widget.crops.isNotEmpty;
    final isActiveNow = widget.activeMonths.contains(currentMonth);
    final selectedCrops =
        widget.cropsByMonth[_selectedMonth] ?? const <String>[];
    final isCurrentMonthSelected = _selectedMonth == currentMonth;
    final selectedMonthLabel = _monthLabels[_selectedMonth - 1];
    final statusColor = isActiveNow
        ? const Color(0xFF238A57)
        : const Color(0xFF6B7280);

    return Positioned(
      left: 0,
      right: 0,
      bottom: widget.bottomOffset,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        constraints: const BoxConstraints(maxHeight: 410),
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5EC),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.agriculture,
                      color: Color(0xFF238A57),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          smartTruncate(widget.name, 50),
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1F2937),
                          ),
                        ),
                        if (hasSeasonData) ...[
                          const SizedBox(height: 6),
                          _HarvestInfoChip(
                            icon: isActiveNow
                                ? Icons.eco
                                : Icons.calendar_month,
                            label: isActiveNow
                                ? 'Active this month'
                                : 'Out of season now',
                            color: statusColor,
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: widget.onClose,
                    tooltip: 'Close',
                  ),
                ],
              ),
              if (hasSeasonData) ...[
                const SizedBox(height: 18),
                const _HarvestSectionTitle(
                  icon: Icons.calendar_month,
                  title: 'Harvest season',
                ),
                const SizedBox(height: 9),
                Wrap(
                  spacing: 6,
                  runSpacing: 7,
                  children: List.generate(12, (index) {
                    final month = index + 1;
                    final isActive = widget.activeMonths.contains(month);
                    final isCurrent = month == currentMonth;
                    final isSelected = month == _selectedMonth;
                    return InkWell(
                      onTap: () => setState(() => _selectedMonth = month),
                      borderRadius: BorderRadius.circular(10),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        width: 42,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF238A57)
                              : isActive
                              ? const Color(0xFFDDF3E5)
                              : const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(10),
                          border: isCurrent && !isSelected
                              ? Border.all(color: statusColor, width: 2)
                              : null,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          _monthLabels[index],
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isActive || isSelected
                                ? FontWeight.w800
                                : FontWeight.w500,
                            color: isSelected
                                ? Colors.white
                                : isActive
                                ? const Color(0xFF176B42)
                                : const Color(0xFF9CA3AF),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ],
              if (hasSeasonData) ...[
                const SizedBox(height: 18),
                _HarvestSectionTitle(
                  icon: Icons.wb_sunny_outlined,
                  title: isCurrentMonthSelected
                      ? 'What is harvested now'
                      : 'What is harvested in $selectedMonthLabel',
                ),
                const SizedBox(height: 9),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: selectedCrops.isNotEmpty
                      ? _HarvestCropWrap(
                          key: ValueKey(_selectedMonth),
                          crops: selectedCrops,
                          highlighted: isCurrentMonthSelected,
                        )
                      : Container(
                          key: ValueKey('empty-$_selectedMonth'),
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3F4F6),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'No harvest is recorded for $selectedMonthLabel.',
                            style: const TextStyle(
                              color: Color(0xFF6B7280),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                ),
              ],
              if (!hasSeasonData && (widget.description ?? '').isNotEmpty) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F8FA),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    widget.description!,
                    style: const TextStyle(
                      color: Color(0xFF4B5563),
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _HarvestInfoChip extends StatelessWidget {
  const _HarvestInfoChip({
    required this.icon,
    required this.label,
    this.color = const Color(0xFF4B5563),
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _HarvestSectionTitle extends StatelessWidget {
  const _HarvestSectionTitle({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF238A57)),
        const SizedBox(width: 7),
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: Color(0xFF374151),
          ),
        ),
      ],
    );
  }
}

class _HarvestCropWrap extends StatelessWidget {
  const _HarvestCropWrap({
    super.key,
    required this.crops,
    this.highlighted = false,
  });

  final List<String> crops;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final visibleCrops = crops.take(8).toList(growable: false);
    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: [
        ...visibleCrops.map(
          (crop) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: highlighted
                  ? const Color(0xFFFFF3D6)
                  : const Color(0xFFEAF4EC),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              crop,
              style: TextStyle(
                color: highlighted
                    ? const Color(0xFF9A6700)
                    : const Color(0xFF26734D),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        if (crops.length > visibleCrops.length)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '+${crops.length - visibleCrops.length}',
              style: const TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    );
  }
}
