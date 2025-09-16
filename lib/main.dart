import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'home_page.dart';

const firebaseDbUrl = "https://logindb-c1c82-default-rtdb.firebaseio.com";

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LoginDB',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue, brightness: Brightness.light),
        useMaterial3: true,
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            minimumSize: const Size.fromHeight(48),
          ),
        ),
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasData && snapshot.data != null) {
          return HomePage();
        } else {
          return const AuthPage();
        }
      },
    );
  }
}

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  bool isLogin = true;
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  String error = '';
  bool loading = false;

  /// Save FCM Token to Realtime Database
  Future<void> saveFcmToken(String uid) async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;

    await messaging.requestPermission(alert: true, badge: true, sound: true);

    String? token = await messaging.getToken();
    if (token != null) {
      final db = FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: firebaseDbUrl,
      ).ref();
      await db.child('users').child(uid).update({'fcmToken': token});
    }

    // Handle token refresh
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      final db = FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: firebaseDbUrl,
      ).ref();
      await db.child('users').child(uid).update({'fcmToken': newToken});
    });
  }

  /// Email validation (only Gmail allowed)
  bool isValidGmail(String email) {
    return RegExp(r'^[a-zA-Z0-9._%+-]+@gmail\.com$').hasMatch(email.trim());
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() {
      loading = true;
      error = '';
    });

    // --- Input validation ---
    if (emailController.text.trim().isEmpty || passwordController.text.isEmpty) {
      setState(() {
        error = "Email and password cannot be empty.";
        loading = false;
      });
      return;
    }
    if (!isValidGmail(emailController.text.trim())) {
      setState(() {
        error = "Please enter a valid Gmail address (example@gmail.com).";
        loading = false;
      });
      return;
    }
    if (passwordController.text.length < 6) {
      setState(() {
        error = "Password must be at least 6 characters.";
        loading = false;
      });
      return;
    }

    try {
      if (isLogin) {
        final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: emailController.text.trim(),
          password: passwordController.text,
        );
        await saveFcmToken(credential.user!.uid);
      } else {
        final credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: emailController.text.trim(),
          password: passwordController.text,
        );
        final uid = credential.user!.uid;
        final db = FirebaseDatabase.instanceFor(
          app: Firebase.app(),
          databaseURL: firebaseDbUrl,
        ).ref();
        await db.child('users').child(uid).set({
          'email': emailController.text.trim(),
          'created_at': DateTime.now().toIso8601String(),
        });
        await saveFcmToken(uid);
      }
    } on FirebaseAuthException catch (e) {
      setState(() {
        error = e.message ?? '';
      });
    } catch (e) {
      setState(() {
        error = "An error occurred.";
      });
    }

    setState(() {
      loading = false;
    });
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      loading = true;
      error = '';
    });
    try {
      final googleSignIn = GoogleSignIn();
      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        setState(() => loading = false);
        return;
      }
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final result = await FirebaseAuth.instance.signInWithCredential(credential);
      final uid = result.user?.uid;
      final email = result.user?.email ?? '';

      if (uid != null) {
        final db = FirebaseDatabase.instanceFor(
          app: Firebase.app(),
          databaseURL: firebaseDbUrl,
        ).ref();
        final userSnap = await db.child('users').child(uid).get();
        if (!userSnap.exists) {
          await db.child('users').child(uid).set({
            'name': result.user?.displayName ?? '',
            'email': email,
            'created_at': DateTime.now().toIso8601String(),
          });
        }
        await saveFcmToken(uid);
      }
    } on FirebaseAuthException catch (e) {
      setState(() {
        error = e.message ?? 'Google Sign-In failed.';
      });
    } catch (e) {
      setState(() {
        error = "Google Sign-In failed.";
      });
    }
    setState(() {
      loading = false;
    });
  }

  Future<void> _forgotPassword() async {
    final email = emailController.text.trim();
    if (!isValidGmail(email)) {
      setState(() {
        error = "Enter a valid Gmail address for password reset.";
      });
      return;
    }
    setState(() {
      loading = true;
    });
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      setState(() {
        error = "Reset link sent! Check your Gmail inbox.";
      });
    } on FirebaseAuthException catch (e) {
      setState(() {
        error = e.message ?? "Reset failed.";
      });
    }
    setState(() {
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock, color: Colors.blue, size: 60),
              const SizedBox(height: 24),
              Text(
                isLogin ? "Log In" : "Register",
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.email_outlined),
                  labelText: "Email (Gmail only)",
                ),
                enabled: !loading,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.lock_outline),
                  labelText: "Password",
                ),
                enabled: !loading,
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: loading ? null : _forgotPassword,
                  child: const Text("Forgot password?"),
                ),
              ),
              const SizedBox(height: 12),
              if (error.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(error, style: const TextStyle(color: Colors.red)),
                ),
              ElevatedButton.icon(
                icon: isLogin ? const Icon(Icons.login) : const Icon(Icons.person_add_alt),
                label: Text(isLogin ? "Log In" : "Register"),
                onPressed: loading ? null : _submit,
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                icon: Image.asset('assets/google_logo.png', height: 24, width: 24),
                label: const Text("Continue with Google", style: TextStyle(color: Colors.black)),
                onPressed: loading ? null : _signInWithGoogle,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: loading ? null : () => setState(() => isLogin = !isLogin),
                child: Text(
                  isLogin
                      ? "Don't have an account? Register"
                      : "Already have an account? Log In",
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }
}
