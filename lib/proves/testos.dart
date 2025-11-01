import 'package:flutter/material.dart';
import 'emails_list_page.dart';
import 'careers_list_page.dart';

class HousePage extends StatelessWidget {
  const HousePage({super.key});
//prova quatre
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Proves Firebase Restaurants'),
        backgroundColor: Colors.deepPurple,
      ),
      body: Padding(
        //prova cinc
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.email_outlined),
                label: const Text('Veure correus dels restaurants'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 50),
                  textStyle: const TextStyle(fontSize: 16),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const EmailsListPage()),
                  );
                },
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                icon: const Icon(Icons.work_outline),
                label: const Text('Veure pàgines de feina'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 50),
                  textStyle: const TextStyle(fontSize: 16),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CareersListPage()),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
