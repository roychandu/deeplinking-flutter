import 'package:flutter/material.dart';
import 'package:deeplinking/deeplinking.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize DeepLinking SDK
  DeepLinking.configure(
    baseUrl: 'https://deeplinking.in',
    appId: 'com.example.deeplinking_demo',
    sdkKey: 'dlk_live_demo_key_xxxxxxxx',
  );

  runApp(const DemoApp());
}

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DeepLinking Demo',
      theme: ThemeData(primarySwatch: Colors.teal, useMaterial3: true),
      home: const DemoHomePage(),
    );
  }
}

class DemoHomePage extends StatefulWidget {
  const DemoHomePage({super.key});

  @override
  State<DemoHomePage> createState() => _DemoHomePageState();
}

class _DemoHomePageState extends State<DemoHomePage> {
  String _status = 'Idle';

  Future<void> _checkInstallAttribution() async {
    setState(() => _status = 'Checking attribution...');
    try {
      final result = await DeepLinking.trackInstall(
        linkId: 'DEMO_LINK_ID',
        installerUserId: 'user_123',
      );

      if (result != null && result.success) {
        setState(() => _status = 'Attributed! Method: ${result.method}, Ref: ${result.referralCode}');
      } else {
        setState(() => _status = 'Organic Install / No Match');
      }
    } on SdkLimitExceededException catch (e) {
      setState(() => _status = 'Limit Error: ${e.message}');
    } on InvalidSdkKeyException catch (e) {
      setState(() => _status = 'SDK Key Error: ${e.message}');
    } catch (e) {
      setState(() => _status = 'Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('DeepLinking SDK Example')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_status, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _checkInstallAttribution,
                icon: const Icon(Icons.link),
                label: const Text('Track Deferred Install'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
