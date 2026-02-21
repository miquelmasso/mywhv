import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'firebase_options.dart';
import 'navigation/route_observer.dart';
import 'screens/screens.dart';
import 'screens/map_osm_vector_page.dart';
import 'screens/admin_gate_page.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'services/offline_bootstrap_service.dart';
import 'services/offline_state.dart';



// 👇 Fitxers per actualitzar codis postals
// ignore: unused_import
import 'models/visa_postcodes_uploader.dart';

Future<void> main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  await dotenv.load(fileName: ".env");

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  // Mantén la xarxa de Firestore desactivada per defecte
  //await FirebaseFirestore.instance.disableNetwork();
  print('✅ Firebase initialized correctly');

  await OfflineBootstrapService.instance.init();
  print('🔌 Offline mode: ${OfflineState.instance.isOfflineMode}');
  
  FlutterNativeSplash.remove();

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

  BottomNavigationBarItem _buildNavItem(IconData iconData, int index) {
    return BottomNavigationBarItem(
      icon: _buildNavIcon(iconData, false),
      activeIcon: _buildNavIcon(iconData, true),
      label: '',
    );
  }

  Widget _buildNavIcon(IconData iconData, bool selected) {
    final primary = Theme.of(context).colorScheme.primary;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      decoration: BoxDecoration(
        color: selected ? primary.withOpacity(0.14) : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(
        iconData,
        color: selected ? primary : Colors.grey.shade600,
        size: 24,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _pages,
      ),
      bottomNavigationBar: Theme(
        data: Theme.of(context).copyWith(
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          hoverColor: Colors.transparent,
        ),
        child: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          showSelectedLabels: false,
          showUnselectedLabels: false,
          currentIndex: _selectedIndex,
          selectedItemColor: Theme.of(context).colorScheme.primary,
          onTap: _onItemTapped,
          items: <BottomNavigationBarItem>[
            _buildNavItem(Icons.map_outlined, 0),
            _buildNavItem(Icons.lightbulb_outline, 1),
            _buildNavItem(Icons.auto_awesome, 2),
            _buildNavItem(Icons.forum_outlined, 3),
          ],
        ),
      ),
    );
  }
}
