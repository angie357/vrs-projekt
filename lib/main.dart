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
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
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
  String _jokeDisplay = "Prilož mobil k zariadeniu...";
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
          _jokeDisplay = "Čas vypršal. Skús to znova.";
        });
      }
    });
  }

  void _readJoke() async {
    setState(() => _isScanning = true);
    _startTimeout();
    NfcManager.instance.startSession(onDiscovered: (NfcTag tag) async {
      _nfcTimer?.cancel();
      try {
        var ndef = Ndef.from(tag);
        if (ndef == null) return;
        NdefMessage message = await ndef.read();
        String joke = String.fromCharCodes(message.records.first.payload).substring(3);
        setState(() => _jokeDisplay = joke);
      } catch (e) {
        setState(() => _jokeDisplay = "Chyba čítania.");
      } finally {
        NfcManager.instance.stopSession();
        setState(() => _isScanning = false);
      }
    });
  }

  void _sendJoke() async {
    if (_controller.text.isEmpty) return;

    // 1. Príprava stavu
    setState(() {
      _isScanning = true;
      _jokeDisplay = "Prilož mobil k zariadeniu pre zápis...";
    });

    // 2. Nastavenie časovača
    _nfcTimer?.cancel();
    _nfcTimer = Timer(const Duration(seconds: 10), () async {
      if (_isScanning) {
        // Force stop - dôležité poradie
        await NfcManager.instance.stopSession();
        if (mounted) {
          setState(() {
            _isScanning = false;
            _jokeDisplay = "Čas na zápis vypršal. Skús to znova.";
          });
        }
      }
    });

    // 3. Spustenie NFC relácie
    try {
      await NfcManager.instance.startSession(
        // Nastavíme polling options, aby sme znížili latenciu (len pre Android, iOS ignoruje)
        pollingOptions: {NfcPollingOption.iso14443, NfcPollingOption.iso15693},
        onDiscovered: (NfcTag tag) async {
          // OKAMŽITÁ KONTROLA: Ak už časovač vybehol, nič nerob
          if (!_isScanning) return;

          _nfcTimer?.cancel(); // Tag sme našli, zruš odpočet

          try {
            var ndef = Ndef.from(tag);
            if (ndef == null || !ndef.isWritable) {
              _updateStatus("Chyba: Tag nepodporuje zápis.");
              await NfcManager.instance.stopSession(errorMessage: "Nevhodný tag.");
              return;
            }

            // Samotný zápis
            NdefMessage message = NdefMessage([NdefRecord.createText(_controller.text)]);
            await ndef.write(message);

            _updateStatus("Vtip bol úspešne nahraný!");
            _controller.clear();
            await NfcManager.instance.stopSession(); // Úspešné ukončenie

          } catch (e) {
            _updateStatus("Chyba počas zápisu: $e");
            await NfcManager.instance.stopSession(errorMessage: "Zápis zlyhal.");
          } finally {
            if (mounted) setState(() => _isScanning = false);
          }
        },
        onError: (error) async {
          _nfcTimer?.cancel();
          _updateStatus("NFC Chyba: $error");
          if (mounted) setState(() => _isScanning = false);
        },
      );
    } catch (e) {
      _nfcTimer?.cancel();
      _updateStatus("Nepodarilo sa spustiť NFC.");
      setState(() => _isScanning = false);
    }
  }

  // Pomocná funkcia na update textu bezpečným spôsobom
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
              Tab(icon: Icon(Icons.auto_awesome), text: "Získať vtip"),
              Tab(icon: Icon(Icons.edit_note), text: "Nahrať vtip"),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // --- ZÁLOŽKA 1: ČÍTANIE ---
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    child: Padding(
                      padding: const EdgeInsets.all(30.0),
                      child: Text(_jokeDisplay, style: const TextStyle(fontSize: 18), textAlign: TextAlign.center),
                    ),
                  ),
                  const SizedBox(height: 40),
                  ElevatedButton.icon(
                    onPressed: _isScanning ? null : _readJoke,
                    icon: _isScanning ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.nfc),
                    label: Text(_isScanning ? "Hľadám zariadenie..." : "Načítať náhodný vtip"),
                    style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 55)),
                  ),
                ],
              ),
            ),
            // --- ZÁLOŽKA 2: ZÁPIS ---
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  TextField(
                    controller: _controller,
                    maxLines: 5,
                    decoration: InputDecoration(
                      hintText: "Sem napíš svoj vtip...",
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                      filled: true,
                      fillColor: Colors.grey[100],
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: _isScanning ? null : _sendJoke,
                    icon: const Icon(Icons.send),
                    label: const Text("Nahrať cez NFC"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 55),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}