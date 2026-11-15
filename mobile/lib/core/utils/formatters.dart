import 'package:intl/intl.dart';

import 'enums.dart';

/// Currency, number and date formatting.
///
/// Somaliland Shilling amounts are large (a burger is 35,000) so grouping and
/// compact forms matter a lot for readability on a phone. The currency prefix
/// is configurable from Settings; [Fmt.prefix] mirrors that setting.
class Fmt {
  const Fmt._();

  /// Mirrors `SettingsState.currencyPrefix`. Updated by the app root whenever
  /// the setting changes, so formatting helpers stay callable from anywhere.
  static String prefix = 'SLSH';

  static final NumberFormat _grouped = NumberFormat('#,##0', 'en_US');
  static final NumberFormat _grouped2 = NumberFormat('#,##0.##', 'en_US');

  /// `SLSH 1,250,000`
  static String money(num value, {String? withPrefix, bool decimals = false}) {
    final String p = withPrefix ?? prefix;
    final String n = decimals
        ? _grouped2.format(value)
        : _grouped.format(value);
    return p.isEmpty ? n : '$p $n';
  }

  /// `1,250,000` — used inside tables where the prefix is in the column header.
  static String number(num value) => _grouped.format(value);

  /// `2.5`, `1,250,000` — keeps up to two decimals and drops trailing zeros.
  /// Rates are the reason this exists: a 2.5% tax rounded to `3%` is wrong on
  /// every receipt that prints it.
  static String decimal(num value) => _grouped2.format(value);

  /// The same number as something you can hand to a `TextField` and edit:
  /// no grouping separators, and no `.0` tacked onto whole numbers.
  static String editable(num value) {
    final double v = value.toDouble();

    return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
  }

  /// `1.25M`, `500K` — axis labels and dense KPI chips.
  static String compact(num value) {
    final double v = value.toDouble();
    final double abs = v.abs();
    if (abs >= 1000000000) return '${_trim(v / 1000000000)}B';
    if (abs >= 1000000) return '${_trim(v / 1000000)}M';
    if (abs >= 1000) return '${_trim(v / 1000)}K';
    return _grouped.format(v);
  }

  static String moneyCompact(num value, {String? withPrefix}) {
    final String p = withPrefix ?? prefix;
    return p.isEmpty ? compact(value) : '$p ${compact(value)}';
  }

  static String _trim(double v) {
    final String s = v.toStringAsFixed(v.abs() < 10 ? 1 : 0);
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }

  /// `+12.5%` / `-3.2%`
  static String delta(double percent) {
    final String sign = percent >= 0 ? '+' : '';
    return '$sign${percent.toStringAsFixed(1)}%';
  }

  static String percent(double value, {int decimals = 0}) =>
      '${value.toStringAsFixed(decimals)}%';

  // ---- Dates -------------------------------------------------------------
  // Hand-rolled month/day names: `intl` ships no Somali locale data, and we
  // must not depend on runtime locale initialisation inside a POS.

  static const List<String> _monthsSo = <String>[
    'Jannaayo',
    'Febraayo',
    'Maarso',
    'Abriil',
    'Maajo',
    'Juun',
    'Luulyo',
    'Agoosto',
    'Sebtembar',
    'Oktoobar',
    'Nofembar',
    'Diseembar',
  ];
  static const List<String> _monthsShortSo = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Abr',
    'Maj',
    'Jun',
    'Lul',
    'Ago',
    'Seb',
    'Okt',
    'Nof',
    'Dis',
  ];
  static const List<String> _monthsEn = <String>[
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  static const List<String> _monthsShortEn = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// Index 0 == Monday, matching `DateTime.weekday - 1`.
  static const List<String> weekdaysShortSo = <String>[
    'Isn',
    'Tal',
    'Arb',
    'Kha',
    'Jim',
    'Sab',
    'Axa',
  ];
  static const List<String> weekdaysShortEn = <String>[
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];
  static const List<String> _weekdaysSo = <String>[
    'Isniin',
    'Talaado',
    'Arbaco',
    'Khamiis',
    'Jimco',
    'Sabti',
    'Axad',
  ];
  static const List<String> _weekdaysEn = <String>[
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  static List<String> weekdayLabels(AppLanguage lang) =>
      lang == AppLanguage.somali ? weekdaysShortSo : weekdaysShortEn;

  static String weekday(DateTime d, AppLanguage lang, {bool short = false}) {
    final int i = d.weekday - 1;
    if (short) return weekdayLabels(lang)[i];
    return (lang == AppLanguage.somali ? _weekdaysSo : _weekdaysEn)[i];
  }

  static String monthName(int month, AppLanguage lang, {bool short = false}) {
    final int i = month - 1;
    if (lang == AppLanguage.somali) {
      return short ? _monthsShortSo[i] : _monthsSo[i];
    }
    return short ? _monthsShortEn[i] : _monthsEn[i];
  }

  /// `24 Maj 2026`
  static String date(DateTime d, AppLanguage lang) =>
      '${d.day} ${monthName(d.month, lang, short: true)} ${d.year}';

  /// `Sabti, 24 Maj 2026`
  static String longDate(DateTime d, AppLanguage lang) =>
      '${weekday(d, lang)}, ${date(d, lang)}';

  /// `18 Maj - 24 Maj 2026`
  static String dateRange(DateTime from, DateTime to, AppLanguage lang) {
    if (from.year == to.year && from.month == to.month) {
      return '${from.day} - ${to.day} ${monthName(to.month, lang, short: true)} ${to.year}';
    }
    return '${date(from, lang)} - ${date(to, lang)}';
  }

  /// 24h clock — restaurants read `14:25` faster than `2:25 PM`.
  static String time(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  static String dateTime(DateTime d, AppLanguage lang) =>
      '${date(d, lang)} ${time(d)}';

  /// `2 daqiiqo ka hor` / `2 min ago`
  static String relative(DateTime d, AppLanguage lang, {DateTime? now}) {
    final Duration diff = (now ?? DateTime.now()).difference(d);
    final bool so = lang == AppLanguage.somali;
    if (diff.inSeconds < 60) return so ? 'Hadda' : 'Just now';
    if (diff.inMinutes < 60) {
      final int m = diff.inMinutes;
      return so ? '$m daqiiqo ka hor' : '$m min ago';
    }
    if (diff.inHours < 24) {
      final int h = diff.inHours;
      return so ? '$h saac ka hor' : '$h hr ago';
    }
    if (diff.inDays < 7) {
      final int d0 = diff.inDays;
      return so ? '$d0 maalmood ka hor' : '$d0 d ago';
    }
    return date(d, lang);
  }

  /// `#1025`
  static String orderNo(int n) => '#$n';
}
