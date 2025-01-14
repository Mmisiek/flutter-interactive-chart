class CandleData {
  /// The timestamp of this data point, in milliseconds since epoch.
  final int timestamp;

  /// The "open" price of this data point. It's acceptable to have null here for
  /// a few data points, but they must not all be null. If either [open] or
  /// [close] is null for a data point, it will appear as a gap in the chart.
  final double? open;

  /// The "high" price. If either one of [high] or [low] is null, we won't
  /// draw the narrow part of the candlestick for that data point.
  final double? high;

  /// The "low" price. If either one of [high] or [low] is null, we won't
  /// draw the narrow part of the candlestick for that data point.
  final double? low;

  /// The "close" price of this data point. It's acceptable to have null here
  /// for a few data points, but they must not all be null. If either [open] or
  /// [close] is null for a data point, it will appear as a gap in the chart.
  final double? close;

  /// The volume information of this data point.
  final double? volume;
  // potencial PL on trade close on this candle
  double? pl;

  /// Data holder for additional trend lines, for this data point.
  ///
  /// For a single trend line, we can assign it as a list with a single element.
  /// For example if we want "7 days moving average", do something like
  /// `trends = [ma7]`. If there are multiple tread lines, we can assign a list
  /// with multiple elements, like `trends = [ma7, ma30]`.
  /// If we don't want any trend lines, we can assign an empty list.
  ///
  /// This should be an unmodifiable list, so please do not use `add`
  /// or `clear` methods on the list. Always assign a new list if values
  /// are changed. Otherwise the UI might not be updated.
  List<double?> trends;

  /// Data holder for indicators to overlap with volume (lower chart place)
  ///
  ///
  List<double?> indicators;
  List<CandleData?> benchmarks;

  CandleData({
    required this.timestamp,
    required this.open,
    required this.close,
    required this.volume,
    this.high,
    this.low,
    this.pl,
    List<double?>? trends,
    List<double?>? indicators,
    List<CandleData?>? benchmarks,
  })  : this.trends = List.unmodifiable(trends ?? []),
        this.indicators = List.unmodifiable(indicators ?? []),
        this.benchmarks = List.unmodifiable(benchmarks ?? []);

  static List<double?> computeMA(List<CandleData> data, [int period = 7]) {
    // If data is not at least twice as long as the period, return nulls.
    if (data.length < period * 2) return List.filled(data.length, null);

    final List<double?> result = [];
    // Skip the first [period] data points. For example, skip 7 data points.
    final firstPeriod =
        data.take(period).map((d) => d.close).whereType<double>();
    double ma = firstPeriod.reduce((a, b) => a + b) / firstPeriod.length;
    result.addAll(List.filled(period, null));

    // Compute the moving average for the rest of the data points.
    for (int i = period; i < data.length; i++) {
      final curr = data[i].close;
      final prev = data[i - period].close;
      if (curr != null && prev != null) {
        ma = (ma * period + curr - prev) / period;
        result.add(ma);
      } else {
        result.add(null);
      }
    }
    return result;
  }

  static List<double?> computePRI(
      List<CandleData> data, List<CandleData> benchmark) {
    final List<double?> result = [];
    // find ovelapping time marks
    int j = 0;
    for (int i = 0; i < data.length; i++) {
      while (benchmark[j].timestamp < data[i].timestamp) {
        j++;
      }
      if (benchmark[j].timestamp == data[i].timestamp) {
        if (data[i].close != null && benchmark[j].close != null) {
          result.add(data[i].close! / benchmark[j].close!);
        } else {
          result.add(null);
        }
      } else {
        result.add(null);
      }
    }

    return result;
  }

  static void setBenchmark(List<CandleData> data, List<CandleData> benchmark) {
    // find ovelapping time marks
    int j = 0;
    for (int i = 0; i < data.length; i++) {
      while (benchmark[j].timestamp < data[i].timestamp) {
        j++;
      }
      if (benchmark[j].timestamp == data[i].timestamp) {
        data[i].benchmarks = [benchmark[j]];
      } else {
        data[i].benchmarks = [];
      }
    }
  }

  static void setCandlePL(
      List<CandleData> data, List<Map<String, dynamic>> trades) {
    // find ovelapping time marks
    const String timestampTag = 'timestamp';
    const String plTag = 'p&l';
    int j = 0;
    for (int i = 0; i < data.length; i++) {
      while (j < (trades.length - 1) &&
          trades[j][timestampTag] < data[i].timestamp) {
        j++;
      }
      while (j < trades.length) {
        if (trades[j][timestampTag] >= data[i].timestamp &&
            trades[j][timestampTag] < data[i + 1].timestamp) {
          double pl = double.parse(trades[j][plTag]);
          if (data[i].pl != null) {
            data[i].pl = data[i].pl! + pl;
          } else {
            data[i].pl = pl;
          }
          j++;
        } else if (trades[j][plTag].isEmpty) {
          j++;
        } else {
          break;
        }
      }
    }
  }

  @override
  String toString() => "<CandleData ($timestamp: $close)>";
}
