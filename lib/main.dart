import 'dart:async';
import 'dart:ui';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:telephony/telephony.dart';
import 'package:permission_handler/permission_handler.dart';

// -----------------------------------------------------------------------------
// 1. CONFIGURATION
// -----------------------------------------------------------------------------
const String supabaseUrl = 'https://gavcnjpzeqhrrhcmnsbp.supabase.co';
const String supabaseKey = 'sb_publishable_yOqpThGaRtSnPHQBslCxrA_PaAYDDhz';

// -----------------------------------------------------------------------------
// 2. APP ENTRY POINT
// -----------------------------------------------------------------------------
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseKey);
  } catch (e) {
    // Already initialized
  }

  runZonedGuarded(() {
    runApp(const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: BootScreen(),
    ));
  }, (error, stack) {
    debugPrint("CRITICAL UI ERROR: $error");
  });
}

class BootScreen extends StatefulWidget {
  const BootScreen({super.key});

  @override
  State<BootScreen> createState() => _BootScreenState();
}

class _BootScreenState extends State<BootScreen> {
  String _status = "Starting System...";
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _initAppAndPermissions();
  }

  Future<void> _initAppAndPermissions() async {
    try {
      // 1. ASK ALL PERMISSIONS IMMEDIATELY AT STARTUP
      setState(() => _status = "Checking Permissions...");

      if (Platform.isAndroid) {
        await [
          Permission.notification,
          Permission.sms,
          Permission.phone,
          Permission.ignoreBatteryOptimizations, // Critical for background work
        ].request();
      }

      setState(() => _status = "Initializing Background Service...");
      await initializeService();

      final prefs = await SharedPreferences.getInstance();
      final String? cachedUID = prefs.getString('current_uid');

      if (mounted) {
        if (cachedUID != null && cachedUID.isNotEmpty) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen()));
        } else {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
        }
      }
    } catch (e) {
      setState(() {
        _hasError = true;
        _status = "Startup Failed:\n$e\n\nCheck Internet Connection.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _hasError ? Colors.red.shade900 : Colors.indigo,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(30.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(_hasError ? Icons.error_outline : Icons.rocket_launch, size: 80, color: Colors.white),
              const SizedBox(height: 20),
              Text(
                  _status,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)
              ),
              if (_hasError)
                Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _hasError = false;
                        _status = "Retrying...";
                      });
                      _initAppAndPermissions();
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.red),
                    child: const Text("Retry"),
                  ),
                )
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 3. LOGIN SCREEN
// -----------------------------------------------------------------------------
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _uidController = TextEditingController();
  bool _loading = false;

  void _login() async {
    final uid = _uidController.text.trim();
    if (uid.isEmpty) return;

    FocusScope.of(context).unfocus();
    setState(() => _loading = true);

    try {
      final data = await Supabase.instance.client
          .from('students')
          .select('uid')
          .eq('uid', uid)
          .maybeSingle();

      if (data == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("UID not found! Try 237106002")));
          setState(() => _loading = false);
        }
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('current_uid', uid);

      if (mounted) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen()));
      }
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Connection Error: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(30.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.school_rounded, size: 80, color: Colors.indigo),
              const SizedBox(height: 20),
              const Text("University Attendance", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 30),
              TextField(
                controller: _uidController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: "Enter Student UID",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  prefixIcon: const Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
                  onPressed: _loading ? null : _login,
                  child: _loading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text("LOGIN"),
                ),
              ),
              const SizedBox(height: 15),
              TextButton(
                  onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen())),
                  child: const Text("Teacher Access (Skip)")
              )
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 4. HOME SCREEN
// -----------------------------------------------------------------------------
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Dashboard"),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: "Logout",
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove('current_uid');

              final service = FlutterBackgroundService();
              if (await service.isRunning()) {
                service.invoke("stopService");
              }

              if (context.mounted) {
                Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                        (route) => false
                );
              }
            },
          )
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildMenuButton(
                context,
                "STUDENT MODULE",
                Icons.shield_moon,
                Colors.blueAccent,
                    () async {
                  final service = FlutterBackgroundService();
                  if (!await service.isRunning()) {
                    await service.startService();
                  }

                  if (context.mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => const StudentDashboard()));
                }
            ),
            const SizedBox(height: 20),
            _buildMenuButton(
                context,
                "TEACHER DASHBOARD",
                Icons.admin_panel_settings,
                Colors.orange,
                    () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TeacherDashboard()))
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuButton(BuildContext context, String label, IconData icon, Color color, VoidCallback onPressed) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          fixedSize: const Size(300, 70),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
      ),
      icon: Icon(icon, size: 28),
      label: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      onPressed: onPressed,
    );
  }
}

// -----------------------------------------------------------------------------
// 5. STUDENT DASHBOARD
// -----------------------------------------------------------------------------
class StudentDashboard extends StatefulWidget {
  const StudentDashboard({super.key});

  @override
  State<StudentDashboard> createState() => _StudentDashboardState();
}

class _StudentDashboardState extends State<StudentDashboard> {
  final _supabase = Supabase.instance.client;
  String? myUID;

  @override
  void initState() {
    super.initState();
    _loadUID();
  }

  _loadUID() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => myUID = prefs.getString('current_uid') ?? '237106002');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("My Attendance"), backgroundColor: Colors.blueAccent, foregroundColor: Colors.white),
      body: myUID == null
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<List<Map<String, dynamic>>>(
        stream: _supabase.from('students').stream(primaryKey: ['uid']).eq('uid', myUID!),
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text("Loading status..."));
          }

          final student = snapshot.data![0];
          final isAbsent = student['status'] == 'Absent';

          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isAbsent ? Icons.cancel : Icons.check_circle,
                  size: 140,
                  color: isAbsent ? Colors.red : Colors.green,
                ),
                const SizedBox(height: 20),
                Text(
                  isAbsent ? "MARKED ABSENT" : "PRESENT",
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: isAbsent ? Colors.red : Colors.green),
                ),
                const SizedBox(height: 10),
                Text("Name: ${student['name']}", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
                Text("UID: ${student['uid']}", style: const TextStyle(color: Colors.grey)),
                const SizedBox(height: 50),
                const Chip(avatar: Icon(Icons.bolt, color: Colors.green), label: Text("Background Monitor Active"))
              ],
            ),
          );
        },
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 6. TEACHER DASHBOARD
// -----------------------------------------------------------------------------
class TeacherDashboard extends StatelessWidget {
  const TeacherDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final supabase = Supabase.instance.client;

    return Scaffold(
      appBar: AppBar(title: const Text("Class List"), backgroundColor: Colors.orange, foregroundColor: Colors.white),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: supabase.from('students').stream(primaryKey: ['uid']).order('name', ascending: true),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          final students = snapshot.data!;
          return ListView.builder(
            itemCount: students.length,
            itemBuilder: (context, index) {
              final student = students[index];
              final isAbsent = student['status'] == 'Absent';

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isAbsent ? Colors.red : Colors.green,
                    child: Text(student['name'][0], style: const TextStyle(color: Colors.white)),
                  ),
                  title: Text(student['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("UID: ${student['uid']}"),
                      Text(
                        isAbsent ? "Status: ABSENT ❌" : "Status: Present ✅",
                        style: TextStyle(
                          color: isAbsent ? Colors.red : Colors.green,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  trailing: isAbsent
                      ? ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                    onPressed: () async {
                      // RESET ALERT: We set sms_sent to false so if they are marked absent again later, it triggers.
                      await supabase.from('students').update({
                        'status': 'Present',
                        'sms_sent': false
                      }).eq('uid', student['uid']);
                    },
                    child: const Text("Undo"),
                  )
                      : ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                    onPressed: () async {
                      // TRIGGER ALERT: We set sms_sent to false so the background service detects it as "New"
                      await supabase.from('students').update({
                        'status': 'Absent',
                        'sms_sent': false
                      }).eq('uid', student['uid']);

                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Marked ${student['name']} Absent")));
                      }
                    },
                    child: const Text("Mark Absent"),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 7. BACKGROUND SERVICE CONFIGURATION (HIDDEN SERVICE MODE)
// -----------------------------------------------------------------------------
Future<void> initializeService() async {
  final service = FlutterBackgroundService();
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  // A. CLEANUP OLD CHANNELS
  final androidPlugin = flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  if (androidPlugin != null) {
    await androidPlugin.deleteNotificationChannel('attendance_alert_channel_v5');
    await androidPlugin.deleteNotificationChannel('attendance_service_channel');
  }

  // B. CREATE NEW CHANNELS

  // 1. SERVICE CHANNEL (HIDDEN / MINIMIZED)
  // We use Importance.min so it doesn't show an icon in the status bar
  const AndroidNotificationChannel serviceChannel = AndroidNotificationChannel(
    'attendance_service_channel_hidden',
    'Background Service',
    description: 'Keeps the app running in background.',
    importance: Importance.min, // <--- THIS HIDES THE ICON & MINIMIZES IT
    showBadge: false,
  );

  // 2. ALERT CHANNEL (LOUD / POP-UP)
  const AndroidNotificationChannel alertChannel = AndroidNotificationChannel(
    'attendance_alert_channel_final',
    'Attendance Alerts',
    description: 'Heads-up notifications for Absent Status',
    importance: Importance.max,
    playSound: true,
  );

  await androidPlugin?.createNotificationChannel(serviceChannel);
  await androidPlugin?.createNotificationChannel(alertChannel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      isForegroundMode: true,

      // USE THE HIDDEN CHANNEL HERE
      notificationChannelId: 'attendance_service_channel_hidden',

      // MINIMAL TEXT (Android requires *something*, but we keep it short)
      initialNotificationTitle: 'App Running',
      initialNotificationContent: '',

      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(),
  );
}

// -----------------------------------------------------------------------------
// 8. BACKGROUND TASK ISOLATE (PROFESSIONAL + RELIABLE)
// -----------------------------------------------------------------------------
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  try {
    await Supabase.initialize(
        url: 'https://gavcnjpzeqhrrhcmnsbp.supabase.co',
        anonKey: 'sb_publishable_yOqpThGaRtSnPHQBslCxrA_PaAYDDhz'
    );
  } catch(e) {
    // Already init
  }

  final supabase = Supabase.instance.client;
  final Telephony telephony = Telephony.instance;
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  // Initialize Notifications for Background Thread
  const AndroidInitializationSettings initializationSettingsAndroid =
  AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initializationSettings =
  InitializationSettings(android: initializationSettingsAndroid);

  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  print("🚀 [Background] Service Started - Professional Mode");

  Timer.periodic(const Duration(seconds: 10), (timer) async {
    if (service is AndroidServiceInstance) {
      if (!await service.isForegroundService()) {
        timer.cancel();
        return;
      }
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final myUID = prefs.getString('current_uid');

      if (myUID == null) return;

      final response = await supabase
          .from('students')
          .select('uid, name, phone, status')
          .eq('status', 'Absent')
          .eq('sms_sent', false) // Only pick up "Fresh" absent cases
          .eq('uid', myUID);

      final List<dynamic> dataList = response as List<dynamic>;

      if (dataList.isNotEmpty) {
        for (var student in dataList) {
          String uid = student['uid'];
          String name = student['name'];
          String phone = student['phone'];
          String status = student['status'];

          print("⚡ DETECTED: $status for $name");

          // 1. PROFESSIONAL NOTIFICATION STYLE (Big Text + Red Color)
          final BigTextStyleInformation bigTextStyleInformation =
          BigTextStyleInformation(
            'You have been marked ABSENT by the University System.\n\nStudent: $name\nUID: $uid\nDate: ${DateTime.now().toString().split(' ')[0]}',
            htmlFormatBigText: true,
            contentTitle: '⚠️ Attendance Alert: ABSENT',
            htmlFormatContentTitle: true,
            summaryText: 'University Attendance System',
            htmlFormatSummaryText: true,
          );

          await flutterLocalNotificationsPlugin.show(
            DateTime.now().millisecond,
            'Attendance Alert',
            'You have been marked Absent.',
            NotificationDetails(
              android: AndroidNotificationDetails(
                'attendance_alert_channel_final', // MUST MATCH THE NEW ID
                'Attendance Alerts',
                importance: Importance.max,
                priority: Priority.high,
                showWhen: true,
                fullScreenIntent: true,
                color: const Color(0xFFFF0000),
                enableLights: true,
                ledColor: const Color(0xFFFF0000),
                ledOnMs: 1000,
                ledOffMs: 500,
                styleInformation: bigTextStyleInformation,
              ),
            ),
          );

          // 2. SEND SMS
          try {
            await telephony.sendSms(
              to: phone,
              message: "URGENT: $name ($uid) marked ABSENT on ${DateTime.now().toString().split(' ')[0]}. Contact Admin if this is an error.",
            );
          } catch (e) {
            print("SMS Failed: $e");
          }

          // 3. UPDATE DATABASE (Marks as sent so it doesn't loop, until Reset by Teacher)
          await supabase.from('students').update({'sms_sent': true}).eq('uid', uid);
        }
      }
    } catch (e) {
      print("❌ [Background Error] $e");
    }
  });
}