import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../services/api_service.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    final messaging = FirebaseMessaging.instance;
    // 1. Request Permission
    NotificationSettings settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      print('User granted notification permission');
    }

    // 2. Local Notifications Setup
    const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
    );
    
    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse details) {
        // Handle tap
      },
    );

    // 3. Handle Foreground Messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      _showLocalNotification(message);
    });
  }

  static Future<void> _showLocalNotification(RemoteMessage message) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'admin_alerts',
      'Admin Alerts',
      channelDescription: 'Notifications for new collections',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
    );
    const NotificationDetails details = NotificationDetails(android: androidDetails);

    await _localNotifications.show(
      message.hashCode,
      message.notification?.title ?? 'New Update',
      message.notification?.body ?? 'An employee has updated a record.',
      details,
    );
  }

  static Future<void> registerDeviceToken(String userToken) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      print('DEBUG: Skipping FCM registration on this platform.');
      return;
    }

    try {
      print('DEBUG: Starting FCM token registration...');
      final messaging = FirebaseMessaging.instance;
      String? token = await messaging.getToken();
      print('DEBUG: FCM Token retrieved: $token');
      if (token == null) {
        print('DEBUG: Token is NULL, skipping registration');
        return;
      }


      print('DEBUG: Sending token to server: ${ApiService.baseUrl}/api/auth/register-fcm-token');
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/api/auth/register-fcm-token'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $userToken',
        },
        body: jsonEncode({'token': token}),
      );

      print('DEBUG: Server response: ${response.statusCode} - ${response.body}');
      if (response.statusCode == 200) {
        print('Device token registered successfully');
      }
    } catch (e) {
      print('Error registering device token: $e');
    }
  }
}
