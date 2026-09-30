import 'package:flutter/material.dart';

/// The look every screen other than the board shares: deep navy gradient,
/// translucent panels with a hairline border, amber accent, uppercase
/// letter-spaced titles. Red is team A, blue is team B — everywhere.
class Ui {
  static const bg = Color(0xFF0F172A);
  static const bg2 = Color(0xFF1E1B4B);
  static const sheet = Color(0xFF1E1B4B);
  static const accent = Colors.amber;
  static const red = Colors.redAccent;
  static const blue = Colors.blueAccent;
  static const panel = Color(0x0DFFFFFF); // white 5%
  static const line = Color(0x1AFFFFFF); // white 10%
  static const muted = Colors.white54;
  static const faint = Colors.white38;

  static const radius = 20.0;

  static Color team(String t) => t == 'A' ? red : blue;

  /// App-wide defaults, so dialogs, chips, inputs, sliders and snackbars
  /// match without per-screen styling.
  static ThemeData theme() {
    final base = ThemeData(brightness: Brightness.dark, useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: bg,
      colorScheme: base.colorScheme.copyWith(
        primary: accent,
        onPrimary: Colors.black,
        secondary: Colors.cyanAccent,
        surface: bg2,
        surfaceContainerHighest: const Color(0xFF2A2766),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
            color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 2),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: sheet,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
        titleTextStyle: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        contentTextStyle: const TextStyle(color: Colors.white70, fontSize: 14),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: sheet,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      ),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: accent)),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.black),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: accent, foregroundColor: Colors.black),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: panel,
        selectedColor: accent.withOpacity(0.2),
        side: const BorderSide(color: line),
        labelStyle: const TextStyle(color: Colors.white70, fontSize: 12),
        secondaryLabelStyle: const TextStyle(color: accent, fontSize: 12),
        checkmarkColor: accent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        labelStyle: TextStyle(color: muted),
        hintStyle: TextStyle(color: Colors.white24),
        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: accent)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? accent : null),
        trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? accent.withOpacity(0.4) : null),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: sheet,
        contentTextStyle: TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
      ),
      dividerTheme: const DividerThemeData(color: line, space: 1, thickness: 1),
      listTileTheme: const ListTileThemeData(iconColor: Colors.white70, textColor: Colors.white),
    );
  }
}

/// A screen: the gradient, an uppercase title, optional tabs/filters below it.
class UiPage extends StatelessWidget {
  final String title;
  final Widget body;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final Widget? fab;

  const UiPage({super.key, required this.title, required this.body, this.actions, this.bottom, this.fab});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title.toUpperCase()), actions: actions, bottom: bottom),
      floatingActionButton: fab,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Ui.bg, Ui.bg2],
          ),
        ),
        child: SizedBox.expand(child: body),
      ),
    );
  }
}

/// A translucent rounded panel with a hairline border.
class UiPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final Color? borderColor;

  const UiPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.only(bottom: 12),
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) => Container(
        margin: margin,
        padding: padding,
        decoration: BoxDecoration(
          color: Ui.panel,
          borderRadius: BorderRadius.circular(Ui.radius),
          border: Border.all(color: borderColor ?? Ui.line),
        ),
        child: child,
      );
}

/// Amber bar + uppercase label, above a panel.
class UiSection extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const UiSection(this.title, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10, top: 4),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 18,
              decoration: BoxDecoration(color: Ui.accent, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(width: 10),
            Text(title.toUpperCase(),
                style: const TextStyle(
                    color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
            const Spacer(),
            if (trailing != null) trailing!,
          ],
        ),
      );
}

/// Centered icon + two lines, for empty lists.
class UiEmpty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? hint;
  const UiEmpty({super.key, required this.icon, required this.title, this.hint});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 64, color: Colors.white24),
              const SizedBox(height: 14),
              Text(title, style: const TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.bold)),
              if (hint != null) ...[
                const SizedBox(height: 6),
                Text(hint!, textAlign: TextAlign.center, style: const TextStyle(color: Ui.faint, fontSize: 13)),
              ],
            ],
          ),
        ),
      );
}

/// "Are you sure?" with a red confirm button. True when confirmed.
Future<bool> uiConfirm(BuildContext context,
    {required String title, required String message, String confirm = 'Delete'}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          style: TextButton.styleFrom(foregroundColor: Colors.white60),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
          child: Text(confirm),
        ),
      ],
    ),
  );
  return ok == true;
}

String uiTime(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// "Today", "Yesterday", "Mon 29/9", or "29/9/2025" for another year.
String uiDay(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  if (diff < 7) return '${wd[d.weekday - 1]} ${d.day}/${d.month}';
  return d.year == now.year ? '${d.day}/${d.month}' : '${d.day}/${d.month}/${d.year}';
}
