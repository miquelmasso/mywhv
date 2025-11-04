import 'package:flutter/material.dart';

class ConsejosPage extends StatelessWidget {
  const ConsejosPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Consejos para trabajar en Australia',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
        centerTitle: true,
      ),
      backgroundColor: Colors.white,
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              SizedBox(height: 10),
              Text(
                '🌏 Trabajar en Australia con una Work and Holiday Visa',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  height: 1.3,
                ),
              ),
              SizedBox(height: 16),
              Text(
                'Australia es un país lleno de oportunidades para quienes buscan '
                'viajar, aprender inglés y ganar experiencia laboral al mismo tiempo. '
                'Con una Work and Holiday Visa puedes trabajar en diferentes sectores '
                'como hostelería, construcción o agricultura mientras exploras el país.',
                style: TextStyle(
                  fontSize: 16,
                  height: 1.5,
                  color: Colors.black87,
                ),
              ),
              SizedBox(height: 16),
              Text(
                'En esta sección encontrarás consejos prácticos sobre cómo buscar empleo, '
                'adaptarte al estilo de vida australiano y aprovechar al máximo tu experiencia laboral.',
                style: TextStyle(
                  fontSize: 16,
                  height: 1.5,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
