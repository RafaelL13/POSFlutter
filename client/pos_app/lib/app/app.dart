import 'package:flutter/material.dart';
import 'package:pos_app/app/router.dart';

class PosApp extends StatelessWidget {
  const PosApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp.router(
        title: 'POS Flutter',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
        routerConfig: appRouter,
      );
}
