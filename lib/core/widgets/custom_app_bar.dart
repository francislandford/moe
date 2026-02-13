import 'package:flutter/material.dart';

import '../constants/app_font.dart';

class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget? leading;
  final String title;
  final List<Widget>? actions;
  final Color backgroundColor;
  final Color textColor;
  final double elevation;
  final bool centerTitle;

  const CustomAppBar({
    super.key,
    this.leading,
    required this.title,
    this.actions,
    this.backgroundColor = Colors.deepPurple,
    this.textColor = Colors.white,
    this.elevation = 4.0,
    this.centerTitle = true,
  });

  @override
  Widget build(BuildContext context) {
    return AppBar(
      leading: leading,
      title: Text(
        title,
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.bold,
          fontSize: 20,
          fontFamily: AppFont.primaryFont, // You can specify a custom font if you have one
        ),
      ),
      actions: actions,
      backgroundColor: backgroundColor,
      elevation: elevation,
      centerTitle: centerTitle,
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
