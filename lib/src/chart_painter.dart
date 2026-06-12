import 'dart:math';
//import 'dart:web_gl';
import 'package:universal_io/io.dart';

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart' as intl;
import 'package:tuple/tuple.dart';

import 'candle_data.dart';
import 'painter_params.dart';
import 'marker_data.dart';
import 'double_extension.dart';

typedef TimeLabelGetter = String Function(int timestamp, int visibleDataCount);
typedef PriceLabelGetter = String Function(double price);
typedef OverlayInfoGetter = Map<String, String> Function(CandleData candle);

class ChartPainter extends CustomPainter {
  final PainterParams params;
  final TimeLabelGetter getTimeLabel;
  final PriceLabelGetter getPriceLabel;
  final OverlayInfoGetter getOverlayInfo;
  final List<Tuple2<int, Rect>> visibleMarkersRect = [];

  ChartPainter({
    required this.params,
    required this.getTimeLabel,
    required this.getPriceLabel,
    required this.getOverlayInfo,
  });

  // to be imporved by screen size ?
  bool isMobile() {
    return Platform.isAndroid || Platform.isIOS;
  }

  @override
  void paint(Canvas canvas, Size size) {
    bool drawCandlesPrices = true;
    if (params.candleTimePeriod < 86400000) {
      canvas.save();
      canvas.translate(params.xShift, 0);

      _drawTradeDaysGridlines(canvas, params);
      canvas.restore();
    }
    // draw min max prices for visible period
    // to do make it option.
    if (drawCandlesPrices) {
      _drawChartHeader(canvas, params);
    }
    _drawSymbolAndTime(canvas, params);
    // dont shpw prices for R lines
    _drawPriceGridAndLabels(canvas, params);
    _drawLowerGridAndLabels(canvas, params);
    // Draw prices, volumes & trend line
    canvas.save();
    canvas.clipRect(Offset.zero & Size(params.chartWidth, params.chartHeight));
    // canvas.drawRect(
    //   // apply yellow tint to clipped area (for debugging)
    //   Offset.zero & Size(params.chartWidth, params.chartHeight),
    //   Paint()..color = Colors.yellow[100]!,
    // );
    canvas.translate(params.xShift, 0);
    for (int i = 0; i < params.candles.length; i++) {
      _drawSingleDay(canvas, params, i);
    }
    canvas.restore();
    if (params.showMarkersPriceLines) {
      for (int i = 0; i < params.candles.length; i++) {
        _drawSingleDayMarkers(canvas, params, i, MarkerElement.priceLine);
      }
    }
    if (params.showRLines) {
      for (int i = 0; i < params.candles.length; i++) {
        _drawSingleDayMarkers(canvas, params, i, MarkerElement.limitStopLines);
        _drawSingleDayMarkers(canvas, params, i, MarkerElement.priceLine);
      }
    }
    if (params.showRLines) {
      for (int i = 0; i < params.candles.length; i++) {
        _drawSingleDayMarkers(canvas, params, i, MarkerElement.limitStopPrices);
        _drawSingleDayMarkers(canvas, params, i, MarkerElement.priceLabel);
      }
    }
    if (params.showMarkersPriceLines) {
      // draw line prices on the side
      for (int i = 0; i < params.candles.length; i++) {
        _drawSingleDayMarkers(canvas, params, i, MarkerElement.priceLabel);
      }
    }

    // Draw time labels (dates) & price labels only if marker are not shown
    _drawTimeLabels(canvas, params);

    canvas.save();
    canvas.clipRect(Offset.zero & Size(params.chartWidth, params.chartHeight));
    // canvas.drawRect(
    //   // apply yellow tint to clipped area (for debugging)
    //   Offset.zero & Size(params.chartWidth, params.chartHeight),
    //   Paint()..color = Colors.yellow[100]!,
    // );
    canvas.translate(params.xShift, 0);
    if (params.showMarketsTimeLines) {
      for (int i = 0; i < params.candles.length; i++) {
        _drawSingleDayMarkers(canvas, params, i, MarkerElement.timeLine);
        _drawSingleDayMarkers(canvas, params, i, MarkerElement.timeLabel);
      }
    }

    for (int i = 0; i < params.candles.length; i++) {
      _drawSingleDayMarkers(canvas, params, i, MarkerElement.marker);
    }

    canvas.restore();
    // Draw tap highlight & overlay
    if (params.tapPosition != null) {
      if (params.tapPosition!.dx < params.chartWidth) {
        _drawTapHighlightAndOverlay(canvas, params);
      }
    }
  }

  // paint summary of chart on top
  void _drawChartHeader(canvas, PainterParams params) {
    double open = params.candles.first.open ?? 0.0;
    double close = params.candles.last.close ?? 0.0;
    double high = open, low = close;
    for (int i = 0; i < params.candles.length; i++) {
      if ((params.candles[i].high ?? 0.0) > high) {
        high = params.candles[i].high ?? 0.0;
      }
      if ((params.candles[i].low ?? 0.0) < low) {
        low = params.candles[i].low ?? 0.0;
      }
    }
    String header = '';
    if (isMobile()) {
      header = 'Open: \$' +
          open.toStringAsFixed(2) +
          ' close: \$' +
          close.toStringAsFixed(2) +
          '\nHigh: \$' +
          high.toStringAsFixed(2) +
          ' low: \$' +
          low.toStringAsFixed(2);
    } else {
      header = 'Open: \$' +
          open.toStringAsFixed(2) +
          ' close: \$' +
          close.toStringAsFixed(2) +
          ' high: \$' +
          high.toStringAsFixed(2) +
          ' low: \$' +
          low.toStringAsFixed(2);
    }
    final headerTp = TextPainter(
      text: TextSpan(
        text: header,
        style: params.style.summaryLabelStyle,
      ),
    )
      ..textDirection = TextDirection.ltr
      ..textAlign = TextAlign.center
      ..layout();
    headerTp.paint(
      canvas,
      Offset(params.chartWidth / 2 - headerTp.width / 2, headerTp.height / 2),
    );
    int maxNames = params.candles[0].trends.length;
    double xOffset = 0;
    double xStart = 0;
    double maxName = 0;
    for (int i = 0; i < params.candles[0].trends.length; i++) {
      // draw legent
      final maTp = TextPainter(
        text: TextSpan(
          text: params.candles[0].trendNames[i],
          style: TextStyle(
              color: params.style.trendLineStyles[i].color,
              fontSize: isMobile() ? 12 : 18),
        ),
      )
        ..textDirection = TextDirection.ltr
        ..layout();
      if (maTp.width > maxName) {
        maxName = maTp.width;
      }
    }
    xStart = params.chartWidth / 2 - maxNames * (maxName + 5) / 2;
    for (int i = 0; i < params.candles[0].trends.length; i++) {
      // draw legent
      final maTp = TextPainter(
        text: TextSpan(
          text: params.candles[0].trendNames[i],
          style: TextStyle(
              color: params.style.trendLineStyles[i].color,
              fontSize: isMobile() ? 12 : 18),
        ),
      )
        ..textDirection = TextDirection.ltr
        ..layout();
      maTp.paint(
        canvas,
        Offset(xStart + xOffset, headerTp.height + maTp.height),
      );
      xOffset += (maTp.width + 5);
    }
  }

  // TODO change it to fixed time intervals instead.
  void _drawTimeLabels(canvas, PainterParams params) {
    // We draw one time label per 90 pixels of screen width
    final lineCount = params.chartWidth ~/ 90;
    final gap = 1 / (lineCount + 1);
    for (int i = 1; i <= lineCount; i++) {
      double x = i * gap * params.chartWidth;
      final index = params.getCandleIndexFromOffset(x);
      if (index < params.candles.length) {
        final candle = params.candles[index];
        final visibleDataCount = params.candles.length;
        final timeTp = TextPainter(
          text: TextSpan(
            text: getTimeLabel(candle.timestamp, visibleDataCount),
            style: params.style.timeLabelStyle,
          ),
        )
          ..textDirection = TextDirection.ltr
          ..layout();

        // Align texts towards vertical bottom
        final topPadding = params.style.timeLabelHeight - timeTp.height;
        timeTp.paint(
          canvas,
          Offset(x - timeTp.width / 2, params.chartHeight + topPadding),
        );
      }
    }
  }

  // TODO change it to fixed time intervals instead.
  void _drawSymbolAndTime(canvas, PainterParams params) {
    // We draw one time label per 90 pixels of screen width
    final x = params.chartWidth / 2.0;
    final y = params.chartHeight / 2.0;
    final fontSizeLarge = params.chartHeight / 5.0;
    final fontSizeSmall = params.chartHeight / 10.0;

    final symbolTp = TextPainter(
      text: TextSpan(
        text: params.symbolLabel,
        style: TextStyle(
          color: params.style.backgroundTextColor,
          fontSize: fontSizeLarge,
          fontWeight: FontWeight.bold,
        ),
      ),
    )
      ..textDirection = TextDirection.ltr
      ..layout();

    // Center text
    symbolTp.paint(
      canvas,
      Offset(x - symbolTp.width / 2.0, y - symbolTp.height / 2.0),
    );

    final timeTp = TextPainter(
      text: TextSpan(
        text: params.timeAgrLabel,
        style: TextStyle(
          color: params.style.backgroundTextColor,
          fontSize: fontSizeSmall,
          fontWeight: FontWeight.bold,
        ),
      ),
    )
      ..textDirection = TextDirection.ltr
      ..layout();
    // Center text
    timeTp.paint(
      canvas,
      Offset(x - timeTp.width / 2.0, y + symbolTp.height / 3.0),
    );
    // draw indicator single line if defined
    for (int j = 0; j < params.indicatorStartList.length; j++) {
      final indicatorLinePaint = params.style.indicatorLineStyles.at(j) ??
          (Paint()
            ..strokeWidth = 2.0
            ..strokeCap = StrokeCap.round
            ..color = params.style.priceLossColor);
      final pt = params.indicatorStartList[j]; // current data point
      canvas.drawLine(
        Offset(0, params.fitInd(pt)),
        Offset(params.chartWidth, params.fitInd(pt)),
        indicatorLinePaint,
      );
        }
  }

  // TO DO more price levels and locked by division
  void _drawPriceGridAndLabels(canvas, PainterParams params) {
    List<double> gridPoints = [];
    if (params.style.enableMinorGrid) {
      gridPoints.clear();
      double priceSpread = params.maxPrice - params.minPrice;
      double priceStep = priceSpread / 10.0;
      //if (priceStep > 1.0) {
      for (int i = 0; i < 10; i++) {
        gridPoints.add(params.minPrice + i * priceStep);
      }
    } else {
      gridPoints = [0.0, 0.25, 0.5, 0.75, 1.0];
      for (int i = 0; i < 5; i++) {
        gridPoints.add(
            ((params.maxPrice - params.minPrice) * i * 0.25) + params.minPrice);
      }
    }
    gridPoints.forEach((y) {
      canvas.drawLine(
        Offset(0, params.fitPrice(y)),
        Offset(params.chartWidth, params.fitPrice(y)),
        Paint()
          ..strokeWidth = 0.5
          ..color = params.style.priceGridLineColor,
      );

      final priceTp = TextPainter(
        text: TextSpan(
          text: getPriceLabel(y),
          style: params.style.priceLabelStyle,
        ),
      )
        ..textDirection = TextDirection.ltr
        ..layout();
      priceTp.paint(
          canvas,
          Offset(
            params.chartWidth + 4,
            params.fitPrice(y) - priceTp.height / 2,
          ));
    });
  }

  double roundNumber(double number, int digits) {
    double gridRound = number;
    double shift = 0;
    // get number rounded for digits after comma
    if (number < digits * 10) {
      gridRound *= 10;
    }

    while (gridRound > (10 * digits)) {
      gridRound /= 10;
      shift++;
    }
    gridRound = gridRound.roundToDouble();
    while (shift > 0) {
      gridRound *= 10;
      shift--;
    }
    if (number < digits * 10) {
      gridRound /= 10;
    }
    return gridRound;
  }

  void _drawLowerGridAndLabels(canvas, PainterParams params) {
    List<double> gridPoints = [];
    List<double> gridY = [];
    int ticks = isMobile() ? 7 : 7;
    gridPoints.clear();
    double gridSpread = 0.0, gridStep = 0.0;
    double gridMin = 0.0, gridMax = 0.0;
    if (params.showVolume) {
      gridSpread = params.maxVol - params.minVol;
      gridMin = roundNumber(params.minVol, 1);
      gridStep = roundNumber(gridSpread / (ticks + 0.0), 1);
      // maybe PL ?
    } else if (params.showPL) {
      double maxPLAdj = params.maxPL;
      double minPLAdj = params.minPL;
      if (minPLAdj < 0 && maxPLAdj < 0) {
        maxPLAdj = 0;
      }
      if (maxPLAdj > 0 && minPLAdj > 0) {
        minPLAdj = 0;
      }
      gridSpread = maxPLAdj - minPLAdj;
      if (gridSpread < 1) {
        gridStep = 0.1;
      } else {
        gridStep = roundNumber(gridSpread / (ticks - 1 + 0.0), 1);
      }
      int ratio = (minPLAdj / gridStep).round();
      gridMin = roundNumber(gridStep * ratio, 1);
    } else {
      return;
    }

    //if (priceStep > 1.0) {
    for (int i = 0; i < ticks; i++) {
      gridPoints.add(gridMin + i * gridStep);
    }

    if (params.showVolume) {
      gridPoints.forEach((y) {
        gridY.add(params.fitVolume(y));
      });
    } else if (params.showPL) {
      gridPoints.forEach((y) {
        gridY.add(params.fitPL(y));
      });
    }

    for (int i = 0; i < gridPoints.length; i++) {
      canvas.drawLine(
        Offset(0, gridY[i]),
        Offset(params.chartWidth, gridY[i]),
        Paint()
          ..strokeWidth = 0.5
          ..color = params.style.priceGridLineColor,
      );

      final priceTp = TextPainter(
        text: TextSpan(
          text: gridPoints[i].asAbbreviated(2),
          style: params.style.lowerGridTextStyle,
        ),
      )
        ..textDirection = TextDirection.ltr
        ..layout();
      priceTp.paint(
          canvas,
          Offset(
            params.chartWidth + 4,
            gridY[i] - priceTp.height / 2,
          ));
    }
  }

  void _drawTradeDaysGridlines(canvas, PainterParams params) {
    List<double> gridShadePoints = [];
    final candle0 = params.candles[0];
    int timestamp0 = candle0.timestamp;
    int i = 0;
    bool lastPointEndSession = false;
    bool lastPointStartSession = false;
    while (i < params.candles.length) {
      int timestamp = params.candles[i].timestamp;
      DateTime dateTimeStart = DateTime.fromMillisecondsSinceEpoch(timestamp);
      timestamp = params.candles[i].timestamp + params.candleTimePeriod;
      DateTime dateTimeEnd = DateTime.fromMillisecondsSinceEpoch(timestamp);
      // artifically adjusted 1 second
      DateTime sessionStart = DateTime(
          dateTimeStart.year, dateTimeStart.month, dateTimeStart.day, 9, 30, 1);
      DateTime sessionEnd = DateTime(
          dateTimeEnd.year, dateTimeEnd.month, dateTimeEnd.day, 15, 59, 59);
      if (dateTimeStart.isBefore(sessionStart) &&
          dateTimeEnd.isAfter(sessionStart)) {
        double dx = sessionStart.difference(dateTimeStart).inMilliseconds /
            params.candleTimePeriod;
        if (gridShadePoints.isEmpty) {
          gridShadePoints.add(-0.1);
        }
        if (lastPointStartSession) {
          // close previous one before opening new
          //open previous before closing
          gridShadePoints.add(gridShadePoints.last + 0.0001);
        }
        gridShadePoints.add(i + dx);
        lastPointEndSession = false;
        lastPointStartSession = true;
      }
      if (dateTimeStart.isBefore(sessionEnd) &&
          dateTimeEnd.isAfter(sessionEnd)) {
        double dx = sessionEnd.difference(dateTimeStart).inMilliseconds /
            params.candleTimePeriod;
        if (lastPointEndSession) {
          //open previous before closing
          gridShadePoints.add(gridShadePoints.last + 0.0001);
        }
        gridShadePoints.add(i + dx);
        lastPointEndSession = true;
        lastPointStartSession = false;
      }
      i++;
    }
    if (lastPointEndSession) {
      // add end of screen
      gridShadePoints.add(params.candles.length + 0.1);
    }
    // if the all are in off day trade
    if (gridShadePoints.length == 0) {
      int timestamp = params.candles.first.timestamp;
      DateTime dateTimeStart = DateTime.fromMillisecondsSinceEpoch(timestamp);
      timestamp = params.candles.last.timestamp + params.candleTimePeriod;
      DateTime dateTimeEnd = DateTime.fromMillisecondsSinceEpoch(timestamp);
      DateTime sessionStart = DateTime(
          dateTimeStart.year, dateTimeStart.month, dateTimeStart.day, 9, 30, 1);
      DateTime sessionEnd = DateTime(
          dateTimeEnd.year, dateTimeEnd.month, dateTimeEnd.day, 15, 59, 59);
      if (dateTimeStart.isAfter(sessionEnd) &&
          dateTimeEnd.isBefore(sessionStart)) {
        gridShadePoints.add(0);
        gridShadePoints.add(params.chartWidth / params.candleWidth);
      }
    }
    /*
    if ((gridShadePoints.length % 2) == 1) {
      print(DateTime.now().toString() + ':'+"Error: " + gridShadePoints.toString());
    } else {
      print(DateTime.now().toString() + ':'+"Good: " + gridShadePoints.toString());
    }
    */
    if (gridShadePoints.length % 2 == 0) {
      for (int i = 0; i < gridShadePoints.length; i += 2) {
        if (((gridShadePoints[i + 1] * params.candleWidth) -
                (gridShadePoints[i] * params.candleWidth)) <
            1) {
          /*
          print(DateTime.now().toString() + ':'+"Line from " +
              ((gridShadePoints[i] * params.candleWidth).round() + 0.0)
                  .toString() +
              " to " +
              ((gridShadePoints[i] * params.candleWidth).round() + 0.0)
                  .toString());*/
          canvas.drawLine(
              Offset(
                  (gridShadePoints[i] * params.candleWidth -
                              params.candleWidth / 2)
                          .round() -
                      0.0,
                  0),
              Offset(
                  (gridShadePoints[i] * params.candleWidth -
                              params.candleWidth / 2)
                          .round() -
                      0.0,
                  params.chartHeight),
              Paint()
                ..color = Colors.grey.shade200
                ..strokeWidth = 5.0
                ..style = PaintingStyle.stroke);
        } else {
          canvas.drawRect(
              Rect.fromLTRB(
                  gridShadePoints[i] * params.candleWidth -
                      params.candleWidth / 2,
                  0,
                  gridShadePoints[i + 1] * params.candleWidth -
                      params.candleWidth / 2,
                  params.chartHeight),
              Paint()..color = params.style.secondaryBackgroundColor);
        }
      }
    }
  }

  // rotate canvas by angle
  void rotate(
      {required Canvas canvas,
      required double cx,
      required double cy,
      required double angle}) {
    canvas.translate(cx, cy);
    canvas.rotate(angle);
    canvas.translate(-cx, -cy);
  }

  void _drawSingleDay(canvas, PainterParams params, int i) {
    final candle = params.candles[i];
    final candleStartTimestamp = candle.timestamp;
    final candleEndTimestamp = candleStartTimestamp + params.candleTimePeriod;
    final x = i * params.candleWidth;
    final thickWidth = max(params.candleWidth * 0.8, 0.8);
    final thinWidth = max(params.candleWidth * 0.1, 0.1);
    final volumeWidth = max(params.candleWidth * 0.9, 0.9);
    //print(DateTime.now().toString() + ':'+
    //    'candle width ${params.candleWidth} thick $thickWidth thin $thinWidth');
    // plot benchamrks
    if (candle.benchmarks.isNotEmpty) {
      candle.benchmarks.forEach((element) {
        final open = element!.open;
        final close = element.close;
        final high = element.high;
        final low = element.low;
        if (open != null && close != null) {
          final color = open == close
              ? params.style.volumeColor
              : (open > close
                  ? params.style.priceLossColor.withAlpha(180)
                  : params.style.priceProfitColor.withAlpha(180));

          if (high != null && low != null) {
            final top = open > close ? open : close;
            final bottom = open < close ? open : close;
            canvas.drawLine(
              Offset(x, params.fitBenchmark(high)),
              Offset(x, params.fitBenchmark(top)),
              Paint()
                ..strokeWidth = thinWidth
                ..style = PaintingStyle.stroke
                ..color = color,
            );
            canvas.drawLine(
              Offset(x, params.fitBenchmark(bottom)),
              Offset(x, params.fitBenchmark(low)),
              Paint()
                ..strokeWidth = thinWidth
                ..style = PaintingStyle.stroke
                ..color = color,
            );
          }
          if (open == close) {
            canvas.drawLine(
              Offset(x - thickWidth / 2, params.fitBenchmark(open)),
              Offset(x + thickWidth / 2, params.fitBenchmark(close)),
              Paint()
                ..strokeWidth = thinWidth
                ..style = PaintingStyle.stroke
                ..color = color,
            );
          } else {
            canvas.drawRect(
              Rect.fromLTRB(
                x - thickWidth / 2,
                params.fitBenchmark(open),
                x + thickWidth / 2,
                params.fitBenchmark(close),
              ),
              Paint()
                ..strokeWidth = thinWidth
                ..style = PaintingStyle.stroke
                ..color = color,
            );
          }
        }

        // plot averages for benchmark candles
        // Draw trend line
        for (int j = 0; j < element.trends.length; j++) {
          Paint trendLinePaint = params.style.trendLineStyles.at(j) ??
              (Paint()
                ..strokeWidth = 2.0
                ..strokeCap = StrokeCap.round
                ..color = Colors.blue);
          Paint bencharkTrendLinePaint = Paint()
            ..strokeWidth = trendLinePaint.strokeWidth
            ..strokeCap = trendLinePaint.strokeCap
            ..color = trendLinePaint.color.withOpacity(0.5);

          final pt = element.trends.at(j); // current data point
          // TODO sometimes exception here happens ???
          try {
            int idx = 1;
            //while (params.candles.at(i - idx)?.benchmarks.isEmpty ?? false) {
            //  idx++;
            //}
            final prevPt =
                params.candles.at(i - idx)?.benchmarks.first?.trends.at(j);
            if (pt != null && prevPt != null) {
              canvas.drawLine(
                Offset(x - params.candleWidth, params.fitBenchmark(prevPt)),
                Offset(x, params.fitBenchmark(pt)),
                bencharkTrendLinePaint,
              );
            }
          } catch (e) {
            print(DateTime.now().toString() + ':' + ' ' + e.toString());
          }

          if (i == 0) {
            // In the front, draw an extra line connecting to out-of-window data
            if (pt != null && params.leadingBenchmarkTrends?.at(j) != null) {
              canvas.drawLine(
                Offset(x - params.candleWidth,
                    params.fitBenchmark(params.leadingBenchmarkTrends!.at(j)!)),
                Offset(x, params.fitBenchmark(pt)),
                bencharkTrendLinePaint,
              );
            }
          } else if (i == params.candles.length - 1) {
            // At the end, draw an extra line connecting to out-of-window data
            if (pt != null && params.trailingBenchmarkTrends?.at(j) != null) {
              canvas.drawLine(
                Offset(x, params.fitBenchmark(pt)),
                Offset(
                  x + params.candleWidth,
                  params.fitBenchmark(params.trailingBenchmarkTrends!.at(j)!),
                ),
                bencharkTrendLinePaint,
              );
            }
          }
        } // for trendlines
      });
    }

    // Draw price bar
    final open = candle.open;
    final close = candle.close;
    final high = candle.high;
    final low = candle.low;

    if (open != null && close != null) {
      final color = open == close
          ? params.style.volumeColor
          : (open > close
              ? params.style.priceLossColor
              : params.style.priceProfitColor);

      if (high != null && low != null) {
        canvas.drawLine(
          Offset(x, params.fitPrice(high)),
          Offset(x, params.fitPrice(low)),
          Paint()
            ..strokeWidth = thinWidth
            ..style = PaintingStyle.stroke
            ..color = color,
        );
      }
      if (open == close) {
        canvas.drawLine(
          Offset(x - thickWidth / 2, params.fitPrice(open)),
          Offset(x + thickWidth / 2, params.fitPrice(close)),
          Paint()
            ..strokeWidth = thinWidth
            ..style = PaintingStyle.stroke
            ..color = color,
        );
      } else {
        canvas.drawLine(
          Offset(x, params.fitPrice(open)),
          Offset(x, params.fitPrice(close)),
          Paint()
            ..strokeWidth = thickWidth
            ..style = PaintingStyle.stroke
            ..color = color,
        );
      }
    }
    if (params.showVolume) {
      // Draw volume bar
      final volume = candle.volume;
      if (volume != null) {
        Color color = params.style.volumeColor.withAlpha(200);
        if (open != null && close != null) {
          color = open == close
              ? params.style.volumeColor
              : (open > close
                  ? params.style.priceLossColor.withAlpha(200)
                  : params.style.priceProfitColor.withAlpha(200));
        }
        canvas.drawLine(
          Offset(x, params.chartHeight),
          Offset(x, params.fitVolume(volume)),
          Paint()
            ..strokeWidth = volumeWidth
            ..style = PaintingStyle.stroke
            ..color = color,
        );
      }
    } else {
      // if not Volume then maybe P&L ?
      final pl = candle.pl;
      Color color = params.style.volumeColor.withAlpha(200);
      if (pl != null) {
        pl > 0
            ? color = params.style.priceProfitColor.withAlpha(200)
            : pl < 0
                ? color = params.style.priceLossColor.withAlpha(200)
                : color = params.style.volumeColor.withAlpha(200);
        if (pl == 0) {
          double spread = (params.maxPL - params.minPL).abs();
          double zeroSpread = 0.1;
          if (spread < 1) {
            zeroSpread = 0.01;
          }
          canvas.drawLine(
            Offset(x, params.fitPL(-zeroSpread)),
            Offset(x, params.fitPL(zeroSpread)),
            Paint()
              ..strokeWidth = volumeWidth
              ..style = PaintingStyle.stroke
              ..color = color,
          );
        } else {
          canvas.drawLine(
            Offset(x, params.fitPL(0)),
            Offset(x, params.fitPL(pl)),
            Paint()
              ..strokeWidth = volumeWidth
              ..style = PaintingStyle.stroke
              ..color = color,
          );
        }
      }
    }
    // Draw trend line
    for (int j = 0; j < candle.trends.length; j++) {
      final trendLinePaint = params.style.trendLineStyles.at(j) ??
          (Paint()
            ..strokeWidth = 2.0
            ..strokeCap = StrokeCap.round
            ..color = Colors.blue);

      final pt = candle.trends.at(j); // current data point
      final prevPt = params.candles.at(i - 1)?.trends.at(j);
      if (pt != null && prevPt != null) {
        canvas.drawLine(
          Offset(x - params.candleWidth, params.fitPrice(prevPt)),
          Offset(x, params.fitPrice(pt)),
          trendLinePaint,
        );
      }
      if (i == 0) {
        // In the front, draw an extra line connecting to out-of-window data
        if (pt != null && params.leadingTrends?.at(j) != null) {
          canvas.drawLine(
            Offset(x - params.candleWidth,
                params.fitPrice(params.leadingTrends!.at(j)!)),
            Offset(x, params.fitPrice(pt)),
            trendLinePaint,
          );
        }
      } else if (i == params.candles.length - 1) {
        // At the end, draw an extra line connecting to out-of-window data
        if (pt != null && params.trailingTrends?.at(j) != null) {
          canvas.drawLine(
            Offset(x, params.fitPrice(pt)),
            Offset(
              x + params.candleWidth,
              params.fitPrice(params.trailingTrends!.at(j)!),
            ),
            trendLinePaint,
          );
        }
      }
    }
    // Draw PRI
    for (int j = 0; j < candle.indicators.length; j++) {
      final indicatorLinePaint = params.style.indicatorLineStyles.at(j) ??
          (Paint()
            ..strokeWidth = 2.0
            ..strokeCap = StrokeCap.round
            ..color = params.style.priceProfitColor);
      final pt = candle.indicators.at(j); // current data point
      final prevPt = params.candles.at(i - 1)?.indicators.at(j);
      if (pt != null && prevPt != null) {
        canvas.drawLine(
          Offset(x - params.candleWidth, params.fitInd(prevPt)),
          Offset(x, params.fitInd(pt)),
          indicatorLinePaint,
        );
      }
    }
  }

  /// Darken a color by [percent] amount (100 = black)
// ........................................................
  Color darken(Color c, [int percent = 10]) {
    assert(1 <= percent && percent <= 100);
    var f = 1 - percent / 100;
    return Color.fromARGB(c.alpha, (c.red * f).round(), (c.green * f).round(),
        (c.blue * f).round());
  }

  /// Lighten a color by [percent] amount (100 = white)
// ........................................................
  Color lighten(Color c, [int percent = 10]) {
    assert(1 <= percent && percent <= 100);
    var p = percent / 100;
    return Color.fromARGB(
        c.alpha,
        c.red + ((255 - c.red) * p).round(),
        c.green + ((255 - c.green) * p).round(),
        c.blue + ((255 - c.blue) * p).round());
  }

  bool _drawSingleDayMarkers(
      canvas, PainterParams params, int index, MarkerElement element) {
    final candle = params.candles[index];
    final candleStartTimestamp = candle.timestamp;
    final candleEndTimestamp = candleStartTimestamp + params.candleTimePeriod;
    final x = index * params.candleWidth;
    final thickWidth = max(params.candleWidth * 0.8, 0.8);
    final thinWidth = max(params.candleWidth * 0.2, 0.2);
    final extraThinWidth = max(params.candleWidth * 0.1, 0.1);
    bool painted = false;
    bool priceProblem = false;
    // Draw ovelaping markers which are in range of candles
    final markers = params.markers.where((element) =>
        element.timestamp >= candleStartTimestamp &&
        element.timestamp < candleEndTimestamp);
    // sometimes there is missing candle due to circut braker
    // when to show prices inside marks and loose side price
    int _showPriceCandlesLimit = isMobile() ? 15 : 30;
    int _showCircleCandleLimit = isMobile() ? 80 : 120;
    double _markerCircleScale = isMobile() ? 3.0 : 2.0;
    int visibeMarkersCount = markers.length;
    markers.forEach((marker) {
      double y = params.fitPrice(marker.price ?? 0.0);
      // check that y is not lower than low on candle,
      // if yes bring it to 0 level
      double yLow = params.fitPrice(candle.low ?? 0.0);
      if (y > (yLow + params.candleWidth)) {
        // show it on the borrom of chart
        if (y > params.chartHeight) {
          y = params.chartHeight - params.candleWidth;
        }
        priceProblem = true;
      }
      // first draw all lines then markers on top
      switch (element) {
        case MarkerElement.marker:
          {
            canvas.save();
            // rotate to draw square diamonds
            rotate(canvas: canvas, cx: x, cy: y, angle: 45 * pi / 180.0);
            // TODO decide on number of candles
            // draw circles so tardes are easier visible
            /*if (params.candles.length > _showCircleCandleLimit) {
              canvas.drawCircle(
                Offset(x, y),
                params.candleWidth * _markerCircleScale,
                Paint()
                  ..color = priceProblem
                      ? Colors.orange
                      : (marker.color ?? Colors.transparent),
              );
            }*/
            double scale = 0.5;
            // if selected increase size
            if (marker.selected ?? false) scale = 0.75;
            canvas.drawRect(
              Rect.fromCenter(
                center: Offset(x, y),
                width: max(params.candleWidth, 14) * scale,
                height: max(params.candleWidth, 14) * scale,
              ),
              Paint()
                ..color = priceProblem
                    ? Colors.orange
                    : (marker.color ?? Colors.transparent)
                ..style = PaintingStyle.fill,
            );
            Rect markerRect = Rect.fromCenter(
                center: Offset(x, y),
                width: max(params.candleWidth, 14) * scale + 0.1,
                height: max(params.candleWidth, 14) * scale + 0.1);
            Rect tapRect = Rect.fromCenter(
                center: Offset(x, y),
                width: max(params.candleWidth, 14),
                height: max(params.candleWidth, 14));
            canvas.drawRect(
              markerRect,
              Paint()
                ..strokeWidth = extraThinWidth
                ..style = PaintingStyle.stroke
                ..color = marker.borderColor ?? Colors.black,
            );
            // increase tap size, specially when it gets rotated back to square
            visibleMarkersRect.add(Tuple2(index, tapRect));
            marker.setRect(tapRect);
            canvas.restore();
            double price = marker.price ?? 0.0;
            // TODO check number of candles
            /*
            if (params.candles.length <= _showPriceCandlesLimit) {
              // show trade price inside diamond
              final priceTp = TextPainter(
                text: TextSpan(
                  text: getPriceLabel(price),
                  style: TextStyle(
                    color: marker.markerPriceColor,
                    fontWeight: FontWeight.bold,
                    fontSize: params.candleWidth / 3.0,
                  ),
                ),
              ) // TextStyle
                ..textDirection = TextDirection.ltr
                ..layout();
              priceTp.paint(
                  canvas,
                  Offset(
                    x - priceTp.width / 2,
                    y - priceTp.height / 2,
                  ));
              painted = true;
            }
            */
          }
          break;

        case MarkerElement.priceLine:
          {
            // plot trade price line in specific color
            // if requested by marker
            if (marker.showPriceLine ?? false) {
              canvas.drawLine(
                Offset(-1, y),
                Offset(params.chartWidth, y),
                Paint()
                  ..strokeWidth = 2.0
                  ..color = marker.priceLineStyle?.color ?? Colors.transparent,
              );
              if (marker.stopPrices.isNotEmpty) {
                for (Tuple2<DateTime, double> stopPrice in marker.stopPrices) {
                  double yPrice = params.fitPrice(stopPrice.item2);
                  if (yPrice > 0 && yPrice < params.chartHeight) {
                    canvas.drawLine(
                      Offset(-1, yPrice),
                      Offset(params.chartWidth, yPrice),
                      Paint()
                        ..strokeWidth = 2.0
                        ..color =
                            marker.stopLineStyle?.color ?? Colors.transparent,
                    );
                  }
                }
              }
              if (marker.limitPrices.isNotEmpty) {
                for (Tuple2<DateTime, double> limitPrice
                    in marker.limitPrices) {
                  double yPrice = params.fitPrice(limitPrice.item2);
                  if (yPrice > 0 && yPrice < params.chartHeight) {
                    canvas.drawLine(
                      Offset(-1, yPrice),
                      Offset(params.chartWidth, yPrice),
                      Paint()
                        ..strokeWidth = 2.0
                        ..color =
                            marker.limitLineStyle?.color ?? Colors.transparent,
                    );
                  }
                }
              }
              if (marker.price != null) {
                double textOffset = 5;
                double pricePos = params.fitPrice(marker.price!);
                double height = (marker.priceLineStyle!.fontSize ?? 18.0) + 5;
                if (params.showRLines) {
                  textOffset = 110;
                } else {
                  for (int o = 0; o < marker.stopPrices.length; o++) {
                    double stopPos =
                        params.fitPrice(marker.stopPrices[o].item2);
                    if ((stopPos - pricePos).abs() < height) {
                      textOffset = 70;
                      break;
                    }
                  }
                  if (textOffset == 5) {
                    for (int o = 0; o < marker.limitPrices.length; o++) {
                      double limitPos =
                          params.fitPrice(marker.limitPrices[o].item2);
                      if ((limitPos - pricePos).abs() < height) {
                        textOffset = 70;
                        break;
                      }
                    }
                  }
                  // is buy on top of sell ? How to check it ?
                }
                final priceTp3 = TextPainter(
                  text: TextSpan(
                    text: marker.side,
                    style: TextStyle(
                      color: marker.priceLineStyle!.color,
                      fontSize: marker.priceLineStyle!.fontSize ?? 14.0,
                    ),
                  ),
                )
                  ..textDirection = TextDirection.ltr
                  ..layout();
                priceTp3.paint(
                    canvas,
                    Offset(
                      textOffset,
                      pricePos - (priceTp3.height + 2),
                    ));
              }
              painted = true;
            }
          }
          break;
        case MarkerElement.limitStopLines:
          {
            if (params.showRLines) {
              for (int i = 0; i < marker.limitRList.length; i++) {
                double yPrice = params.fitPrice(marker.limitRList[i].item2);
                if (yPrice > 0 && yPrice < params.chartHeight) {
                  canvas.drawLine(
                    Offset(-1, yPrice),
                    Offset(params.chartWidth, yPrice),
                    Paint()
                      ..strokeWidth = 2.0
                      ..color = darken(
                          marker.limitLineStyle?.color ?? Colors.transparent,
                          (i + 1) * 5),
                  );
                }
              }
              for (int i = 0; i < marker.stopRList.length; i++) {
                double yPrice = params.fitPrice(marker.stopRList[i].item2);
                if (yPrice > 0 && yPrice < params.chartHeight) {
                  canvas.drawLine(
                    Offset(-1, yPrice),
                    Offset(params.chartWidth, yPrice),
                    Paint()
                      ..strokeWidth = 2.0
                      ..color = darken(
                          marker.stopLineStyle?.color ?? Colors.transparent,
                          (i + 1) * 5),
                  );
                }
              }
            }
          }
          break;
        case MarkerElement.priceLabel:
          {
            if (marker.price != null) {
              final priceTp = TextPainter(
                text: TextSpan(
                  text: getPriceLabel(marker.price!),
                  style: marker.priceLineStyle,
                ),
              )
                ..textDirection = TextDirection.ltr
                ..layout();
              priceTp.paint(
                  canvas,
                  Offset(
                    params.chartWidth - (priceTp.width + 2),
                    y - (priceTp.height + 2),
                  ));
            }
            if (marker.stopPrices.isNotEmpty) {
              for (Tuple2<DateTime, double> stopPrice in marker.stopPrices) {
                double yPrice = params.fitPrice(stopPrice.item2);
                if (yPrice > 0 && yPrice < params.chartHeight) {
                  final priceTp = TextPainter(
                    text: TextSpan(
                      text: getPriceLabel(stopPrice.item2),
                      style: marker.stopLineStyle,
                    ),
                  )
                    ..textDirection = TextDirection.ltr
                    ..layout();
                  priceTp.paint(
                      canvas,
                      Offset(
                        params.chartWidth - (priceTp.width + 2),
                        yPrice - (priceTp.height + 2),
                      ));

                  final priceTp2 = TextPainter(
                    text: TextSpan(
                      text: "STOP",
                      style: TextStyle(
                        color: marker.stopLineStyle!.color,
                        fontSize: marker.stopLineStyle!.fontSize ?? 14.0,
                      ),
                    ),
                  )
                    ..textDirection = TextDirection.ltr
                    ..layout();
                  priceTp2.paint(
                      canvas,
                      Offset(
                        params.showRLines ? 70 : 5,
                        yPrice - (priceTp2.height + 2),
                      ));
                }
              }
              if (marker.limitPrices.isNotEmpty) {
                for (Tuple2<DateTime, double> limitPrice
                    in marker.limitPrices) {
                  double yPrice = params.fitPrice(limitPrice.item2);
                  if (yPrice > 0 && yPrice < params.chartHeight) {
                    final priceTp = TextPainter(
                      text: TextSpan(
                          text: getPriceLabel(limitPrice.item2),
                          style: marker.limitLineStyle),
                    )
                      ..textDirection = TextDirection.ltr
                      ..layout();
                    priceTp.paint(
                        canvas,
                        Offset(
                          params.chartWidth - (priceTp.width + 2),
                          yPrice - (priceTp.height + 2),
                        ));
                    final priceTp2 = TextPainter(
                      text: TextSpan(
                        text: "LIMIT",
                        style: TextStyle(
                            color: marker.limitLineStyle!.color,
                            fontSize: marker.limitLineStyle!.fontSize ?? 14.0),
                      ),
                    )
                      ..textDirection = TextDirection.ltr
                      ..layout();
                    priceTp2.paint(
                        canvas,
                        Offset(
                          params.showRLines ? 70 : 5,
                          yPrice - (priceTp2.height + 2),
                        ));
                  }
                }
              }
              painted = true;
            }
          }
          break;
        case MarkerElement.limitStopPrices:
          {
            for (int i = 0; i < marker.limitRList.length; i++) {
              y = params.fitPrice(marker.limitRList[i].item2);
              final priceTp = TextPainter(
                text: TextSpan(
                  text: getPriceLabel(marker.limitRList[i].item2),
                  style: TextStyle(
                      color: darken(
                          marker.limitLineStyle?.color ?? Colors.transparent,
                          (i + 1) * 5)),
                ),
              )
                ..textDirection = TextDirection.ltr
                ..layout();
              priceTp.paint(
                  canvas,
                  Offset(
                    params.chartWidth - (priceTp.width + 2),
                    y - (priceTp.height + 2),
                  ));

              final priceTp2 = TextPainter(
                text: TextSpan(
                  text: '${marker.limitRList[i].item1} R LIMIT',
                  style: TextStyle(
                    color: darken(
                        marker.limitLineStyle?.color ?? Colors.transparent,
                        (i + 1) * 5),
                    fontSize: marker.stopLineStyle!.fontSize ?? 14.0,
                  ),
                ),
              )
                ..textDirection = TextDirection.ltr
                ..layout();
              priceTp2.paint(
                  canvas,
                  Offset(
                    5,
                    y - (priceTp2.height + 2),
                  ));
            }
            for (int i = 0; i < marker.stopRList.length; i++) {
              y = params.fitPrice(marker.stopRList[i].item2);
              final priceTp = TextPainter(
                text: TextSpan(
                  text: getPriceLabel(marker.stopRList[i].item2),
                  style: TextStyle(
                      color: darken(
                          marker.stopLineStyle?.color ?? Colors.transparent,
                          (i + 1) * 5)),
                ),
              )
                ..textDirection = TextDirection.ltr
                ..layout();
              priceTp.paint(
                  canvas,
                  Offset(
                    params.chartWidth - (priceTp.width + 2),
                    y - (priceTp.height + 2),
                  ));

              final priceTp2 = TextPainter(
                text: TextSpan(
                  text: '${marker.stopRList[i].item1} R STOP',
                  style: TextStyle(
                      color: darken(
                          marker.stopLineStyle?.color ?? Colors.transparent,
                          (i + 1) * 5),
                      fontSize: marker.stopLineStyle!.fontSize ?? 14.0),
                ),
              )
                ..textDirection = TextDirection.ltr
                ..layout();
              priceTp2.paint(
                  canvas,
                  Offset(
                    5,
                    y - (priceTp2.height + 2),
                  ));
            }
          }
          break;
        case MarkerElement.timeLine:
          {
            double xx = index * params.candleWidth;
            // plot trade price line in specific color
            // if requested by marker
            if (marker.showMarkerTimeLine ?? false) {
              canvas.drawLine(
                Offset(xx, y),
                Offset(xx, params.chartHeight),
                Paint()
                  ..strokeWidth = 2.0
                  ..color = marker.priceLineStyle?.color ?? Colors.transparent,
              );
              painted = true;
            }
          }
          break;
        case MarkerElement.timeLabel:
          {
            double xx = index * params.candleWidth;
            if (marker.showMarkerTimeLine ?? false) {
              final timeTp = TextPainter(
                text: TextSpan(
                  text: getTimeLabel(marker.timestamp, visibeMarkersCount),
                  style: TextStyle(
                      color: marker.color, fontSize: isMobile() ? 12.0 : 14.0),
                ),
              )
                ..textDirection = TextDirection.ltr
                ..layout();
              final topPadding = 0;
              //params.style.timeLabelHeight - timeTp.height;
              Offset delta = Offset(
                xx - (timeTp.height * 2),
                params.chartHeight - params.volumeHeight - 2,
              );
              Offset center = Offset(
                  xx - timeTp.width / 2, params.chartHeight + topPadding);

              // rotate for 1 min only
              //if (params.candleTimePeriod == 60 * 1000) {
              Offset pivot = timeTp.size.center(delta);
              canvas.save();
              canvas.translate(pivot.dx, pivot.dy);
              canvas.rotate(-pi / 2);
              canvas.translate(-pivot.dx, -pivot.dy);
              timeTp.paint(canvas, delta);
              canvas.restore();
              //} else {
              //  timeTp.paint(canvas, center);
              //}
              painted = true;
            }
          }
          break;
      }
    });
    return painted;
  }

  void _drawTapHighlightAndOverlay(canvas, PainterParams params) {
    final pos = params.tapPosition!;
    // first check if there is marker in this place:
    final index =
        visibleMarkersRect.lastIndexWhere((tuple) => tuple.item2.contains(pos));
    if (index != -1) {
      final markerIndex = visibleMarkersRect[index].item1;
      // it will be handled in th echart do not draw anything.
    } else {
      final i = params.getCandleIndexFromOffset(pos.dx);
      final candle = params.candles[i];
      canvas.save();
      canvas.translate(params.xShift, 0.0);
      // Draw highlight bar (selection box)
      canvas.drawLine(
          Offset(i * params.candleWidth, 0.0),
          Offset(i * params.candleWidth, params.chartHeight),
          Paint()
            ..strokeWidth = max(params.candleWidth * 0.88, 1.0)
            ..color = params.style.selectionHighlightColor);
      canvas.restore();
      // Draw info pane
      _drawTapInfoOverlay(canvas, params, candle);
    }
  }

  void _drawTapInfoOverlay(canvas, PainterParams params, CandleData candle) {
    final xGap = 8.0;
    final yGap = 4.0;

    TextPainter makeTP(String text) => TextPainter(
          text: TextSpan(
            text: text,
            style: params.style.overlayTextStyle,
          ),
        )
          ..textDirection = TextDirection.ltr
          ..layout();

    final info = getOverlayInfo(candle);
    if (info.isEmpty) return;
    final labels = info.keys.map((text) => makeTP(text)).toList();
    final values = info.values.map((text) => makeTP(text)).toList();

    final labelsMaxWidth = labels.map((tp) => tp.width).reduce(max);
    final valuesMaxWidth = values.map((tp) => tp.width).reduce(max);
    final panelWidth = labelsMaxWidth + valuesMaxWidth + xGap * 3;
    final panelHeight = max(
          labels.map((tp) => tp.height).reduce((a, b) => a + b),
          values.map((tp) => tp.height).reduce((a, b) => a + b),
        ) +
        yGap * (values.length + 1);

    // Shift the canvas, so the overlay panel can appear near touch position.
    canvas.save();
    final pos = params.tapPosition!;
    final fingerSize = 32.0; // leave some margin around user's finger
    double dx, dy;
    assert(params.size.width >= panelWidth, "Overlay panel is too wide.");
    if (pos.dx <= params.size.width / 2) {
      // If user touches the left-half of the screen,
      // we show the overlay panel near finger touch position, on the right.
      dx = pos.dx + fingerSize;
    } else {
      // Otherwise we show panel on the left of the finger touch position.
      dx = pos.dx - panelWidth - fingerSize;
    }
    dx = dx.clamp(0, params.size.width - panelWidth);
    dy = pos.dy - panelHeight - fingerSize;
    if (dy < 0) dy = 0.0;
    canvas.translate(dx, dy);

    // Draw the background for overlay panel
    canvas.drawRRect(
        RRect.fromRectAndRadius(
          Offset.zero & Size(panelWidth, panelHeight),
          Radius.circular(8),
        ),
        Paint()..color = params.style.overlayBackgroundColor);

    // Draw texts
    var y = 0.0;
    for (int i = 0; i < labels.length; i++) {
      y += yGap;
      final rowHeight = max(labels[i].height, values[i].height);
      // Draw labels (left align, vertical center)
      final labelY = y + (rowHeight - labels[i].height) / 2; // vertical center
      labels[i].paint(canvas, Offset(xGap, labelY));

      // Draw values (right align, vertical center)
      final leading = valuesMaxWidth - values[i].width; // right align
      final valueY = y + (rowHeight - values[i].height) / 2; // vertical center
      values[i].paint(
        canvas,
        Offset(labelsMaxWidth + xGap * 2 + leading, valueY),
      );
      y += rowHeight;
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(ChartPainter oldDelegate) =>
      params.shouldRepaint(oldDelegate.params);
}

extension ElementAtOrNull<E> on List<E> {
  E? at(int index) {
    if (index < 0 || index >= length) return null;
    return elementAt(index);
  }
}
