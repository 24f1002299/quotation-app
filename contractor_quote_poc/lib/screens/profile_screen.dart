import 'settings_screen.dart';

/// Backward-compatible alias: Settings lives in [SettingsScreen] now.
/// The '/profile' route still resolves here.
class ProfileScreen extends SettingsScreen {
  const ProfileScreen({super.key});
}
