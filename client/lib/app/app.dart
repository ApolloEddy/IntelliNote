import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../features/home/home_page.dart';
import 'app_state.dart';

class IntelliNoteApp extends StatelessWidget {
  const IntelliNoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState(),
      child: MaterialApp(
        title: 'IntelliNote',
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: Colors.indigo,
          fontFamily: 'Consolas',
          fontFamilyFallback: const ['SimHei'],
          textTheme: const TextTheme(
            bodyLarge: TextStyle(fontSize: 18),
            bodyMedium: TextStyle(fontSize: 16),
            titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
        ),
        home: const HomePage(),
      ),
    );
  }
}
