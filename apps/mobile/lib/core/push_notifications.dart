import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../firebase_options.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  debugPrint('Received background FCM message: ${message.messageId ?? 'no id'}');
}

class PushNotifications {
  PushNotifications._();

  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static bool _initialized = false;
  static String? _registrationToken;

  static String? get registrationToken => _registrationToken;

  static void registerBackgroundHandler() {
    if (!kIsWeb) {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    }
  }

  static Future<void> initialize() async {
    if (_initialized || kIsWeb) return;
    _initialized = true;

    try {
      await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (defaultTargetPlatform == TargetPlatform.iOS) {
        await _messaging.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
      }

      _registrationToken = await _messaging.getToken();
      _messaging.onTokenRefresh.listen((token) {
        _registrationToken = token;
      });

      FirebaseMessaging.onMessage.listen((message) {
        debugPrint('Received foreground FCM message: ${message.messageId ?? 'no id'}');
      });
      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        debugPrint('Opened from FCM message: ${message.messageId ?? 'no id'}');
      });

      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        debugPrint('Started from FCM message: ${initialMessage.messageId ?? 'no id'}');
      }
    } catch (error, stackTrace) {
      _initialized = false;
      debugPrint('Firebase Messaging initialization failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }
}
