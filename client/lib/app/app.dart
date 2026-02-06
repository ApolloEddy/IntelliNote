import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../features/home/home_page.dart';
import 'app_state.dart';

class IntelliNoteApp extends StatelessWidget {
  const IntelliNoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState()..seedDemoData(),
      child: MaterialApp(
        title: 'IntelliNote',
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: Colors.indigo,
        ),
        home: const HomePage(),
      ),
    );
  }
}
