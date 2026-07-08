import 'package:flutter/material.dart';

import '../utils/app_i18n.dart';

class FilterButton extends StatefulWidget {
  /// Quan és `false`, només es mostren els restaurants amb dades de contacte.
  /// Quan és `true`, es mostren tots (incloent els sense dades).
  final ValueChanged<bool> onChanged;

  const FilterButton({super.key, required this.onChanged});

  @override
  State<FilterButton> createState() => _FilterButtonState();
}

class _FilterButtonState extends State<FilterButton> {
  bool _showAll = false; // 🔹 De base: només mostrar llocs amb dades útils

  void _toggleFilter(bool? value) {
    setState(() => _showAll = value ?? false);
    widget.onChanged(_showAll);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, String>>(
      future: AppI18n.load(),
      initialData: AppI18n.forCode('en'),
      builder: (context, snapshot) {
        final strings = snapshot.data ?? AppI18n.forCode('en');
        String t(String key) => AppI18n.t(strings, key);

        return PopupMenuButton<int>(
          icon: Icon(
            Icons.filter_list,
            color: _showAll ? Colors.blueAccent : Colors.black87,
          ),
          tooltip: t('map.filter.title'),
          itemBuilder: (context) => [
            PopupMenuItem<int>(
              value: 0,
              child: StatefulBuilder(
                builder: (context, setInnerState) {
                  return CheckboxListTile(
                    value: _showAll,
                    onChanged: (value) {
                      setInnerState(() => _showAll = value ?? false);
                      _toggleFilter(value);
                    },
                    title: Text(
                      t('map.filter.show_without_contact'),
                      style: const TextStyle(fontSize: 14),
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
