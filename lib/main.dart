import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:intl/intl.dart';
import 'package:telephony/telephony.dart';

void main() {
  runApp(const AttendanceApp());
}

class AttendanceApp extends StatelessWidget {
  const AttendanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.deepPurple, useMaterial3: true),
      home: const DashboardScreen(),
    );
  }
}

// ---------------------------------------------------------------------------
// 1. DATABASE
// ---------------------------------------------------------------------------
class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;
  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('uni_attendance_silent_v2.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, filePath);
    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future _createDB(Database db, int version) async {
    await db.execute('CREATE TABLE students (id INTEGER PRIMARY KEY AUTOINCREMENT, uid TEXT, name TEXT, email TEXT, phone TEXT)');

    // YOUR REAL STUDENTS
    List<Map<String, String>> data = [
      {'uid': '237106002', 'name': 'Akashdeep Singh', 'phone': '9053442600'},
      {'uid': '237106007', 'name': 'Diljeet Singh', 'phone': '7888490481'},
      {'uid': '237106009', 'name': 'Gurinderpal Singh', 'phone': '8427018050'},
      {'uid': '237106027', 'name': 'Prashant Singh', 'phone': '7009451091'},
      {'uid': '237106034', 'name': 'Supandeep Singh', 'phone': '9915045799'},
      {'uid': '237106001', 'name': 'Malik Mzamil', 'phone number': '7889842002'},
    ];

    for (var s in data) {
      await db.insert('students', {`
        'uid': s['uid'], 'name': s['name'], 'phone': s['phone'],
        'email': 'YOUR_REAL_EMAIL@gmail.com' // Don't forget to change this!
      });
    }
  }
}

// ---------------------------------------------------------------------------
// 2. SILENT NOTIFICATION SERVICE
// ---------------------------------------------------------------------------
class NotificationService {
  static const String myEmail = 'YOUR_EMAIL@gmail.com';
  static const String myAppPassword = 'YOUR_APP_PASSWORD';
  static final Telephony telephony = Telephony.instance;

  static Future<void> sendSilentSMS(String phone, String name) async {
    try {
      // Direct SMS without opening app
      await telephony.sendSms(
        to: phone,
        message: "ALERT: $name is absent today.",
        isMultipart: true,
      );
      print("✅ SMS sent silently to $name");
    } catch (e) {
      print("❌ SMS Error: $e");
    }
  }

  static Future<void> sendSilentEmail(String recipient, String name) async {
    final smtpServer = gmail(myEmail, myAppPassword);
    final message = Message()
      ..from = Address(myEmail, 'Attendance Bot')
      ..recipients.add(recipient)
      ..subject = 'Attendance Alert'
      ..text = '$name is absent today.';
    try { await send(message, smtpServer); } catch (e) { print(e); }
  }
}

// ---------------------------------------------------------------------------
// 3. UI SCREEN
// ---------------------------------------------------------------------------
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<Map<String, dynamic>> students = [];
  Map<int, bool> status = {};
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  _load() async {
    final db = await DatabaseHelper.instance.database;
    final data = await db.query('students');
    setState(() {
      students = data;
      for (var s in students) { status[s['id']] = true; }
      loading = false;
    });
  }

  _submit() async {
    // Check SMS Permission
    bool? permissionsGranted = await NotificationService.telephony.requestPhoneAndSmsPermissions;
    if (permissionsGranted != true) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("SMS Permission Denied!")));
      return;
    }

    int count = 0;
    for (var s in students) {
      if (status[s['id']] == false) {
        count++;
        // FIRE AND FORGET (Silent)
        NotificationService.sendSilentSMS(s['phone'], s['name']);
        NotificationService.sendSilentEmail(s['email'], s['name']);
      }
    }
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Sent!"),
        content: Text("Automatically notified $count students via SMS and Email."),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("OK"))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Silent Auto Attendance")),
      body: loading ? const Center(child: CircularProgressIndicator()) : Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: students.length,
              itemBuilder: (c, i) => ListTile(
                title: Text(students[i]['name']),
                subtitle: Text(students[i]['phone']),
                trailing: Switch(
                  value: status[students[i]['id']]!,
                  activeColor: Colors.green, inactiveThumbColor: Colors.red,
                  onChanged: (v) => setState(() => status[students[i]['id']] = v),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              onPressed: _submit,
              child: const Text("SUBMIT & AUTO-SEND"),
            ),
          )
        ],
      ),
    );
  }
}