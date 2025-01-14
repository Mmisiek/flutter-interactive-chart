import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart' as intl;

import '../interactive_chart.dart';
import 'candle_data.dart';
import 'chart_painter.dart';
import 'chart_style.dart';
import 'painter_params.dart';
import 'marker_data.dart';
import 'double_extension.dart';

class InteractiveChart extends StatefulWidget {
  /// Symbol label
  ///
  final String symbolLabel;

  /// Time agregate label
  ///
  final String timeAgrLabel;

  ///
  /// The full list of [CandleData] to be used for this chart.
  ///
  /// It needs to have at least 3 data points. If data is sufficiently large,
  /// the chart will default to display the most recent 90 data points when
  /// first opened (configurable with [initialVisibleCandleCount] parameter),
  /// and allow users to freely zoom and pan however they like.
  final List<CandleData> candles;

  /// List of markets to add on chart
  ///
  ///
  final List<MarkerData> markers;

  // The defualt starting candle. If not provided 0 (first).
  //
  final int startVisibleCandle;

  /// The default number of data points to be displayed when the chart is first
  /// opened. The default value is 90. If [CandleData] does not have enough data
  /// points, the chart will display all of them.
  final int initialVisibleCandleCount;

  /// If non-null, the style to use for this chart.
  final ChartStyle style;

  /// How the date/time label at the bottom are displayed.
  ///
  /// If null, it defaults to use yyyy-mm format if more than 20 data points
  /// are visible in the current chart window, otherwise it uses mm-dd format.
  final TimeLabelGetter? timeLabel;

  /// How the price labels on the right are displayed.
  ///
  /// If null, it defaults to show 2 digits after the decimal point.
  final PriceLabelGetter? priceLabel;

  /// How the overlay info are displayed, when user touches the chart.
  ///
  /// If null, it defaults to display `date`, `open`, `high`, `low`, `close`
  /// and `volume` fields when user selects a data point in the chart.
  ///
  /// To customize it, pass in a function that returns a Map<String,String>:
  /// ```dart
  /// return {
  ///   "Date": "Customized date string goes here",
  ///   "Open": candle.open?.toStringAsFixed(2) ?? "-",
  ///   "Close": candle.close?.toStringAsFixed(2) ?? "-",
  /// };
  /// ```
  final OverlayInfoGetter? overlayInfo;

  /// The candle size in time (miliseconds), default 1 minute = 60 * 1000
  ///
  final int candleTimePeriod;

  /// An optional event, fired when the user clicks on a candlestick.
  final ValueChanged<CandleData>? onTap;

  /// An optional event, fired when user zooms in/out.
  ///
  /// This provides the width of a candlestick at the current zoom level.
  final ValueChanged<double>? onCandleResize;

  /// Show markers price lines
  ///
  final bool? showMarkersPriceLines;

  /// Show markers price lines
  ///
  final bool? showMarkersTimeLines;
  // Show volume
  final bool? showVolume;

  const InteractiveChart({
    Key? key,
    this.symbolLabel = '',
    this.timeAgrLabel = '',
    required this.candles,
    this.markers = const [],
    this.candleTimePeriod = 60 * 1000, // one minute default
    this.startVisibleCandle = -90,
    this.initialVisibleCandleCount = 90,
    ChartStyle? style,
    this.timeLabel,
    this.priceLabel,
    this.overlayInfo,
    this.onTap,
    this.onCandleResize,
    this.showMarkersPriceLines = false,
    this.showMarkersTimeLines = false,
    this.showVolume = true,
  })  : this.style = style ?? const ChartStyle(),
        assert(candles.length >= 3,
            "InteractiveChart requires 3 or more CandleData"),
        assert(initialVisibleCandleCount >= 3,
            "initialVisibleCandleCount must be more 3 or more"),
        assert(
            (startVisibleCandle < candles.length &&
                startVisibleCandle > -1 * candles.length),
            "startVisibleCandle must less than last candle number"),
        super(key: key);

  @override
  _InteractiveChartState createState() => _InteractiveChartState();

  void reloadChart() {
    (key as GlobalKey<_InteractiveChartState>).currentState?.reloadChart();
  }
}

class _InteractiveChartState extends State<InteractiveChart> {
  // The width of an individual bar in the chart.
  late double _candleWidth;

  // The x offset (in px) of current visible chart window,
  // measured against the beginning of the chart.
  // i.e. a value of 0.0 means we are displaying data for the very first day,
  // and a value of 20 * _candleWidth would be skipping the first 20 days.
  late double _startOffset;

  // The position that user is currently tapping, null if user let go.
  Offset? _tapPosition;

  double? _prevChartWidth; // used by _handleResize
  late double _prevCandleWidth;
  late double _prevStartOffset;
  late Offset _initialFocalPoint;
  PainterParams? _prevParams; // used in onTapUp event

  void reloadChart() {
    print("Reload chart called");
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final size = constraints.biggest;
        final w = size.width - widget.style.priceLabelWidth;
        _handleResize(w);

        // Find the visible data range
        final int start = (_startOffset / _candleWidth).floor();
        final int count = (w / _candleWidth).ceil();
        final int end = (start + count).clamp(start, widget.candles.length);
        final candlesInRange = widget.candles.getRange(start, end).toList();
        if (end < widget.candles.length) {
          // Put in an extra item, since it can become visible when scrolling
          final nextItem = widget.candles[end];
          candlesInRange.add(nextItem);
        }
        // Select markers which overlap visible candless using
        // timestamp as filter
        List<MarkerData> markersInRange = List.from(widget.markers);
        markersInRange.removeWhere((element) =>
            (element.timestamp < candlesInRange.first.timestamp ||
                element.timestamp > candlesInRange.last.timestamp));
        // If possible, find neighbouring trend line data,
        // so the chart could draw better-connected lines
        final leadingTrends = widget.candles.at(start - 1)?.trends;
        final trailingTrends = widget.candles.at(end + 1)?.trends;

        // Find the horizontal shift needed when drawing the candles.
        // First, always shift the chart by half a candle, because when we
        // draw a line using a thick paint, it spreads to both sides.
        // Then, we find out how much "fraction" of a candle is visible, since
        // when users scroll, they don't always stop at exact intervals.
        final halfCandle = _candleWidth / 2;
        final fractionCandle = _startOffset - start * _candleWidth;
        final xShift = halfCandle - fractionCandle;

        // Calculate min and max among the visible data
        double? highest(CandleData c) {
          if (c.high != null) return c.high;
          if (c.open != null && c.close != null) return max(c.open!, c.close!);
          return c.open ?? c.close;
        }

        double? lowest(CandleData c) {
          if (c.low != null) return c.low;
          if (c.open != null && c.close != null) return min(c.open!, c.close!);
          return c.open ?? c.close;
        }

        final maxPrice =
            candlesInRange.map(highest).whereType<double>().reduce(max);
        final minPrice =
            candlesInRange.map(lowest).whereType<double>().reduce(min);

        final maxVol = candlesInRange
            .map((c) => c.volume)
            .whereType<double>()
            .fold(double.negativeInfinity, max);
        final minVol = candlesInRange
            .map((c) => c.volume)
            .whereType<double>()
            .fold(double.infinity, min);
        bool showPL = false;
        double maxPL = candlesInRange
            .map((c) => c.pl)
            .whereType<double>()
            .fold(double.negativeInfinity, max);
        double minPL = candlesInRange
            .map((c) => c.pl)
            .whereType<double>()
            .fold(double.infinity, min);
        if (maxPL == double.negativeInfinity && minPL == double.infinity) {
          maxPL = 0;
          minPL = 0;
        } else {
          showPL = true;
          // check for single operation
          if (maxPL == minPL) {
            if (maxPL == 0) {
              // if there is zero trade make sure it is visible
              // around 0 as grey bar
              minPL = -200;
              maxPL = 200;
            }
            if (maxPL < 0) {
              maxPL = 0;
            }
            if (maxPL > 0) {
              minPL = 0;
            }
          }
        }

        double maxBench = double.negativeInfinity;
        double minBench = double.infinity;
        bool benchSet = false;
        // look for benchmark range
        int countBench = 0;
        for (int j = 0; j < candlesInRange.length; j++) {
          candlesInRange[j].benchmarks.forEach((element) {
            double? high = highest(element!);
            if (high != null) {
              if (high! > maxBench) {
                maxBench = high;
                benchSet = true;
              }
              countBench++;
            }
            double? low = lowest(element!);
            if (low != null) {
              if (low! < minBench) {
                minBench = low;
                benchSet = true;
              }
              countBench++;
            }
          });
        }
        if (benchSet == false) {
          maxBench = 0;
          minBench = 0;
        } else {
          print("Benchmark max $maxBench min $minBench count $countBench");
        }

        // find fits candle in indicators witn non-null value
        List<double> indicatorStartList = [];
        for (int j = 0; j < widget.candles.first.indicators.length; j++) {
          // assumes at least 1 value not null in indicator list
          CandleData first = widget.candles
              .firstWhere((candle) => candle.indicators[j] != null);
          indicatorStartList.add(first.indicators[j]!);
        }
        final child = TweenAnimationBuilder(
          tween: PainterParamsTween(
            end: PainterParams(
              symbolLabel: widget.symbolLabel,
              timeAgrLabel: widget.timeAgrLabel,
              candles: candlesInRange,
              indicatorStartList: indicatorStartList,
              markers: markersInRange,
              candleTimePeriod: widget.candleTimePeriod,
              style: widget.style,
              size: size,
              candleWidth: _candleWidth,
              startOffset: _startOffset,
              showMarkersPriceLines: widget.showMarkersPriceLines ?? false,
              showMarketsTimeLines: widget.showMarkersTimeLines ?? false,
              showVolume: widget.showVolume ?? false,
              showPL: showPL,
              maxPrice: maxPrice,
              minPrice: minPrice,
              maxVol: maxVol,
              minVol: minVol,
              maxBench: maxBench,
              minBench: minBench,
              maxPL: maxPL,
              minPL: minPL,
              xShift: xShift,
              tapPosition: _tapPosition,
              leadingTrends: leadingTrends,
              trailingTrends: trailingTrends,
            ),
          ),
          duration: Duration(milliseconds: 300),
          curve: Curves.easeOut,
          builder: (_, PainterParams params, __) {
            _prevParams = params;
            return RepaintBoundary(
              child: CustomPaint(
                size: size,
                painter: ChartPainter(
                  params: params,
                  getTimeLabel: widget.timeLabel ?? defaultTimeLabel,
                  getPriceLabel: widget.priceLabel ?? defaultPriceLabel,
                  getOverlayInfo: widget.overlayInfo ?? defaultOverlayInfo,
                ),
              ),
            );
          },
        );

        return Listener(
          onPointerSignal: (signal) {
            if (signal is PointerScrollEvent) {
              final dy = signal.scrollDelta.dy;
              if (dy.abs() > 0) {
                _onScaleStart(signal.position);
                _onScaleUpdate(
                  dy > 0 ? 0.9 : 1.1,
                  signal.position,
                  w,
                );
              }
            }
          },
          child: GestureDetector(
            // Tap and hold to view candle details
            onTapDown: (details) => setState(() {
              _tapPosition = details.localPosition;
            }),
            onTapCancel: () => setState(() => _tapPosition = null),
            onTapUp: (_) {
              // Fire callback event and reset _tapPosition
              if (widget.onTap != null) _fireOnTapEvent();
              setState(() => _tapPosition = null);
            },
            // Pan and zoom
            onScaleStart: (details) => _onScaleStart(details.localFocalPoint),
            onScaleUpdate: (details) =>
                _onScaleUpdate(details.scale, details.localFocalPoint, w),
            child: child,
          ),
        );
      },
    );
  }

  _onScaleStart(Offset focalPoint) {
    _prevCandleWidth = _candleWidth;
    _prevStartOffset = _startOffset;
    _initialFocalPoint = focalPoint;
  }

  _onScaleUpdate(double scale, Offset focalPoint, double w) {
    // Handle zoom
    final candleWidth = (_prevCandleWidth * scale)
        .clamp(_getMinCandleWidth(w), _getMaxCandleWidth(w));
    final clampedScale = candleWidth / _prevCandleWidth;
    var startOffset = _prevStartOffset * clampedScale;
    // Handle pan
    final dx = (focalPoint - _initialFocalPoint).dx * -1;
    startOffset += dx;
    // Adjust pan when zooming
    final double prevCount = w / _prevCandleWidth;
    final double currCount = w / candleWidth;
    final zoomAdjustment = (currCount - prevCount) * candleWidth;
    final focalPointFactor = focalPoint.dx / w;
    startOffset -= zoomAdjustment * focalPointFactor;
    startOffset = startOffset.clamp(0, _getMaxStartOffset(w, candleWidth));
    // Fire candle width resize event
    if (candleWidth != _candleWidth) {
      widget.onCandleResize?.call(candleWidth);
    }
    // Apply changes
    setState(() {
      _candleWidth = candleWidth;
      _startOffset = startOffset;
    });
  }

  _handleResize(double w) {
    if (w == _prevChartWidth) return;
    int count = 0;
    if (_prevChartWidth != null) {
      // Re-clamp when size changes (e.g. screen rotation)
      _candleWidth = _candleWidth.clamp(
        _getMinCandleWidth(w),
        _getMaxCandleWidth(w),
      );
      //print('Candle width $_candleWidth secreen width $w');
      _startOffset = _startOffset.clamp(
        0,
        _getMaxStartOffset(w, _candleWidth),
      );
    } else {
      // Default zoom level. Defaults to a 90 day chart, but configurable.
      // If data is shorter, we use the whole range.
      final start = widget.startVisibleCandle;

      count = min(
        widget.candles.length,
        widget.initialVisibleCandleCount,
      );
      _candleWidth = w / count;
      // Default show the latest available data, e.g. the most recent 90 days.
      // find offset to requested candle from beginig
      if (start >= 0) {
        _startOffset = start * _candleWidth;
      } else {
        // or from end
        _startOffset = (widget.candles.length + start - count) * _candleWidth;
      }
    }
    _prevChartWidth = w;
    //print('Candle width $_candleWidth secreen width $w count $count');
  }

  // The narrowest candle width, i.e. when drawing all available data points.
  double _getMinCandleWidth(double w) => w / widget.candles.length;

  // The widest candle width, e.g. when drawing 14 day chart
  double _getMaxCandleWidth(double w) => w / min(14, widget.candles.length);

  // Max start offset: how far can we scroll towards the end of the chart
  double _getMaxStartOffset(double w, double candleWidth) {
    final count = w / candleWidth; // visible candles in the window
    final start = widget.candles.length - count;
    return max(0, candleWidth * start);
  }

  String defaultTimeLabel(int timestamp, int visibleDataCount) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp)
        .toIso8601String()
        .split("T")
        .first
        .split("-");

    if (visibleDataCount > 20) {
      // If more than 20 data points are visible, we should show year and month.
      return "${date[0]}-${date[1]}"; // yyyy-mm
    } else {
      // Otherwise, we should show month and date.
      return "${date[1]}-${date[2]}"; // mm-dd
    }
  }

  String defaultPriceLabel(double price) => price.toStringAsFixed(2);

  Map<String, String> defaultOverlayInfo(CandleData candle) {
    final date = intl.DateFormat.yMMMd()
        .add_Hms()
        .format(DateTime.fromMillisecondsSinceEpoch(candle.timestamp));
    Map<String, String> map = {
      "Date": date,
      "Open": candle.open?.toStringAsFixed(2) ?? "-",
      "High": candle.high?.toStringAsFixed(2) ?? "-",
      "Low": candle.low?.toStringAsFixed(2) ?? "-",
      "Close": candle.close?.toStringAsFixed(2) ?? "-",
      "Volume": candle.volume?.asAbbreviated() ?? "-",
    };
    if (candle.pl != null) {
      map["P&L"] = candle.pl?.toString() ?? "-";
    }
    return map;
  }

  void _fireOnTapEvent() {
    if (_prevParams == null || _tapPosition == null) return;
    final params = _prevParams!;
    final dx = _tapPosition!.dx;
    final selected = params.getCandleIndexFromOffset(dx);
    final candle = params.candles[selected];
    widget.onTap?.call(candle);
  }
}
