import 'dart:convert';
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
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          primary: Colors.deepPurple,
          secondary: Colors.orange,
        ),
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

  // Універсальне декодування кирилиці для Windows-1251
  String _decodeWin1251(List<int> bytes) {
    var out = StringBuffer();
    for (var byte in bytes) {
      if (byte >= 192 && byte <= 255) {
        out.writeCharCode(byte + 848); 
      } else if (byte == 168) {
        out.write('Ё');
      } else if (byte == 184) {
        out.write('ё');
      } else if (byte == 170) {
        out.write('Є');
      } else if (byte == 186) {
        out.write('є');
      } else if (byte == 175) {
        out.write('Ї');
      } else if (byte == 191) {
        out.write('ї');
      } else if (byte == 178) {
        out.write('І');
      } else if (byte == 179) {
        out.write('і');
      } else {
        out.writeCharCode(byte);
      }
    }
    return out.toString();
  }

  Future<Map<String, String>?> login(String login, String password) async {
    final url = Uri.parse('https://stat.maximuma.net/index.php');
    final initUrl = Uri.parse('https://stat.maximuma.net/index2.php');

    try {
      final initRes = await _client.get(initUrl, headers: {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36',
      });
      _cookie = initRes.headers['set-cookie']?.split(';').first;

      final request = http.Request('POST', url);
      request.headers.addAll({
        'Content-Type': 'application/x-www-form-urlencoded',
        'User-Agent': 'Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36',
        if (_cookie != null) 'Cookie': _cookie!,
      });

      request.bodyFields = {
        'login': login.trim(),
        'password': password.trim(),
        'action': 'actlogin',
      };

      final streamedResponse = await _client.send(request);
      final response = await http.Response.fromStream(streamedResponse);
      final decodedBody = _decodeWin1251(response.bodyBytes);

      if (decodedBody.contains('ІНФОРМАЦІЯ АБОНЕНТА') || decodedBody.contains('logout')) {
        return _parseData(decodedBody);
      } else {
        throw Exception("Невірний логін або пароль");
      }
    } catch (e) {
      rethrow;
    }
  }

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

    // Парсинг основної таблиці (Абонент, ID, Баланс)
    var rows = doc.querySelectorAll('table.sample tr');
    for (var row in rows) {
      var cells = row.querySelectorAll('td');
      if (cells.length < 2) continue;
      
      String label = cells[0].text.toLowerCase();
      
      // Читаємо значення з другої комірки
      if (label.contains('договору')) {
        data['id'] = cells[1].text.trim();
      }
      if (label.contains('піб')) {
        data['name'] = cells[1].text.trim();
      }
      if (label.contains('баланс')) {
        // ШУКАЄМО ТЕКСТ У ТЕГУ <b> (він там завжди, незалежно від кольору font)
        var boldText = cells[1].querySelector('b');
        data['balance'] = boldText != null ? boldText.text.trim() : cells[1].text.trim().split(' ').first;
      }
      if (label.contains('кредит до')) {
        data['expiry'] = cells[1].text.trim();
      }
    }

    // Парсинг таблиці сервісів (Тариф, Статус)
    var serviceTable = doc.querySelector('#services table');
    if (serviceTable != null) {
      var sRows = serviceTable.querySelectorAll('tr');
      if (sRows.length >= 3) {
        var cells = sRows[2].querySelectorAll('td');
        if (cells.length >= 4) {
          data['tariff'] = cells[0].text.trim();
          data['status'] = cells[3].text.trim();
        }
      }
    }
    return data;
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        padding: const EdgeInsets.all(35),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.network('https://stat.maximuma.net/img/logo.png', height: 80, errorBuilder: (c,e,s) => const Icon(Icons.wifi, size: 80)),
            const SizedBox(height: 50),
            TextField(controller: _l, decoration: const InputDecoration(labelText: "Логін (ID)", border: OutlineInputBorder())),
            const SizedBox(height: 15),
            TextField(controller: _p, obscureText: true, decoration: const InputDecoration(labelText: "Пароль", border: OutlineInputBorder())),
            const SizedBox(height: 30),
            if (_busy) const CircularProgressIndicator()
            else SizedBox(
              width: double.infinity, height: 55,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple, foregroundColor: Colors.white),
                onPressed: _submit, child: const Text("УВІЙТИ")
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  final Map<String, String> data;
  const HomePage({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    // Визначаємо колір балансу: якщо є мінус — червоний, інакше зелений
    bool isNegative = data['balance']!.contains('-');

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        title: Image.network('https://stat.maximuma.net/img/logo.png', height: 30),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _buildBalanceCard(isNegative),
          const SizedBox(height: 25),
          _buildInfoTile("Абонент", data['name']!, Icons.person),
          _buildInfoTile("Договір ID", data['id']!, Icons.tag),
          _buildInfoTile("Тариф", data['tariff']!, Icons.bolt, color: Colors.orange),
          _buildInfoTile("Статус", data['status']!, Icons.info_outline, 
            textColor: data['status']!.contains('активований') ? Colors.green : Colors.red),
        ],
      ),
    );
  }

  Widget _buildBalanceCard(bool isNegative) {
    return Container(
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Colors.deepPurple, Color(0xFF4527A0)]),
        borderRadius: BorderRadius.circular(25),
      ),
      child: Column(
        children: [
          const Text("Мій баланс", style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(data['balance']!, style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.bold)),
              const Text(" грн", style: TextStyle(color: Colors.orange, fontSize: 22, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoTile(String label, String value, IconData icon, {Color? color, Color? textColor}) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(icon, color: color ?? Colors.deepPurple),
        title: Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        subtitle: Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: textColor ?? Colors.black87)),
      ),
    );
  }
}
