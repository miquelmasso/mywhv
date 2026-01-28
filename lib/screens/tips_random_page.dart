import 'dart:math';

import 'package:flutter/material.dart';

class TipsRandomPage extends StatefulWidget {
  const TipsRandomPage({super.key});

  @override
  State<TipsRandomPage> createState() => _TipsRandomPageState();
}

class _TipsRandomPageState extends State<TipsRandomPage> {
  final List<String> _tips = const [
    'Austràlia té més cangurs que persones; en moltes zones rurals són part del dia a dia.',
    'Els semàfors poden tardar molt en zones petites: la gent està acostumada a esperar.',
    'És habitual fer barbacoes públiques gratis als parcs i platges (BBQ elèctrics).',
    'En molts llocs no es paga mensualment: lloguer i salari solen ser setmanals.',
    'Els australians fan servir molt les abreviacions: arvo (tarda), brekkie (esmorzar), servo (benzina).',
    'El sol és molt fort: et pots cremar en 15 minuts fins i tot amb núvols.',
    'Els animals salvatges no són una atracció: si veus un cangur a la carretera, redueix velocitat.',
    'En pobles petits, tothom et saluda encara que no et conegui.',
    'Els pubs rurals solen ser el centre social del poble.',
    'És normal anar descalç en supermercats o gasolineres en zones costaneres.',
    'Les distàncies són enormes: “a prop” pot voler dir 3 hores en cotxe.',
    'Moltes feines no es troben online sinó preguntant directament al lloc.',
    'Els hostels sovint funcionen com a borsa de treball informal.',
    'L’aigua de l’aixeta és potable gairebé a tot el país.',
    'Els animals poden aparèixer a carreteres de nit; conduir de fosca és arriscat.',
    'La majoria de pagaments es fan amb targeta o mòbil, fins i tot imports molt petits.',
    'Els australians valoren més l’actitud que l’experiència en moltes feines.',
    'El “fair go” (joc just) és un valor cultural molt important.',
    'Els dies festius (public holidays) es cobren molt més.',
    'Moltes cases compartides es troben només via Facebook.',
    'En zones remotes, la cobertura mòbil pot desaparèixer completament.',
    'Els cafès tanquen d’hora; a partir de les 15–16h pot costar trobar-ne oberts.',
    'És normal canviar sovint de ciutat i feina; no està mal vist.',
    'Molts backpackers acaben treballant en feines que mai s’haurien imaginat abans de venir.',
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
      appBar: null,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Sabies que...',
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
