import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'firebase_options.dart';
import 'screens/screens.dart';



// 👇 Fitxers per actualitzar codis postals
// ignore: unused_import
import 'models/visa_postcodes_uploader.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  //await FirebaseFirestore.instance.disableNetwork();


  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
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
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  State<MyHomePage> createState() => _MyHomePageState(initialIndex: initialIndex);
}

class _MyHomePageState extends State<MyHomePage> {
  _MyHomePageState({this.initialIndex = 0});

  final int initialIndex;
  late int _selectedIndex;

  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _selectedIndex = initialIndex;
    _pages = <Widget>[
      const MapPage(),
      GuideScreen(onNavigateToTab: _onItemTapped),
      const TipsRandomPage(),
      const ForumPage(),
    ];
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
Widget build(BuildContext context) {
  return Scaffold(
    // ❌ Eliminem l’AppBar
    // appBar: AppBar(
    //   backgroundColor: Theme.of(context).colorScheme.inversePrimary,
    //   title: Text(_titles[_selectedIndex]),
    // ),

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
