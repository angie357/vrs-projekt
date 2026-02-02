import 'dart:async';
import 'package:flutter/material.dart';
import 'package:nfc_manager/nfc_manager.dart';

void main() => runApp(const JokeNfcApp());

class JokeNfcApp extends StatelessWidget {
  const JokeNfcApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const JokeHomePage(),
    );
  }
}

class JokeHomePage extends StatefulWidget {
  const JokeHomePage({super.key});

  @override
  State<JokeHomePage> createState() => _JokeHomePageState();
}

class _JokeHomePageState extends State<JokeHomePage> {
  String _jokeDisplay = "Enclose phone to the device...";
  final TextEditingController _controller = TextEditingController();
  bool _isScanning = false;
  Timer? _nfcTimer;

  void _startTimeout() {
    _nfcTimer?.cancel();
    _nfcTimer = Timer(const Duration(seconds: 10), () {
      if (_isScanning) {
        NfcManager.instance.stopSession();
        setState(() {
          _isScanning = false;
          _jokeDisplay = "Timed out. Try again.";
        });
      }
    });
  }

  // --- READ FUNCTION ---
  void _readJoke() async {
    // 1. Kontrola, či je NFC zapnuté v mobile
    bool isAvailable = await NfcManager.instance.isAvailable();
    if (!isAvailable) {
      _updateStatus("Error: Turn on NFC in the phone 1!");
      return;
    }

    setState(() {
      _isScanning = true;
      _jokeDisplay = "Looking for device... Enclose phone.";
    });

    _startTimeout();

    NfcManager.instance.startSession(onDiscovered: (NfcTag tag) async {
      _nfcTimer?.cancel();
      try {
        var ndef = Ndef.from(tag);
        if (ndef == null) {
          _updateStatus("Error: This is not a joke (invalid format).");
          return;
        }

        NdefMessage message = await ndef.read();
        if (message.records.isEmpty) {
          _updateStatus("Device is empty, no joke.");
        } else {
          String joke = String.fromCharCodes(message.records.first.payload).substring(3);
          _updateStatus("Received joke: $joke");
        }
      } catch (e) {
        _updateStatus("Error downloading joke.");
      } finally {
        NfcManager.instance.stopSession();
        if (mounted) setState(() => _isScanning = false);
      }
    });
  }

  // --- WRITE FUNCTION ---
  void _sendJoke() async {
    // 1. TEXT CONTROL
    if (_controller.text.trim().isEmpty) {
      setState(() => _jokeDisplay = "ERROR: Write text!");
      return;
    }

    // 2. HARDWARE CONTROL
    bool isAvailable = await NfcManager.instance.isAvailable();
    if (!isAvailable) {
      setState(() => _jokeDisplay = "ERROR: Turn on NFC in the phone!");
      return;
    }

    // 3. STEP "WRITING"
    setState(() {
      _isScanning = true;
      _jokeDisplay = "READY: Enclose phone to STM32...";
    });

    _nfcTimer?.cancel();
    _nfcTimer = Timer(const Duration(seconds: 10), () async {
      if (_isScanning) {
        await NfcManager.instance.stopSession();
        if (mounted) {
          setState(() {
            _isScanning = false;
            _jokeDisplay = "TIMED OUT: Device not found.";
          });
        }
      }
    });

    // 4. Turn on NFC
    NfcManager.instance.startSession(onDiscovered: (NfcTag tag) async {
      if (!_isScanning) return;

      _nfcTimer?.cancel();

      setState(() => _jokeDisplay = "DEVICE FOUND: Writing data...");

      try {
        var ndef = Ndef.from(tag);
        if (ndef == null || !ndef.isWritable) {
          _updateStatus("ERROR: This chip does not support write.");
        } else {
          await ndef.write(NdefMessage([NdefRecord.createText(_controller.text)]));
          _updateStatus("DONE: Joke sent successfully!");
          _controller.clear();
        }
      } catch (e) {
        _updateStatus("ERROR: Write failed. Try again.");
      } finally {
        await NfcManager.instance.stopSession();
        if (mounted) setState(() => _isScanning = false);
      }
    }, onError: (error) async {
      _nfcTimer?.cancel();
      _updateStatus("NFC ERROR: $error");
      if (mounted) setState(() => _isScanning = false);
    });
  }

  void _updateStatus(String text) {
    if (mounted) {
      setState(() => _jokeDisplay = text);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('NFC Joke Database'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.auto_awesome), text: "Read joke"),
              Tab(icon: Icon(Icons.edit_note), text: "Write joke"),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // --- TAB 1: READ ---
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  _buildStatusCard(),
                  const SizedBox(height: 20),
                  _buildReadButton(),
                ],
              ),
            ),

            // --- TAB 2: WRITE ---
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    _buildStatusCard(),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _controller,
                      maxLines: 5,
                      decoration: InputDecoration(
                        hintText: "Write your joke here...",
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                        filled: true,
                        fillColor: Colors.grey[100],
                      ),
                    ),
                    const SizedBox(height: 20),
                    _buildWriteButton(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    return Card(
      elevation: 4,
      color: _isScanning ? Colors.teal[50] : Colors.blue[100],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(25.0),
        child: SizedBox(
          width: double.infinity,
          child: Text(_jokeDisplay,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500), textAlign: TextAlign.center),
        ),
      ),
    );
  }

  Widget _buildReadButton() {
    return ElevatedButton.icon(
      onPressed: _isScanning ? null : _readJoke,
      icon: _isScanning
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.download),
      label: Text(_isScanning ? "Looking for joke..." : "Read random joke"),
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(double.infinity, 55),
        foregroundColor: Colors.white,
        backgroundColor: Colors.blue[900],

      ),
    );
  }

  Widget _buildWriteButton() {
    return ElevatedButton.icon(
      onPressed: _isScanning ? null : _sendJoke,
      icon: _isScanning
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : const Icon(Icons.upload),
      label: Text(_isScanning ? "Writing..." : "Write through NFC"),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.blue[900],
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 55),
      ),
    );
  }
}
