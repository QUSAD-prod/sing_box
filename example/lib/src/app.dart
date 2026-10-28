import 'package:flutter/material.dart';

import 'home_page.dart';
import 'logs_page.dart';
import 'routing_page.dart';
import 'servers_page.dart';
import 'tools_page.dart';

/// Root widget of the example app.
class ExampleApp extends StatefulWidget {
  const ExampleApp({super.key});

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> {
  int _index = 0;

  static const _pages = [
    (title: 'sing-box VPN', icon: Icons.shield_outlined, page: HomePage()),
    (title: 'Servers', icon: Icons.dns_outlined, page: ServersPage()),
    (title: 'Routing', icon: Icons.alt_route, page: RoutingPage()),
    (title: 'Logs', icon: Icons.notes, page: LogsPage()),
    (title: 'Tools', icon: Icons.build_outlined, page: ToolsPage()),
  ];

  @override
  Widget build(BuildContext context) {
    final page = _pages[_index];
    return MaterialApp(
      title: 'sing_box example',
      theme: ThemeData(colorSchemeSeed: Colors.teal),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.teal,
        brightness: Brightness.dark,
      ),
      home: Scaffold(
        appBar: AppBar(title: Text(page.title)),
        body: page.page,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: [
            for (final p in _pages)
              NavigationDestination(
                icon: Icon(p.icon),
                label: p.title == 'sing-box VPN' ? 'Home' : p.title,
              ),
          ],
        ),
      ),
    );
  }
}
