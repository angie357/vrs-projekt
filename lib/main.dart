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
        fontFamily: 'MojFont'
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
  String _jokeDisplay = "Place phone near the device...";
  final TextEditingController _controller = TextEditingController();
  bool _isScanning = false;
  Timer? _nfcTimer;

  // --- 10 SECOND TIMEOUT ---
  void _startTimeout() {
    _nfcTimer?.cancel();
    _nfcTimer = Timer(const Duration(seconds: 10), () async {
      if (_isScanning) {
        await NfcManager.instance.stopSession();
        if (mounted) {
          setState(() {
            _isScanning = false;
            _jokeDisplay = "Timed out. Please try again.";
          });
        }
      }
    });
  }

  // --- READ FUNCTION (GET_JOKE) ---
  void _readJoke() async {
    // Check if NFC is enabled on the phone hardware
    bool isAvailable = await NfcManager.instance.isAvailable();
    if (!isAvailable) {
      _updateStatus("ERROR: Please enable NFC in settings!");
      return;
    }

    setState(() {
      _isScanning = true;
      _jokeDisplay = "Sending request GET_JOKE...";
    });

    _startTimeout();

    NfcManager.instance.startSession(onDiscovered: (NfcTag tag) async {
      try {
        var ndef = Ndef.from(tag);
        if (ndef == null || !ndef.isWritable) {
          _updateStatus("ERROR: Incompatible NFC tag.");
          return;
        }

        // STEP 1: Write "GET_JOKE"
        await ndef.write(NdefMessage([NdefRecord.createText("GET_JOKE")]));
        _updateStatus("Request sent. Waiting for response...");

        // STEP 2: Wait for STM32 processing
        await Future.delayed(const Duration(milliseconds: 600));

        // STEP 3: Read response
        NdefMessage response = await ndef.read();
        if (response.records.isEmpty) {
          _updateStatus("Device returned no data.");
        } else {
          String rawText = String.fromCharCodes(response.records.first.payload).substring(3);

          if (rawText == "INVALID REQUEST") {
            _updateStatus("ERROR: STM32 rejected the command.");
          } else {
            _updateStatus(rawText);
          }
        }
        _nfcTimer?.cancel();
      } catch (e) {
        _updateStatus("Error in communication.");
      } finally {
        NfcManager.instance.stopSession();
        if (mounted) setState(() => _isScanning = false);
      }
    });
  }

  // --- WRITE FUNCTION (ADD_JOKE) ---
  void _sendJoke() async {
    if (_controller.text.trim().isEmpty) {
      _updateStatus("Write a joke first!");
      return;
    }

    bool isAvailable = await NfcManager.instance.isAvailable();
    if (!isAvailable) {
      _updateStatus("ERROR: NFC is disabled!");
      return;
    }

    setState(() {
      _isScanning = true;
      _jokeDisplay = "Saving joke to database...";
    });

    _startTimeout();

    NfcManager.instance.startSession(onDiscovered: (NfcTag tag) async {
      if (!_isScanning) return;

      try {
        var ndef = Ndef.from(tag);
        if (ndef == null || !ndef.isWritable) {
          _updateStatus("ERROR: Tag is not writable.");
          return;
        }

        String formattedJoke = "ADD_JOKE:${_controller.text.trim()}";

        await ndef.write(NdefMessage([NdefRecord.createText(formattedJoke)]));
        _nfcTimer?.cancel();

        // Check for "ADD_JOKE request received" confirmation
        await Future.delayed(const Duration(milliseconds: 500));
        NdefMessage confirm = await ndef.read();
        String result = String.fromCharCodes(confirm.records.first.payload).substring(3);

        _updateStatus(result);
        _controller.clear();
      } catch (e) {
        _updateStatus("Write failed. Check connection.");
      } finally {
        NfcManager.instance.stopSession();
        if (mounted) setState(() => _isScanning = false);
      }
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
                      maxLength: 200,
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
      // Using your requested Teal/Blue color logic
      color: _isScanning ? Colors.teal[50] : Colors.blue[100],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(25.0),
        child: SizedBox(
          width: double.infinity,
          child: Text(
            _jokeDisplay,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
            textAlign: TextAlign.center,
          ),
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