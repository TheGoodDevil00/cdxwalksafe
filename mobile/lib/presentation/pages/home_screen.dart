import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../../data/datasources/api_client.dart';
import '../widgets/map_widget.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ApiClient _apiClient = ApiClient();
  List<LatLng> _currentRoute = [];
  bool _isLoading = false;

  void _fetchRoute() async {
    setState(() => _isLoading = true);
    // Mock coordinates for demo
    final start = LatLng(51.509364, -0.128928);
    final end = LatLng(51.515, -0.130);

    final routes = await _apiClient.getRoutes(start, end);

    if (routes.isNotEmpty) {
      // Pick the 'safest' or first one
      setState(() {
        _currentRoute = routes.first.points;
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('No routes found')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SafeWalk'),
        actions: [
          IconButton(icon: const Icon(Icons.shield_outlined), onPressed: () {}),
        ],
      ),
      body: Stack(
        children: [
          SafeWalkMap(routePoints: _currentRoute, routeColor: Colors.green),
          // const Center(child: Text("Map Placeholder")),
          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const TextField(
                      decoration: InputDecoration(
                        hintText: "Where to?",
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton(
                      onPressed: _isLoading ? null : _fetchRoute,
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 50),
                        backgroundColor: Colors.blueAccent,
                        foregroundColor: Colors.white,
                      ),
                      child: _isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text('Find Safe Route'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
