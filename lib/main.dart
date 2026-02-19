import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' show parse;

void main() => runApp(const MaxNetApp());

class MaxNetApp extends StatelessWidget {
  const MaxNetApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true, 
        colorSchemeSeed: const Color(0xFF0055A4),
      ),
      home: const LoginPage(),
    );
  }
}

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  final _client = http.Client();
  String? _cookie;

  Future<Map<String, String>?> login(String login, String password) async {
    final url = Uri.parse('https://stat.maximuma.net/index.php');
    final initUrl = Uri.parse('https://stat.maximuma.net/index2.php');

    try {
      // 1. Отримання сесійної куки 
      final initRes = await _client.get(initUrl, headers: {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36',
      });
      
      _cookie = initRes.headers['set-cookie']?.split(';').first;

      // 2. Авторизація (POST) 
      final request = http.Request('POST', url);
      request.headers.addAll({
        'Content-Type': 'application/x-www-form-urlencoded',
        'User-Agent': 'Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36',
        'Referer': 'https://stat.maximuma.net/index2.php',
        'Origin': 'https://stat.maximuma.net',
        if (_cookie != null) 'Cookie': _cookie!,
      });

      request.bodyFields = {
        'login': login.trim(),
        'password': password.trim(),
        'action': 'actlogin',
      };

      final streamedResponse = await _client.send(request);
      final response = await http.Response.fromStream(streamedResponse);

      // 3. Аналіз відповіді 
      if (response.body.contains('ІНФОРМАЦІЯ АБОНЕНТА') || response.body.contains(login.trim())) {
        return _parseData(response.body);
      } else {
        throw Exception("Невірний логін або пароль");
      }
    } catch (e) {
      rethrow;
    }
  }

  // Оновлений парсинг усіх даних 
  Map<String, String> _parseData(String html) {
    var doc = parse(html);
    Map<String, String> data = {
      'balance': '0.00',
      'id': '---',
      'name': '---',
      'tariff': '---',
      'status': '---',
      'expiry': '---',
    };

    var rows = doc.querySelectorAll('tr');
    for (var row in rows) {
      var text = row.text;
      var cells = row.querySelectorAll('td');
      if (cells.length < 2) continue;

      var value = cells.last.text.trim();

      // Шукаємо відповідність за ключовими словами в рядку таблиці
      if (text.contains('№ договору')) data['id'] = value;
      if (text.contains('ПІБ')) data['name'] = value;
      if (text.contains('Тарифний план')) data['tariff'] = value;
      if (text.contains('Статус')) data['status'] = value;
      if (text.contains('Кінцева дата')) data['expiry'] = value;
      
      if (text.contains('Поточний баланс')) {
        var redFont = row.querySelector("font[color='red']");
        data['balance'] = redFont != null ? redFont.text.trim() : value;
      }
    }
    return data;
  }
}

// --- LoginPage ---

class _LoginPageState extends State<LoginPage> {
  final _l = TextEditingController();
  final _p = TextEditingController();
  bool _busy = false;

  void _submit() async {
    if (_l.text.isEmpty || _p.text.isEmpty) return;
    setState(() => _busy = true);
    
    try {
      final res = await ApiService().login(_l.text, _p.text);
      if (mounted && res != null) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (c) => HomePage(data: res)));
      }
    } catch (e) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text("Помилка"),
            content: Text(e.toString().replaceAll("Exception:", "")),
            actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text("OK"))],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(30),
          child: Column(children: [
            const Icon(Icons.wifi_tethering, size: 80, color: Color(0xFF0055A4)),
            const SizedBox(height: 20),
            const Text("MAXIMUM-NET", style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Color(0xFF0055A4))),
            const SizedBox(height: 40),
            TextField(controller: _l, decoration: const InputDecoration(labelText: "ID або Логін", border: OutlineInputBorder())),
            const SizedBox(height: 15),
            TextField(controller: _p, obscureText: true, decoration: const InputDecoration(labelText: "Пароль", border: OutlineInputBorder())),
            const SizedBox(height: 30),
            if (_busy) const CircularProgressIndicator() 
            else SizedBox(width: double.infinity, height: 55, 
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0055A4), foregroundColor: Colors.white),
                onPressed: _submit, child: const Text("УВІЙТИ")
              )
            ),
          ]),
        ),
      ),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

// --- HomePage з виведенням усіх даних ---

class HomePage extends StatelessWidget {
  final Map<String, String> data;
  const HomePage({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Мій Кабінет"),
        backgroundColor: const Color(0xFF0055A4),
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: Container(
        color: Colors.grey[100],
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildBalanceCard(),
            const SizedBox(height: 16),
            _buildInfoTile("Абонент", data['name']!, Icons.person),
            _buildInfoTile("ID Договору", data['id']!, Icons.assignment),
            _buildInfoTile("Тариф", data['tariff']!, Icons.speed),
            _buildInfoTile("Статус", data['status']!, Icons.info_outline),
            _buildInfoTile("Діє до", data['expiry']!, Icons.calendar_today),
          ],
        ),
      ),
    );
  }

  Widget _buildBalanceCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          gradient: const LinearGradient(
            colors: [Color(0xFF0055A4), Color(0xFF0077E6)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          children: [
            const Text("Поточний баланс", style: TextStyle(color: Colors.white70, fontSize: 16)),
            const SizedBox(height: 10),
            Text("${data['balance']} грн", 
              style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoTile(String label, String value, IconData icon) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF0055A4)),
        title: Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey)),
        subtitle: Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black87)),
      ),
    );
  }
}
