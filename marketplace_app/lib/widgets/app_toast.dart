import 'package:fluttertoast/fluttertoast.dart';
import '../core/constants/app_colors.dart';

/// Toast escuro arredondado padrao do app, usado para confirmacoes.
class AppToast {
  AppToast._();

  static void mostrar(String mensagem) {
    Fluttertoast.showToast(
      msg: mensagem,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
      backgroundColor: AppColors.topBarDark,
      textColor: AppColors.white,
      fontSize: 14,
    );
  }
}
