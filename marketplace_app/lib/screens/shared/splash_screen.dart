import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_config.dart';
import '../../core/constants/app_text_styles.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.topBarDark,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  AppConfig.appName,
                  style: AppTextStyles.h1.copyWith(color: AppColors.white, fontSize: 34),
                ),
                const SizedBox(width: 6),
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: const BoxDecoration(color: AppColors.amber, shape: BoxShape.circle),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              AppConfig.appTagline,
              style: AppTextStyles.body.copyWith(color: AppColors.white.withValues(alpha: 0.75)),
            ),
            const SizedBox(height: 40),
            const CircularProgressIndicator(color: AppColors.amber),
          ],
        ),
      ),
    );
  }
}
