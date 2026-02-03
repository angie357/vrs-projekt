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
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue), useMaterial3: true, fontFamily: 'MojFont'),
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
  String _statusDisplay = "Place phone near the device...";
  final TextEditingController _controller = TextEditingController();
  bool _isScanning = false;
  Timer? _nfcTimer;
  int _readStep = 1; // 1 = Send Request, 2 = Read Joke

  // Debug Log list
  List<String> _debugLogs = [];

  void _addLog(String message) {
    if (mounted) {
      setState(() {
        _debugLogs.insert(0, "${DateTime.now().second}s: $message");
        if (_debugLogs.length > 5) _debugLogs.removeLast();
      });
    }
  }

  void _startTimeout() {
    _nfcTimer?.cancel();
    _nfcTimer = Timer(const Duration(seconds: 10), () async {
      if (_isScanning) {
        await NfcManager.instance.stopSession();
        if (mounted) {
          setState(() {
            _isScanning = false;
            _statusDisplay = "Timed out. Please try again.";
            _addLog("TIMEOUT: No device found.");
          });
        }
      }
    });
  }

  // --- READ FUNCTION (GET_JOKE) ---
  void _readJoke() async {
    bool isAvailable = await NfcManager.instance.isAvailable();
    if (!isAvailable) {
      _updateStatus("ERROR: Enable NFC!");
      return;
    }

    if (_readStep == 1) {
      // --- STEP 1: SENT REQUEST ---
      setState(() {
        _isScanning = true;
        _statusDisplay = "Step 1: Sending GET_JOKE...";
      });
      _addLog("Sending GET_JOKE trigger...");

      _startTimeout();

      NfcManager.instance.startSession(onDiscovered: (NfcTag tag) async {
        try {
          var ndef = Ndef.from(tag);
          if (ndef == null) return;

          await ndef.write(NdefMessage([NdefRecord.createText("GET_JOKE")]));

          _nfcTimer?.cancel();
          _addLog("Request sent! Press physical button on STM32.");

          if (mounted) {
            setState(() {
              _readStep = 2;
              _statusDisplay = "Step 1 Done! Now press physical button, then tap '2. Read Joke'";
            });
          }
        } catch (e) {
          _addLog("ERR: $e");
          _updateStatus("Send failed.");
        } finally {
          NfcManager.instance.stopSession();
          if (mounted) setState(() => _isScanning = false);
        }
      });
    } else {
      // --- STEP 2: READ JOKE ---
      setState(() {
        _isScanning = true;
        _statusDisplay = "Step 2: Reading joke...";
      });
      _addLog("Attempting to read joke...");

      _startTimeout();

      NfcManager.instance.startSession(onDiscovered: (NfcTag tag) async {
        try {
          var ndef = Ndef.from(tag);
          if (ndef == null) return;

          NdefMessage response = await ndef.read();
          if (response.records.isEmpty) {
            _addLog("Tag is empty.");
          } else {
            String rawText = String.fromCharCodes(response.records.first.payload).substring(3);
            _addLog("Received: $rawText");
            _updateStatus(rawText);

            if (mounted) {
              setState(() {
                _readStep = 1;
              });
            }
          }
          _nfcTimer?.cancel();
        } catch (e) {
          _addLog("Read ERR: $e");
          _updateStatus("Read failed. Is the joke ready?");
        } finally {
          NfcManager.instance.stopSession();
          if (mounted) setState(() => _isScanning = false);
        }
      });
    }
  }

  // --- WRITE FUNCTION (ADD_JOKE) ---
  void _sendJoke() async {
    if (_controller.text.trim().isEmpty) {
      _updateStatus("Write a joke first!");
      _addLog("ERROR: Empty text field.");
      return;
    }

    bool isAvailable = await NfcManager.instance.isAvailable();
    if (!isAvailable) {
      _updateStatus("ERROR: Please enable NFC in settings!");
      _addLog("ERROR: NFC hardware is OFF.");
      return;
    }

    setState(() {
      _isScanning = true;
      _statusDisplay = "Uploading joke... Tap device.";
      _debugLogs.clear();
    });
    _addLog("Starting Write Session...");

    _startTimeout();

    NfcManager.instance.startSession(onDiscovered: (NfcTag tag) async {
      if (!_isScanning) return;

      try {
        var ndef = Ndef.from(tag);
        if (ndef == null || !ndef.isWritable) {
          _addLog("ERROR: Tag not writable.");
          _updateStatus("ERROR: Incompatible tag.");
          return;
        }

        String formattedJoke = "ADD_JOKE:${_controller.text.trim()}";
        _addLog("Writing: $formattedJoke");

        await ndef.write(NdefMessage([NdefRecord.createText(formattedJoke)]));
        _nfcTimer?.cancel();
        _addLog("Write successful. Waiting for STM32...");

        // Give STM32 time to update the response
        await Future.delayed(const Duration(milliseconds: 600));

        NdefMessage confirm = await ndef.read();
        String result = String.fromCharCodes(confirm.records.first.payload).substring(3);

        _addLog("STM32 Response: $result");
        _updateStatus(result);
        _controller.clear();
      } catch (e) {
        _updateStatus("Write failed.");
        _addLog("ERR: $e");
      } finally {
        NfcManager.instance.stopSession();
        if (mounted) setState(() => _isScanning = false);
      }
    });
  }

  void _updateStatus(String text) {
    if (mounted) setState(() => _statusDisplay = text);
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
              Tab(icon: Icon(Icons.auto_awesome), text: "Read"),
              Tab(icon: Icon(Icons.edit_note), text: "Write"),
            ],
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: TabBarView(
                children: [
                  // TAB 1
                  _buildTabContent(_buildStatusCard(), _buildReadButton()),
                  // TAB 2
                  _buildTabContent(_buildStatusCard(), _buildWriteSection()),
                ],
              ),
            ),
            // _buildDebugPanel(), // Spoločný log panel na spodku
          ],
        ),
      ),
    );
  }

  Widget _buildTabContent(Widget top, Widget bottom) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(children: [top, const SizedBox(height: 20), bottom]),
    );
  }

  Widget _buildWriteSection() {
    return Column(
      children: [
        TextField(
          controller: _controller,
          maxLines: 3,
          maxLength: 200,
          decoration: InputDecoration(
            hintText: "Enter joke...",
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
          ),
        ),
        const SizedBox(height: 10),
        _buildWriteButton(),
      ],
    );
  }

  Widget _buildStatusCard() {
    return Card(
      elevation: 4,
      color: _isScanning ? Colors.teal[50] : Colors.blue[100],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: SizedBox(
          width: double.infinity,
          child: Text(_statusDisplay, style: const TextStyle(fontSize: 16), textAlign: TextAlign.center),
        ),
      ),
    );
  }

  Widget _buildDebugPanel() {
    return Container(
      height: 120,
      width: double.infinity,
      color: Colors.grey[900],
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("DEBUG CONSOLE", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 10)),
          const Divider(color: Colors.green, height: 5),
          Expanded(
            child: ListView.builder(
              itemCount: _debugLogs.length,
              itemBuilder: (context, i) => Text(_debugLogs[i],
                  style: const TextStyle(color: Colors.greenAccent, fontSize: 12, fontFamily: 'monospace')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReadButton() {
    return Column(
      children: [
        ElevatedButton.icon(
          onPressed: _isScanning ? null : _readJoke,
          icon: Icon(_readStep == 1 ? Icons.send : Icons.download),
          label: Text(_readStep == 1 ? "Send Request (GET_JOKE)" : "Read Joke"),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 60),
            backgroundColor: _readStep == 1 ? Colors.blue[900] : Colors.green[700],
            foregroundColor: Colors.white,
          ),
        ),
        if (_readStep == 2)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: TextButton(
              onPressed: () => setState(() => _readStep = 1),
              child: const Text("Reset to Step 1"),
            ),
          ),
      ],
    );
  }

  Widget _buildWriteButton() {
    return ElevatedButton.icon(
      onPressed: _isScanning ? null : _sendJoke,
      icon: const Icon(Icons.upload),
      label: Text(_isScanning ? "Writing..." : "Save Joke"),
      style: ElevatedButton.styleFrom(
          minimumSize: const Size(double.infinity, 50),
          backgroundColor: Colors.blue[900],
          foregroundColor: Colors.white),
    );
  }
}
