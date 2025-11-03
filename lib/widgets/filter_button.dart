import 'package:flutter/material.dart';

class FilterButton extends StatefulWidget {
  final bool showAll;
  final ValueChanged<bool> onChanged;

  const FilterButton({
    super.key,
    required this.showAll,
    required this.onChanged,
  });

  @override
  State<FilterButton> createState() => _FilterButtonState();
}

class _FilterButtonState extends State<FilterButton> {
  late bool _showAll;

  @override
  void initState() {
    super.initState();
    _showAll = widget.showAll;
  }

  void _toggleFilter(bool? value) {
    setState(() => _showAll = value ?? false);
    widget.onChanged(_showAll);
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      icon: const Icon(Icons.filter_list, color: Colors.black87),
      tooltip: 'Filtres',
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
                title: const Text(
                  'Mostrar restaurants sense web ni contacte',
                  style: TextStyle(fontSize: 14),
                ),
                controlAffinity: ListTileControlAffinity.leading,
              );
            },
          ),
        ),
      ],
    );
  }
}
