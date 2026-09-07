import 'package:flutter/material.dart';

/// PayFlex design tokens — sampled directly from the approved logo.
/// Every screen and widget references these. No inline hex or magic numbers
/// anywhere in widget code.
class AppColors {
  // Brand gradient (logo's blue→green)
  static const Color primaryBlue = Color(0xFF0B2FBE);
  static const Color primaryGreen = Color(0xFF1FD65F);
  static const Color gradientStart = primaryBlue;
  static const Color gradientEnd = primaryGreen;

  // Base surfaces (logo's dark QR background → flat navy)
  static const Color darkNavy = Color(0xFF0A1330);
  static const Color darkSurface = Color(0xFF11183A);
  static const Color darkSurfaceAlt = Color(0xFF161E40);

  // Light mode
  static const Color lightBg = Color(0xFFF7F7F5);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceAlt = Color(0xFFF0F0EC);

  // Text
  static const Color textWhite = Color(0xFFFFFFFF);
  static const Color textOffWhite = Color(0xFFECEDF2);
  static const Color textDark = Color(0xFF1A1F2E);
  static const Color textMutedDark = Color(0xFF8A93A8);
  static const Color textMutedLight = Color(0xFF5C6378);

  // Status
  static const Color success = Color(0xFF1FD65F);
  static const Color warning = Color(0xFFF5A623);
  static const Color error = Color(0xFFE5484D);

  // Brand gradient as a Paint object for fills
  static const LinearGradient brandGradient = LinearGradient(
    colors: [primaryBlue, primaryGreen],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class AppRadius {
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
}

class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

class AppTypography {
  static const String displayFamily = 'Inter';
  static const String bodyFamily = 'Inter';
  static const String monoFamily = 'JetBrains Mono';

  static const TextStyle balanceDisplay = TextStyle(
    fontFamily: displayFamily,
    fontSize: 56,
    fontWeight: FontWeight.w700,
    letterSpacing: -1.5,
    height: 1.0,
  );

  static const TextStyle amountLarge = TextStyle(
    fontFamily: displayFamily,
    fontSize: 38,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    height: 1.05,
  );

  static const TextStyle heading1 = TextStyle(
    fontFamily: displayFamily,
    fontSize: 24,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
    height: 1.2,
  );

  static const TextStyle heading2 = TextStyle(
    fontFamily: displayFamily,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    height: 1.25,
  );

  static const TextStyle body = TextStyle(
    fontFamily: bodyFamily,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.1,
    height: 1.45,
  );

  static const TextStyle bodySmall = TextStyle(
    fontFamily: bodyFamily,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.1,
    height: 1.4,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: bodyFamily,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.2,
    height: 1.4,
    color: AppColors.textMutedDark,
  );

  static const TextStyle mono = TextStyle(
    fontFamily: monoFamily,
    fontSize: 14,
    fontWeight: FontWeight.w500,
  );
}

class AppMotion {
  // Durations (ms)
  static const int fast = 150;
  static const int normal = 250;
  static const int slow = 400;

  // Curves — ease-out physically plausible
  static const Curve easeOut = Curves.easeOut;
  static const Curve easeOutExpo = Curves.easeOutExpo;
  static const Curve easeInOut = Curves.easeInOut;

  // Shared transition duration
  static const Duration pageTransition = Duration(milliseconds: 300);
}

/// Global app theme factory — dark default for wallet/splash,
/// light default for forms, per section 1 of the design brief.
class AppTheme {
  static ThemeData dark() {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.darkNavy,
      primaryColor: AppColors.primaryBlue,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primaryBlue,
        secondary: AppColors.primaryGreen,
        surface: AppColors.darkSurface,
        error: AppColors.error,
        onPrimary: AppColors.textWhite,
        onSecondary: AppColors.textDark,
        onSurface: AppColors.textOffWhite,
        onError: AppColors.textWhite,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontFamily: AppTypography.displayFamily,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AppColors.textOffWhite,
          letterSpacing: -0.2,
        ),
        iconTheme: IconThemeData(color: AppColors.textOffWhite, size: 24),
      ),
      cardTheme: CardTheme(
        color: AppColors.darkSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.brandGradient,
          foregroundColor: AppColors.textWhite,
          elevation: 0,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.md,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          textStyle: AppTypography.heading2.copyWith(color: AppColors.textWhite),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primaryGreen,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          textStyle: AppTypography.body.copyWith(
            color: AppColors.primaryGreen,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: AppColors.textOffWhite,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFF2A3355),
        thickness: 1,
        space: 1,
      ),
      textTheme: TextTheme(
        displayLarge: AppTypography.balanceDisplay.copyWith(color: AppColors.textWhite),
        headlineLarge: AppTypography.heading1.copyWith(color: AppColors.textWhite),
        headlineMedium: AppTypography.heading2.copyWith(color: AppColors.textWhite),
        bodyLarge: AppTypography.body.copyWith(color: AppColors.textOffWhite),
        bodyMedium: AppTypography.bodySmall.copyWith(color: AppColors.textOffWhite),
        bodySmall: AppTypography.caption,
        labelLarge: AppTypography.body.copyWith(
          color: AppColors.textOffWhite,
          fontWeight: FontWeight.w600,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.darkSurfaceAlt,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: Color(0xFF2A3355), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.primaryBlue, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.error, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.error, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        hintStyle: AppTypography.bodySmall.copyWith(color: AppColors.textMutedDark),
      ),
      textFieldTheme: const TextFieldThemeData(
        style: TextStyle(fontFamily: AppTypography.bodyFamily),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.darkSurfaceAlt,
        contentTextStyle: AppTypography.bodySmall.copyWith(color: AppColors.textOffWhite),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xs),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.darkSurface,
        selectedItemColor: AppColors.primaryGreen,
        unselectedItemColor: AppColors.textMutedDark,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.darkSurface,
        indicatorColor: AppColors.primaryBlue.withOpacity(0.3),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        elevation: 0,
        shadowColor: Colors.transparent,
      ),
    );
  }

  static ThemeData light() {
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.lightBg,
      primaryColor: AppColors.primaryBlue,
      colorScheme: const ColorScheme.light(
        primary: AppColors.primaryBlue,
        secondary: AppColors.primaryGreen,
        surface: AppColors.lightSurface,
        error: AppColors.error,
        onPrimary: AppColors.textWhite,
        onSecondary: AppColors.textDark,
        onSurface: AppColors.textDark,
        onError: AppColors.textWhite,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.lightBg,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontFamily: AppTypography.displayFamily,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AppColors.textDark,
          letterSpacing: -0.2,
        ),
        iconTheme: IconThemeData(color: AppColors.textMutedLight, size: 24),
      ),
      cardTheme: CardTheme(
        color: AppColors.lightSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        shadowColor: Colors.transparent,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.brandGradient,
          foregroundColor: AppColors.textWhite,
          elevation: 0,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.md,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          textStyle: AppTypography.heading2.copyWith(color: AppColors.textWhite),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primaryBlue,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          textStyle: AppTypography.body.copyWith(
            color: AppColors.primaryBlue,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: AppColors.textMutedLight,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFFE0E0DC),
        thickness: 1,
        space: 1,
      ),
      textTheme: TextTheme(
        displayLarge: AppTypography.balanceDisplay.copyWith(color: AppColors.textDark),
        headlineLarge: AppTypography.heading1.copyWith(color: AppColors.textDark),
        headlineMedium: AppTypography.heading2.copyWith(color: AppColors.textDark),
        bodyLarge: AppTypography.body.copyWith(color: AppColors.textDark),
        bodyMedium: AppTypography.bodySmall.copyWith(color: AppColors.textDark),
        bodySmall: AppTypography.caption.copyWith(color: AppColors.textMutedLight),
        labelLarge: AppTypography.body.copyWith(
          color: AppColors.textDark,
          fontWeight: FontWeight.w600,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.lightSurfaceAlt,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: Color(0xFFCFCFCC), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.primaryBlue, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.error, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.error, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        hintStyle: AppTypography.bodySmall.copyWith(color: AppColors.textMutedLight),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.lightSurface,
        selectedItemColor: AppColors.primaryBlue,
        unselectedItemColor: AppColors.textMutedLight,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.lightSurface,
        indicatorColor: AppColors.primaryBlue.withOpacity(0.1),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        elevation: 0,
        shadowColor: Colors.transparent,
      ),
    );
  }
}
