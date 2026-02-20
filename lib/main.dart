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

  // Декодування Win-1251 (кирилиця)
  String _decodeResponse(http.Response response) {
    try {
      return latin1.decode(response.bodyBytes);
    } catch (_) {
      return response.body;
    }
  }

  Future<Map<String, String>?> login(String login, String password) async {
    final url = Uri.parse('https://stat.maximuma.net/index.php');
    final initUrl = Uri.parse('https://stat.maximuma.net/index2.php');

    try {
      // КРОК 1: Отримання куки
      final initRes = await _client.get(initUrl, headers: {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36',
      });
      _cookie = initRes.headers['set-cookie']?.split(';').first;

      // КРОК 2: Авторизація
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
      final decodedBody = _decodeResponse(response);

      // Перевірка на успішний вхід
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

    // 1. Парсинг основної таблиці (використовуємо селектори під ваш HTML)
    var rows = doc.querySelectorAll('table.sample tr');
    for (var row in rows) {
      var cells = row.querySelectorAll('td');
      if (cells.length < 2) continue;
      
      String label = cells[0].text.toLowerCase();
      String value = cells[1].text.trim();

      if (label.contains('договору')) data['id'] = value;
      if (label.contains('піб')) data['name'] = value;
      if (label.contains('баланс')) {
        // Отримуємо значення з тегу <b> всередині комірки (там лежить число)
        var balanceBold = cells[1].querySelector('b');
        data['balance'] = balanceBold != null ? balanceBold.text.trim() : value.split(' ').first;
      }
      if (label.contains('кредит до')) data['expiry'] = value;
    }

    // 2. Парсинг сервісів (Тариф та Статус)
    var servicesTable = doc.querySelector('#services table');
    if (servicesTable != null) {
      var sRows = servicesTable.querySelectorAll('tr');
      if (sRows.length >= 3) {
        var dataRow = sRows[2]; // Третій рядок містить поточний тариф
        var cells = dataRow.querySelectorAll('td');
        if (cells.length >= 4) {
          data['tariff'] = cells[0].text.trim();
          data['status'] = cells[3].text.trim();
          if (data['expiry'] == '---') data['expiry'] = cells[2].text.trim();
        }
      }
    }

    return data;
  }
}

// --- LoginPage ---

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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceAll("Exception:", "")),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(35),
          child: Column(children: [
            // ЛОГОТИП З САЙТУ
            Image.network(
              'https://stat.maximuma.net/img/logo.png',
              height: 70,
              errorBuilder: (c, e, s) => const Icon(Icons.wifi, size: 70, color: Colors.deepPurple),
            ),
            const SizedBox(height: 10),
            const Text("ОСОБИСТИЙ КАБІНЕТ", 
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orange, letterSpacing: 3)),
            const SizedBox(height: 50),
            _buildField(_l, "ID або Логін", Icons.person_outline),
            const SizedBox(height: 15),
            _buildField(_p, "Пароль", Icons.lock_outline, obscure: true),
            const SizedBox(height: 35),
            if (_busy) const CircularProgressIndicator()
            else SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                onPressed: _submit,
                child: const Text("УВІЙТИ", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildField(TextEditingController ctrl, String label, IconData icon, {bool obscure = false}) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Colors.orange),
        filled: true,
        fillColor: Colors.deepPurple.withOpacity(0.05),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
      ),
    );
  }
}

// --- HomePage ---

class HomePage extends StatelessWidget {
  final Map<String, String> data;
  const HomePage({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    bool isBlocked = data['status']!.toLowerCase().contains('заблоковано');

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        title: Image.network('https://stat.maximuma.net/img/logo.png', height: 30),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _buildBalanceCard(isBlocked),
          const SizedBox(height: 25),
          _buildInfoTile("Абонент", data['name']!, Icons.person),
          _buildInfoTile("Договір", data['id']!, Icons.tag),
          _buildInfoTile("Тариф", data['tariff']!, Icons.bolt, color: Colors.orange),
          _buildInfoTile("Статус", data['status']!, Icons.info_outline, 
              color: isBlocked ? Colors.red : Colors.green),
          _buildInfoTile("Діє до", data['expiry']!, Icons.calendar_today),
        ],
      ),
    );
  }

  Widget _buildBalanceCard(bool blocked) {
    return Container(
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Colors.deepPurple, Color(0xFF4527A0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(25),
        boxShadow: [BoxShadow(color: Colors.deepPurple.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 8))],
      ),
      child: Column(
        children: [
          const Text("До сплати", style: TextStyle(color: Colors.white70, fontSize: 14)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(data['balance']!, style: const TextStyle(color: Colors.white, fontSize: 45, fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              const Text("грн", style: TextStyle(color: Colors.orange, fontSize: 20, fontWeight: FontWeight.bold)),
            ],
          ),
          if (blocked)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text("Доступ обмежено", style: TextStyle(color: Colors.orange[200], fontSize: 12, fontWeight: FontWeight.w500)),
            ),
        ],
      ),
    );
  }

  Widget _buildInfoTile(String label, String value, IconData icon, {Color color = Colors.deepPurple}) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        subtitle: Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87)),
      ),
    );
  }
}
