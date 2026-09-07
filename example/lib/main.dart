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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
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
  List<String> _screens = [];
  List<String> _permissions = [];
  Map<String, dynamic> _screenPermissions = {};

  @override
  void initState() {
    super.initState();

    // Listen for direct deep link opens from native intents
    DeepLinking.onDeepLinkOpen((params) {
      setState(() {
        _status = 'Deep link opened! Screen: ${params['screen']}, LinkId: ${params['linkId']}';
      });
    });

    // Listen for clipboard install attribution
    DeepLinking.onInstallAttribution((result) {
      setState(() {
        _status = 'Attributed from install listener! Method: ${result.method}';
        _screens = result.screens;
        _permissions = result.permissions;
        _screenPermissions = result.screenPermissions;
      });
    });
  }

  Future<void> _checkInstallAttribution() async {
    setState(() => _status = 'Checking attribution...');
    try {
      final result = await DeepLinking.trackInstall(
        linkId: 'DEMO_LINK_ID',
        installerUserId: 'user_123',
      );

      if (result != null && result.success) {
        setState(() {
          _status = 'Attributed! Method: ${result.method}, Ref: ${result.referralCode}';
          _screens = result.screens;
          _permissions = result.permissions;
          _screenPermissions = result.screenPermissions;
        });
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

  Future<void> _shareWithMultipleScreens() async {
    setState(() => _status = 'Registering multi-screen share...');
    try {
      final response = await DeepLinking.registerShare(
        linkId: 'DEMO_LINK_ID',
        screens: ['Catalog', 'ProductDetail', 'Checkout'],
        permissions: ['read', 'comment', 'vip'],
        screenPermissions: {
          'ProductDetail': ['view', 'buy'],
          'Checkout': ['apply_discount'],
        },
        senderReferralCode: 'REF_ALICE',
        senderUserId: 'user_alice',
        productId: 'prod_999',
      );

      setState(() {
        _status = 'Share registered! Link: ${response['shareUrl']}';
      });
    } catch (e) {
      setState(() => _status = 'Share Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('DeepLinking Multi-Screen & Permission Demo')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Attribution Status',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(_status, style: const TextStyle(fontSize: 14)),
                      if (_screens.isNotEmpty) ...[
                        const Divider(height: 24),
                        Text('Target Screens: ${_screens.join(", ")}'),
                      ],
                      if (_permissions.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text('Global Permissions: ${_permissions.join(", ")}'),
                      ],
                      if (_screenPermissions.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text('Screen Permissions: $_screenPermissions'),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _checkInstallAttribution,
                icon: const Icon(Icons.link),
                label: const Text('Track Deferred Install'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _shareWithMultipleScreens,
                icon: const Icon(Icons.share),
                label: const Text('Register Share (Multi-Screen + Perms)'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
