import 'dart:math';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

class OTPService {
  /// Sends a 6-digit OTP to the given email.
  /// Returns the OTP if sent successfully, or an empty string if failed.
  static Future<String> sendOtpToEmail(String email) async {
    // Generate 6-digit OTP
    final otp = (Random().nextInt(900000) + 100000).toString();
    print("[OTPService] Generated OTP: $otp for $email");

    // === Gmail SMTP setup ===
    // Replace with your Gmail & App Password
    const gmailUser = "prowidget09@gmail.com";
    const gmailAppPassword = "mwiy zjoi bcyg jujt";

    final smtpServer = gmail(gmailUser, gmailAppPassword);

    // Create the message
    final message = Message()
      ..from = Address(gmailUser, 'Aexor Security')
      ..recipients.add(email)
      ..subject = 'Your Aexor Verification Code'
      ..text = 'Your OTP Code is: $otp\n\nUse this code to verify your login.';

    try {
      final sendReport = await send(message, smtpServer);
      print("[OTPService] OTP sent successfully: $otp");
      print("[OTPService] Send report: $sendReport");
      return otp;
    } on MailerException catch (e) {
      print("[OTPService] OTP sending failed:");
      for (var p in e.problems) {
        print(' - ${p.code}: ${p.msg}');
      }
      return "";
    } catch (e) {
      print("[OTPService] Unexpected error sending OTP: $e");
      return "";
    }
  }
}
