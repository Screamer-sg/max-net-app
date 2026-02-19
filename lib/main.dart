import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' show parse;
import 'package:url_launcher/url_launcher.dart';

void main() => runApp(const MaxNetApp());

class MaxNetApp extends StatelessWidget {
  const MaxNetApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFF0055A4)),
      home: const LoginPage(),
    );
  }
}

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  // Використовуємо один клієнт для всіх запитів, щоб підтримувати сесію
  final _client = http.Client();
  String? _cookie;

  Future<Map<String, String>?> login(String login, String password) async {
    final url = Uri.parse('https://stat.maximuma.net/index.php');
    final initUrl = Uri.parse('https://stat.maximuma.net/index2.php');

    try {
      // 1. ПЕРШИЙ КРОК: Заходимо на сторінку входу (GET)
      final initRes = await _client.get(initUrl, headers: {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36',
      });
      
      // Зберігаємо куку, яку видав сервер
      _cookie = initRes.headers['set-cookie']?.split(';').first;

      // 2. ДРУГИЙ КРОК: Відправляємо дані (POST)
      // Ми використовуємо Request вручну, щоб контролювати кожен заголовок
      final request = http.Request('POST', url);
      
      request.headers.addAll({
        'Content-Type': 'application/x-www-form-urlencoded',
        'User-Agent': 'Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36',
        'Referer': 'https://stat.maximuma.net/index2.php',
        'Origin': 'https://stat.maximuma.net',
        if (_cookie != null) 'Cookie': _cookie!,
      });

      // Порядок полів як у вашій HTML формі: login -> password -> action
      request.bodyFields = {
        'login': login.trim(),
        'password': password.trim(),
        'action': 'actlogin',
      };

      final streamedResponse = await _client.send(request);
      final response = await http.Response.fromStream(streamedResponse);

      // 3. ТРЕТІЙ КРОК: Аналіз результату
      // Перевіряємо наявність ID або ключового слова успіху
      if (response.body.contains('ІНФОРМАЦІЯ АБОНЕНТА') || response.body.contains(login.trim())) {
        return _parseData(response.body);
      } else {
        // Якщо сервер повернув форму входу (index2.php), значить дані не прийняті
        String snippet = response.body.length > 100 ? response.body.substring(0, 100) : response.body;
        throw Exception("Сервер відхилив запит. Фрагмент відповіді: $snippet");
      }
    } catch (e) {
      rethrow;
    }
  }

  Map<String, String> _parseData(String html) {
    var doc = parse(html);
    var balance = "0.00";
    var id = "---";

    // Шукаємо баланс (він часто в тегу <font color='red'>)
    var redFont = doc.querySelector("font[color='red'] b") ?? doc.querySelector("b font[color='red']");
    if (redFont != null) {
      balance = redFont.text.trim();
    } else {
      // Альтернативний пошук у таблиці
      var rows = doc.querySelectorAll('tr');
      for (var row in rows) {
        if (row.text.contains('Поточний баланс')) {
          balance = row.querySelectorAll('td').last.text.trim();
        }
      }
    }

    // Шукаємо ID договору
    for (var row in doc.querySelectorAll('tr')) {
      if (row.text.contains('№ договору')) {
        id = row.querySelectorAll('td').last.text.trim();
      }
    }
    return {'balance': balance, 'id': id};
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
      if (mounted) {
        setState(() => _busy = false);
        if (res != null) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (c) => HomePage(data: res)));
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showDialog(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text("Помилка"),
            content: Text(e.toString().replaceAll("Exception:", "")),
            actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text("OK"))],
          ),
        );
      }
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

class HomePage extends StatelessWidget {
  final Map<String, String> data;
  const HomePage({super.key, required this.data});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Кабінет")),
      body: Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text("ID: ${data['id']}", style: const TextStyle(fontSize: 18)),
          Text("${data['balance']} грн", style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.blue)),
        ],
      )),
    );
  }
}
