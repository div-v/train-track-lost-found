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
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0B57D0),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFE0E3E7)),
          ),
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
  final formKey = GlobalKey<FormState>();
  String error = '';
  bool loading = false;

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

    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      final db = FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: firebaseDbUrl,
      ).ref();
      await db.child('users').child(uid).update({'fcmToken': newToken});
    });
  }

  bool isValidGmailStrict(String emailRaw) {
    final email = emailRaw.trim().toLowerCase();
    if (!email.endsWith('@gmail.com')) return false;
    final parts = email.split('@');
    if (parts.length != 2) return false;
    final user = parts.first;
    if (user.length < 3 || user.length > 30) return false;
    if (!RegExp(r'^[a-z]').hasMatch(user)) return false;
    if (!RegExp(r'^[a-z0-9._]+$').hasMatch(user)) return false;
    if (user.contains('..')) return false;
    if (user.startsWith('.') || user.endsWith('.')) return false;
    if (!RegExp(r'[a-z]').hasMatch(user)) return false;
    if (RegExp(r'^[0-9]+$').hasMatch(user)) return false;
    return true;
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!formKey.currentState!.validate()) return;

    setState(() {
      loading = true;
      error = '';
    });

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
    } catch (_) {
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
      final googleSignIn = GoogleSignIn(
        scopes: const ['email', 'profile'],
      );

      try {
        final current = await googleSignIn.signInSilently();
        if (current != null) {
          await googleSignIn.disconnect();
        }
        await googleSignIn.signOut();
      } catch (_) {}

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
    } catch (_) {
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
    if (!isValidGmailStrict(email)) {
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
        error = "Reset link sent! Check the Gmail inbox.";
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
    final cs = Theme.of(context).colorScheme;

    // Responsive top spacing
    final h = MediaQuery.of(context).size.height;
    final topGap = (h * 0.06).clamp(16.0, 40.0); // above logo
    final belowLogoGap = 10.0;                    // logo -> caption
    final captionToTitleGap = 14.0;               // caption -> title

    return Scaffold(
      body: Stack(
        children: [
          const _WavyBlueBackground(),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(height: topGap),

                      // Logo
                      CircleAvatar(
                        radius: 38,
                        backgroundColor: Colors.white,
                        child: ClipOval(
                          child: Image.asset(
                            'assets/app_logo.png',
                            width: 70,
                            height: 70,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),

                      SizedBox(height: belowLogoGap),

                      // Two-line centered caption exactly as requested
                      Text(
                        'By\nIndian Railways',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.black54,
                              fontWeight: FontWeight.w600,
                              height: 1.2, // slightly tighter line spacing
                              letterSpacing: 0.2,
                            ),
                      ),

                      SizedBox(height: captionToTitleGap),

                      // Title
                      Text(
                        isLogin ? "Log In" : "Register",
                        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                      ),

                      const SizedBox(height: 14),

                      // Form
                      Form(
                        key: formKey,
                        child: Column(
                          children: [
                            TextFormField(
                              controller: emailController,
                              keyboardType: TextInputType.emailAddress,
                              decoration: const InputDecoration(
                                prefixIcon: Icon(Icons.email_outlined),
                                labelText: "Email (Gmail only)",
                              ),
                              enabled: !loading,
                              autovalidateMode: AutovalidateMode.onUserInteraction,
                              validator: (v) {
                                final value = v?.trim() ?? '';
                                if (value.isEmpty) return 'Email is required';
                                if (!isValidGmailStrict(value)) {
                                  return 'Use a valid Gmail (letters first, 3–30 chars, no only digits)';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: passwordController,
                              obscureText: true,
                              decoration: const InputDecoration(
                                prefixIcon: Icon(Icons.lock_outline),
                                labelText: "Password",
                              ),
                              enabled: !loading,
                              autovalidateMode: AutovalidateMode.onUserInteraction,
                              validator: (v) {
                                final p = v ?? '';
                                if (p.isEmpty) return 'Password is required';
                                if (p.length < 6) return 'At least 6 characters';
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),

                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: loading ? null : _forgotPassword,
                          child: const Text("Forgot password?"),
                        ),
                      ),

                      const SizedBox(height: 8),

                      if (error.isNotEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.08),
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
                          side: const BorderSide(color: Color(0xFFE0E3E7)),
                        ),
                      ),

                      const SizedBox(height: 12),

                      TextButton(
                        onPressed: loading ? null : () => setState(() => isLogin = !isLogin),
                        child: Text(
                          isLogin ? "Don't have an account? Register" : "Already have an account? Log In",
                          style: TextStyle(color: cs.primary),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
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

// Decorative light‑blue wavy background
class _WavyBlueBackground extends StatelessWidget {
  const _WavyBlueBackground();

  @override
  Widget build(BuildContext context) {
    final top = Theme.of(context).colorScheme.primary.withOpacity(.10);
    final mid = const Color(0xFFE8F0FE);
    final bottom = Colors.white;

    return SizedBox.expand(
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [top, mid, bottom],
                stops: const [0.0, 0.35, 1.0],
              ),
            ),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: ClipPath(
              clipper: _WaveClipper1(),
              child: Container(
                height: 260,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [mid, top],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: ClipPath(
              clipper: _WaveClipper2(),
              child: Container(
                height: 220,
                color: Colors.white.withOpacity(.4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WaveClipper1 extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path()..lineTo(0, size.height - 60);
    path.quadraticBezierTo(size.width * .25, size.height - 10, size.width * .5, size.height - 40);
    path.quadraticBezierTo(size.width * .75, size.height - 80, size.width, size.height - 30);
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _WaveClipper2 extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path()..lineTo(0, size.height - 80);
    path.quadraticBezierTo(size.width * .2, size.height - 20, size.width * .55, size.height - 60);
    path.quadraticBezierTo(size.width * .8, size.height - 90, size.width, size.height - 50);
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
