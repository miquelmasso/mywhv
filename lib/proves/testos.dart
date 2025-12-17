import 'package:flutter/material.dart';
import 'emails_list_page.dart';
import 'careers_list_page.dart';

class HousePage extends StatelessWidget {
  const HousePage({super.key});
//prova dos
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('House'),
        backgroundColor: Colors.deepPurple,
      ),
      body: const Center(
        child: Text(
          'House',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
