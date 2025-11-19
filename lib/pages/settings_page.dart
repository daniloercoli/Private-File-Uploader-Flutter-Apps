import 'package:flutter/material.dart';
import '../services/app_storage.dart';
import '../services/wp_api.dart'; // 👈 aggiunto

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final _urlCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _testing = false; // 👈 nuovo stato per test connessione

  @override
  void initState() {
    super.initState();
    _loadStoredValues();
  }

  Future<void> _loadStoredValues() async {
    // Carica i valori salvati (se ci sono)
    final url = await AppStorage.getUrl() ?? '';
    final user = await AppStorage.getUsername() ?? '';
    final pass = await AppStorage.getPassword() ?? '';

    _urlCtrl.text = url;
    _userCtrl.text = user;
    _passCtrl.text = pass;

    setState(() => _loading = false);
  }

  Future<void> _onSave() async {
    // Validazione semplice: URL e credenziali non vuoti
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    try {
      await AppStorage.setUrl(_urlCtrl.text.trim());
      await AppStorage.setUsername(_userCtrl.text.trim());
      await AppStorage.setPassword(_passCtrl.text);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Impostazioni salvate')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Errore salvataggio: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _onReset() async {
    setState(() => _saving = true);
    try {
      await AppStorage.resetAll();
      _urlCtrl.clear();
      _userCtrl.clear();
      _passCtrl.clear();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Impostazioni ripristinate')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Errore reset: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _onTestConnection() async {
    // Usiamo la stessa validazione del form (URL, user, pass non vuoti e URL valido)
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Correggi i campi evidenziati prima di testare')));
      return;
    }

    final url = _urlCtrl.text.trim();
    final user = _userCtrl.text.trim();
    final pass = _passCtrl.text;

    setState(() => _testing = true);

    // Modale di "test in corso"
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        title: Text('Test connessione'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 8),
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Verifica in corso…', textAlign: TextAlign.center),
          ],
        ),
      ),
    );

    final res = await WpApi.ping(baseUrl: url, username: user, password: pass);

    if (!mounted) return;
    Navigator.of(context).pop(); // chiude la modale di loading
    setState(() => _testing = false);

    final ok = res['ok'] == true;
    final status = res['status'];
    final body = (res['body'] ?? '').toString();

    if (ok) {
      // dialog di successo + chiedi se vuole salvare
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Connessione riuscita'),
          content: Text(
            'Ping eseguito con successo (HTTP $status).\n\n'
            'Vuoi salvare queste impostazioni?',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('No')),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(ctx).pop();
                await _onSave();
              },
              child: const Text('Salva'),
            ),
          ],
        ),
      );
    } else {
      // dialog di errore
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Connessione fallita'),
          content: Text(
            'Impossibile contattare il server.\n\n'
            'HTTP $status\n$body',
          ),
          actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Chiudi'))],
        ),
      );
    }
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final isBusy = _saving || _testing;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Credenziali del Cloud', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                const SizedBox(height: 16),

                // URL
                TextFormField(
                  controller: _urlCtrl,
                  decoration: const InputDecoration(
                    labelText: 'URL del sito (es. https://filesuploader.ercoliconsulting.eu/)',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.url,
                  validator: (v) {
                    final s = v?.trim() ?? '';
                    if (s.isEmpty) return 'Inserisci l’URL';
                    // validazione molto basica
                    if (!s.startsWith('http://') && !s.startsWith('https://')) {
                      return 'L’URL deve iniziare con http:// o https://';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                // USERNAME
                TextFormField(
                  controller: _userCtrl,
                  decoration: const InputDecoration(labelText: 'Username', border: OutlineInputBorder()),
                  validator: (v) => (v == null || v.isEmpty) ? 'Inserisci lo username' : null,
                ),
                const SizedBox(height: 12),

                // PASSWORD (secure)
                TextFormField(
                  controller: _passCtrl,
                  decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
                  obscureText: true,
                  validator: (v) => (v == null || v.isEmpty) ? 'Inserisci la password' : null,
                ),
                const SizedBox(height: 20),

                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: isBusy ? null : _onSave,
                        icon: const Icon(Icons.save),
                        label: _saving ? const Text('Salvataggio…') : const Text('Salva'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: isBusy ? null : _onReset,
                      icon: const Icon(Icons.restore),
                      label: const Text('Reset'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: isBusy ? null : _onTestConnection,
                    icon: const Icon(Icons.wifi_tethering),
                    label: _testing ? const Text('Test in corso…') : const Text('Test connection'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
