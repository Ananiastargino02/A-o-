import 'package:firebase_auth/firebase_auth.dart';

/// Login por telefone/SMS via Firebase Auth.
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Inicia a verificacao por SMS. [onCodeSent] recebe o verificationId
  /// necessario para [confirmCode]. [onAutoVerified] e chamado se o Android
  /// conseguir auto-detectar o SMS.
  Future<void> enviarCodigoSms({
    required String telefoneE164,
    required void Function(String verificationId) onCodeSent,
    required void Function(User user) onAutoVerified,
    required void Function(String erro) onError,
  }) async {
    await _auth.verifyPhoneNumber(
      phoneNumber: telefoneE164,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (credential) async {
        final result = await _auth.signInWithCredential(credential);
        if (result.user != null) onAutoVerified(result.user!);
      },
      verificationFailed: (e) => onError(e.message ?? 'Falha ao enviar SMS.'),
      codeSent: (verificationId, resendToken) => onCodeSent(verificationId),
      codeAutoRetrievalTimeout: (verificationId) {},
    );
  }

  Future<User?> confirmarCodigo({
    required String verificationId,
    required String smsCode,
  }) async {
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );
    final result = await _auth.signInWithCredential(credential);
    return result.user;
  }

  Future<void> logout() => _auth.signOut();
}
