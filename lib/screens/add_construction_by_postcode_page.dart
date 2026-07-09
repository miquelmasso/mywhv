import 'package:flutter/material.dart';

class AddConstructionByPostcodePage extends StatefulWidget {
  const AddConstructionByPostcodePage({super.key});

  @override
  State<AddConstructionByPostcodePage> createState() =>
      _AddConstructionByPostcodePageState();
}

class _AddConstructionByPostcodePageState
    extends State<AddConstructionByPostcodePage> {
  final TextEditingController _postcodeController = TextEditingController(
    text: '4802',
  );
  String _result = '';
  bool _loading = false;

  @override
  void dispose() {
    _postcodeController.dispose();
    super.dispose();
  }

  Future<void> _checkPostcode() async {
    final input = _postcodeController.text.trim();
    if (input.isEmpty) {
      setState(() {
        _result = 'Enter a postcode.';
      });
      return;
    }

    final postcode = input.padLeft(4, '0');
    if (!RegExp(r'^\d{4}$').hasMatch(postcode)) {
      setState(() {
        _result = 'Enter a valid 4-digit postcode.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _result = '';
    });

    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;

    setState(() {
      _loading = false;
      _result =
          'Construction search is ready for postcode $postcode. The data source is not connected yet.';
    });
  }

  void _showNotConnectedSnack() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Construction import is prepared, but no data source is connected yet.',
        ),
        backgroundColor: Colors.blueGrey.shade800,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Construction management',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      backgroundColor: Colors.white,
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 10),
              const Text(
                'Search construction by postcode',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 25),
              TextField(
                controller: _postcodeController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Enter postcode',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.search),
                    onPressed: _checkPostcode,
                  ),
                ),
                onSubmitted: (_) => _checkPostcode(),
              ),
              const SizedBox(height: 20),
              if (_loading)
                const CircularProgressIndicator()
              else if (_result.isNotEmpty)
                Text(
                  _result,
                  style: TextStyle(
                    fontSize: 16,
                    color: _result.startsWith('Construction')
                        ? Colors.green.shade700
                        : Colors.orange.shade800,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              const SizedBox(height: 40),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF6F7FA),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFDDE2EA)),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Construction import',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'This mirrors the restaurant postcode search flow. The next step is connecting a construction data source.',
                      style: TextStyle(color: Colors.black54, height: 1.35),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 15,
                runSpacing: 15,
                alignment: WrapAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: _loading ? null : _showNotConnectedSnack,
                    icon: const Icon(Icons.construction),
                    label: const Text('Add construction places'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueGrey.shade700,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _loading ? null : _showNotConnectedSnack,
                    icon: const Icon(Icons.search_rounded),
                    label: const Text('Add all from postcode'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
