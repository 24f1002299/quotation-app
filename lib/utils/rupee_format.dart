import 'package:intl/intl.dart';

/// Returns an Indian-rupee formatted string, e.g. ₹1,23,456.
/// Uses the Indian numbering system (lakh/crore grouping via 'en_IN').
String formatRupee(num amount) {
  final fmt = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );
  return fmt.format(amount);
}
