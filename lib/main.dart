import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_state.dart';
import 'ui/home_page.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  SharedPreferences? prefs;
  try {
    prefs = await SharedPreferences.getInstance();
  } catch (_) {
    prefs = null; // 保存できなくても使える
  }
  // exe にファイルを渡して起動したとき（アイコンへのドロップなど）は、選んだ状態で開く
  final state = AppState(prefs: prefs)..addPaths(args);
  runApp(FileNameUnifierApp(state: state));
}

class FileNameUnifierApp extends StatelessWidget {
  const FileNameUnifierApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ファイル名ととのえ',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF1F6F6A),
        useMaterial3: true,
        fontFamilyFallback: const ['Yu Gothic UI', 'Meiryo UI', 'Meiryo'],
      ),
      home: HomePage(state: state),
    );
  }
}
