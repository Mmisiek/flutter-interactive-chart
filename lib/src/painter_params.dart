import 'dart:ui';
import 'package:flutter/widgets.dart';

import 'chart_style.dart';
import 'candle_data.dart';
import 'marker_data.dart';

class PainterParams {
  final String symbolLabel;
  final String timeAgrLabel;
  final List<CandleData> candles;
  final List<double> indicatorStartList;
  final List<MarkerData> markers;
  final ChartStyle style;
  final int candleTimePeriod;
  final Size size;
  final double candleWidth;
  final double startOffset;

  final bool showMarkersPriceLines;
  final bool showMarketsTimeLines;
  final bool showVolume;
  final bool showPL;

  final double maxPrice;
  final double minPrice;
  final double maxVol;
  final double minVol;
  final double maxBench;
  final double minBench;
  final double maxPL;
  final double minPL;

  final double xShift;
  final Offset? tapPosition;
  final List<double?>? leadingTrends;
  final List<double?>? trailingTrends;

  PainterParams({
    required this.symbolLabel,
    required this.timeAgrLabel,
    required this.candles,
    required this.indicatorStartList,
    required this.markers,
    required this.candleTimePeriod,
    required this.style,
    required this.size,
    required this.candleWidth,
    required this.startOffset,
    required this.showMarkersPriceLines,
    required this.showMarketsTimeLines,
    required this.showVolume,
    required this.showPL,
    required this.maxPrice,
    required this.minPrice,
    required this.maxVol,
    required this.minVol,
    required this.maxBench,
    required this.minBench,
    required this.maxPL,
    required this.minPL,
    required this.xShift,
    required this.tapPosition,
    required this.leadingTrends,
    required this.trailingTrends,
  });

  double get chartWidth => // width without price labels
      size.width - style.priceLabelWidth;

  double get chartHeight => // height without time labels
      size.height - style.timeLabelHeight;

  double get volumeHeight => chartHeight * style.volumeHeightFactor;

  double get priceHeight => chartHeight - volumeHeight;

  int getCandleIndexFromOffset(double x) {
    final adjustedPos = x - xShift + candleWidth / 2;
    final i = adjustedPos ~/ candleWidth;
    return i;
  }

  double fitPrice(double y) =>
      priceHeight * (maxPrice - y) / (maxPrice - minPrice) + candleWidth;

  double fitBenchmark(double y) =>
      priceHeight * (maxBench - y) / (maxBench - minBench) + candleWidth;

  double fitVolume(double y) {
    final gap = 12; // the gap between price bars and volume bars
    final baseAmount = 2; // display at least "something" for the lowest volume

    if (maxVol == minVol) {
      // Apparently max and min values (in the current visible range, at least)
      // are the same. It's likely they passed in a bunch of zeroes, because
      // they don't have real volume data or don't want to draw volumes.
      assert(() {
        if (style.volumeHeightFactor != 0) {
          print('If you do not want to show volumes, '
              'make sure to set `volumeHeightFactor` (ChartStyle) to zero.');
        }
        return true;
      }());
      // if they are both set to 0 just dot show it
      // Since they are equal, we just draw all volume bars as half height.
      return priceHeight + volumeHeight / 2;
    }

    final volGridSize = (volumeHeight - baseAmount - gap) / (maxVol - minVol);
    final vol = (y - minVol) * volGridSize;
    return volumeHeight - vol + priceHeight - baseAmount;
  }

  double fitPL(double y) {
    final gap = 12; // the gap between price bars and volume bars
    final baseAmount = 0; // display at least "something" for the lowest volume

    if (maxPL == minPL) {
      // Apparently max and min values (in the current visible range, at least)
      // are the same. It's likely they passed in a bunch of zeroes, because
      // they don't have real volume data or don't want to draw volumes.
      assert(() {
        if (style.volumeHeightFactor != 0) {
          print('If you do not want to show PL, '
              'make sure to set `volumeHeightFactor` (ChartStyle) to zero.');
        }
        return true;
      }());
      // if they are both set to 0 just dot show it
      // Since they are equal, we just draw all volume bars as half height.
      return priceHeight + volumeHeight / 2;
    }

    final volGridSize = (volumeHeight - baseAmount - gap) / (maxPL - minPL);
    final pl = (y - minPL) * volGridSize;
    return volumeHeight - pl + priceHeight - baseAmount;
  }

  double fitInd(double y) {
    final gap = 12; // the gap between price bars and volume bars
    final maxInd = 1;
    final minInd = 0;
    final baseAmount = 0;

    final volGridSize = (volumeHeight - baseAmount - gap) / (maxInd - minInd);
    final ind = (y - minInd) * volGridSize;
    return volumeHeight - ind + priceHeight - baseAmount;
  }

  static PainterParams lerp(PainterParams a, PainterParams b, double t) {
    double lerpField(double getField(PainterParams p)) =>
        lerpDouble(getField(a), getField(b), t)!;
    return PainterParams(
      symbolLabel: b.symbolLabel,
      timeAgrLabel: b.timeAgrLabel,
      candles: b.candles,
      indicatorStartList: b.indicatorStartList,
      markers: b.markers,
      candleTimePeriod: b.candleTimePeriod,
      style: b.style,
      size: b.size,
      candleWidth: b.candleWidth,
      startOffset: b.startOffset,
      showMarkersPriceLines: b.showMarkersPriceLines,
      showMarketsTimeLines: b.showMarketsTimeLines,
      showVolume: b.showVolume,
      showPL: b.showPL,
      maxPrice: lerpField((p) => p.maxPrice),
      minPrice: lerpField((p) => p.minPrice),
      maxVol: lerpField((p) => p.maxVol),
      minVol: lerpField((p) => p.minVol),
      maxBench: lerpField((p) => p.maxBench),
      minBench: lerpField((p) => p.minBench),
      maxPL: lerpField((p) => p.maxPL),
      minPL: lerpField((p) => p.minPL),
      xShift: b.xShift,
      tapPosition: b.tapPosition,
      leadingTrends: b.leadingTrends,
      trailingTrends: b.trailingTrends,
    );
  }

  bool shouldRepaint(PainterParams other) {
    if (candles.length != other.candles.length) return true;

    if (size != other.size ||
        candleWidth != other.candleWidth ||
        startOffset != other.startOffset ||
        xShift != other.xShift) return true;

    if (maxPrice != other.maxPrice ||
        minPrice != other.minPrice ||
        maxVol != other.maxVol ||
        minVol != other.minVol ||
        maxBench != other.maxBench ||
        minBench != other.minBench ||
        maxPL != other.maxPL ||
        minPL != other.minPL) return true;

    if (tapPosition != other.tapPosition) return true;

    if (leadingTrends != other.leadingTrends ||
        trailingTrends != other.trailingTrends) return true;

    if (style != other.style) return true;

    return false;
  }
}

class PainterParamsTween extends Tween<PainterParams> {
  PainterParamsTween({
    PainterParams? begin,
    required PainterParams end,
  }) : super(begin: begin, end: end);

  @override
  PainterParams lerp(double t) => PainterParams.lerp(begin ?? end!, end!, t);
}
