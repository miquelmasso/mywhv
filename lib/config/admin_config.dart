import 'package:firebase_auth/firebase_auth.dart';

const String adminUid = 'EuCfztB40CNpQ9OqosqF0H8TBUc2';

bool get isAdminSession => FirebaseAuth.instance.currentUser?.uid == adminUid;
