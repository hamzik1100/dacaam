import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'features/shell/misconfigured_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Checked before anything else. A release build with no server behind it
  // would otherwise start normally on demo data and let anybody in with any
  // password — a failure that looks exactly like success, which is the only
  // kind worth stopping the app for.
  if (AppConfig.isMisconfigured) {
    runApp(const MisconfiguredScreen());

    return;
  }

  // Restaurant staff hold the device in portrait behind the counter; rotating
  // mid-order loses focus and slows service down.
  SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const DacaamApp());
}
