import 'dart:math';

import 'package:flutter/material.dart';

class TipsRandomPage extends StatefulWidget {
  const TipsRandomPage({super.key});

  @override
  State<TipsRandomPage> createState() => _TipsRandomPageState();
}

class _TipsRandomPageState extends State<TipsRandomPage> {
  final List<String> _tips = const [
    'Demana sempre el TFN (Tax File Number) en arribar per poder treballar legalment.',
    'Crea un compte bancari local (Commbank, Westpac, etc.) els primers dies per rebre nòmines.',
    'Compra una SIM local amb dades il·limitades per poder buscar feina i navegar fàcilment.',
    'A l’outback, porta sempre aigua extra i avisa algú del teu recorregut.',
    'Actualitza el CV al format australià: curt, directe i amb referències locals si en tens.',
    'Per feines de farm, pregunta pels drets: paga mínima, horaris i contracte ABN o TFN.',
    'Explora hostels i grups de Facebook/WhatsApp per trobar feines ràpidament.',
    'Si fas servir vehicle, revisa assegurança, revisió i Roadworthy abans de llargs trajectes.',
    'Evita estafes: mai paguis per avançat per una feina; valida l’empresa i ABN.',
    'Guarda un coixí d’estalvis per cobrir almenys 1 mes de despeses a l’arribada.',
    'Per renovar la visa, documenta correctament les hores de farm amb payslips i formularis.',
    'En feines d’hospitality, el RSA (Responsible Service of Alcohol) pot ser necessari per servir alcohol.',
  ];

  late String _currentTip;
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _currentTip = _tips[_random.nextInt(_tips.length)];
  }

  void _nextTip() {
    setState(() {
      _currentTip = _tips[_random.nextInt(_tips.length)];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tips'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Tip ràpid',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blueGrey.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blueGrey.withOpacity(0.1)),
              ),
              child: Text(
                _currentTip,
                style: const TextStyle(fontSize: 16, height: 1.4),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _nextTip,
              icon: const Icon(Icons.shuffle),
              label: const Text('Nou tip'),
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
