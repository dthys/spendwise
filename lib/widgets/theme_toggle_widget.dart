import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/theme_service.dart';

class ThemeToggleWidget extends StatelessWidget {
  final bool showAsListTile;

  const ThemeToggleWidget({
    Key? key,
    this.showAsListTile = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeService>(
      builder: (context, themeService, child) {
        if (showAsListTile) {
          return ListTile(
            leading: Icon(
              themeService.currentThemeIcon,
              color: Theme.of(context).primaryColor,
            ),
            title: Text('Appearance'),
            subtitle: Text('${themeService.currentThemeText} mode'),
            trailing: Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => _showThemeDialog(context, themeService),
          );
        } else {
          return IconButton(
            icon: Icon(themeService.currentThemeIcon),
            onPressed: () => _showThemeDialog(context, themeService),
            tooltip: 'Change theme',
          );
        }
      },
    );
  }

  void _showThemeDialog(BuildContext context, ThemeService themeService) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Choose Theme'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ThemeOption(
              title: 'Light',
              icon: Icons.light_mode,
              isSelected: themeService.themeMode == ThemeMode.light,
              onTap: () {
                themeService.setThemeMode(ThemeMode.light);
                Navigator.pop(context);
              },
            ),
            _ThemeOption(
              title: 'Dark',
              icon: Icons.dark_mode,
              isSelected: themeService.themeMode == ThemeMode.dark,
              onTap: () {
                themeService.setThemeMode(ThemeMode.dark);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _ThemeOption({
    required this.title,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        icon,
        color: isSelected ? Theme.of(context).primaryColor : null,
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? Theme.of(context).primaryColor : null,
        ),
      ),
      trailing: isSelected
          ? Icon(Icons.check, color: Theme.of(context).primaryColor)
          : null,
      onTap: onTap,
    );
  }
}

// Quick theme toggle for AppBar - Simple toggle between light/dark
class QuickThemeToggle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeService>(
      builder: (context, themeService, child) {
        return IconButton(
          icon: AnimatedSwitcher(
            duration: Duration(milliseconds: 300),
            child: Icon(
              themeService.currentThemeIcon,
              key: ValueKey(themeService.themeMode),
            ),
          ),
          onPressed: () => themeService.toggleTheme(), // Simple toggle between light/dark
          tooltip: 'Toggle theme (${themeService.currentThemeText})',
        );
      },
    );
  }
}

// Alternative: Switch-style toggle
class ThemeSwitchWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeService>(
      builder: (context, themeService, child) {
        return ListTile(
          leading: Icon(
            themeService.isDarkMode ? Icons.dark_mode : Icons.light_mode,
            color: Theme.of(context).primaryColor,
          ),
          title: Text('Dark Mode'),
          subtitle: Text(themeService.isDarkMode ? 'Enabled' : 'Disabled'),
          trailing: Switch(
            value: themeService.isDarkMode,
            onChanged: (value) {
              themeService.setThemeMode(value ? ThemeMode.dark : ThemeMode.light);
            },
            activeColor: Theme.of(context).primaryColor,
          ),
        );
      },
    );
  }
}