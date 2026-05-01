import 'package:flutter/material.dart';

import 'be_associate_screen.dart';
import 'find_associates_screen.dart';
import 'my_bookings_screen.dart';

class AssociatesHubScreen extends StatelessWidget {
  const AssociatesHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Associate Doctors'),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(icon: Icon(Icons.search), text: 'Find'),
              Tab(icon: Icon(Icons.medical_services_outlined), text: 'Be an Associate'),
              Tab(icon: Icon(Icons.event_note_outlined), text: 'My Bookings'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            FindAssociatesScreen(),
            BeAssociateScreen(),
            MyBookingsScreen(),
          ],
        ),
      ),
    );
  }
}
