import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'screens/screens.dart';
import 'screens/consejos_page.dart';



// 👇 Fitxers per actualitzar codis postals
// ignore: unused_import
import 'models/visa_postcodes_uploader.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _selectedIndex = 0;

  static const List<Widget> _pages = <Widget>[
  MapPage(),
  ConsejosPage(),
  HousePage(),
  ProfilePage(),
];

static const List<String> _titles = <String>[
  'Map',
  'Consejos',
  'House',
  'Profile',
];

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
      currentIndex: _selectedIndex,
      selectedItemColor: Theme.of(context).colorScheme.primary,
      onTap: _onItemTapped,
      items: const <BottomNavigationBarItem>[
        BottomNavigationBarItem(
          icon: Icon(Icons.map_outlined),
          label: 'Map',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.lightbulb_outline),
          label: 'Consejos',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.house_outlined),
          label: 'House',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.person_outline),
          label: 'Profile',
        ),
      ],
    ),
  );
}
}
