import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'firebase_options.dart';
import 'navigation/route_observer.dart';
import 'screens/screens.dart';
import 'screens/map_osm_vector_page.dart';
import 'screens/admin_gate_page.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';



// 👇 Fitxers per actualitzar codis postals
// ignore: unused_import
import 'models/visa_postcodes_uploader.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: ".env");

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  // Mantén la xarxa de Firestore desactivada per defecte
  //await FirebaseFirestore.instance.disableNetwork();
  print('✅ Firebase initialized correctly');
  

  // 🔽 Descomenta aquestes línies si vols actualitzar els codis postals al Firestore:
  //
  //await VisaPostcodesUploader.uploadVisaPostcodes();     
  //
  // Quan s’executin, pujaran tots els codis nous al Firebase i eliminaran els anteriors.

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MyWHV',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color.fromARGB(255, 215, 10, 10),
        ),
      ),
      navigatorObservers: [routeObserver],
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, this.initialIndex = 1});

  final int initialIndex;

  @override
  State<MyHomePage> createState() => _MyHomePageState(initialIndex: initialIndex);
}

class _MyHomePageState extends State<MyHomePage> {
  _MyHomePageState({this.initialIndex = 1});

  final int initialIndex;
  late int _selectedIndex;
  int _adminTapCount = 0;
  DateTime? _adminFirstTap;

  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _selectedIndex = initialIndex;
    _pages = <Widget>[
      const MapOSMVectorPage(),
      GuideScreen(onNavigateToTab: _onItemTapped),
      const TipsRandomPage(),
      const ForumPage(),
    ];
  }

  void _onItemTapped(int index) {
    const forumIndex = 3;
    final now = DateTime.now();

    if (index == forumIndex) {
      if (_adminFirstTap == null || now.difference(_adminFirstTap!) > const Duration(seconds: 3)) {
        _adminFirstTap = now;
        _adminTapCount = 1;
      } else {
        _adminTapCount += 1;
      }

      if (_adminTapCount >= 10) {
        _adminTapCount = 0;
        _adminFirstTap = null;
        HapticFeedback.mediumImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Admin gate unlocked')),
        );
        _openAdminGate();
      }
    } else {
      _adminTapCount = 0;
      _adminFirstTap = null;
    }

    setState(() => _selectedIndex = index);
  }

  Future<void> _openAdminGate() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const AdminGatePage()),
    );
    if (result == true && mounted) {
      setState(() {}); // refresh UI to reflect admin session
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        showSelectedLabels: false,
        showUnselectedLabels: false,
        currentIndex: _selectedIndex,
        selectedItemColor: Theme.of(context).colorScheme.primary,
        onTap: _onItemTapped,
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.map_outlined),
            label: '',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.lightbulb_outline),
            label: '',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.auto_awesome),
            label: '',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.forum_outlined),
            label: '',
          ),
        ],
      ),
    );
  }
}
