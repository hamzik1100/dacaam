package so.dacaam.dacaam_pos

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity, not FlutterActivity: local_auth shows the system
// biometric prompt as a fragment, and on a plain FlutterActivity the call
// fails at runtime with no prompt at all.
class MainActivity : FlutterFragmentActivity()
