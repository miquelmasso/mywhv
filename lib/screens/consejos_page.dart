import 'package:flutter/material.dart';

class ConsejosPage extends StatelessWidget {
  const ConsejosPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Tips for working in Australia',
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
                '🌏 Working in Australia with a Work and Holiday Visa',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  height: 1.3,
                ),
              ),
              SizedBox(height: 16),
              Text(
                'Australia is full of opportunities if you want to travel, '
                'improve your English and gain work experience at the same time. '
                'With a Work and Holiday Visa you can work in sectors like '
                'hospitality, construction or agriculture while exploring the country.',
                style: TextStyle(
                  fontSize: 16,
                  height: 1.5,
                  color: Colors.black87,
                ),
              ),
              SizedBox(height: 16),
              Text(
                'In this section you will find practical tips on how to look for work, '
                'adapt to the Australian lifestyle and make the most of your work experience.',
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
