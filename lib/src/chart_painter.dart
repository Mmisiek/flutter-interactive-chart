import 'dart:math';
//import 'dart:web_gl';
import 'package:universal_io/io.dart';

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart' as intl;

import 'candle_data.dart';
import 'painter_params.dart';
import 'marker_data.dart';

typedef TimeLabelGetter = String Function(int timestamp, int visibleDataCount);
typedef PriceLabelGetter = String Function(double price);
typedef OverlayInfoGetter = Map<String, String> Function(CandleData candle);

class ChartPainter extends CustomPainter {
  final PainterParams params;
  final TimeLabelGetter getTimeLabel;
  final PriceLabelGetter getPriceLabel;
  final OverlayInfoGetter getOverlayInfo;

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
    bool skipTimeTicks = false;
    bool skipPriceTicks = false;
    if (params.showMarketsTimeLines) {
      for (int i = 0; i < params.candles.length; i++) {
        skipTimeTicks |=
            _drawSingleDayMarkers(canvas, params, i, MarkerElement.timeLabel);
      }
    }
    if (!skipTimeTicks) {
      // Draw time labels (dates) & price labels only if marker are not shown
      _drawTimeLabels(canvas, params);
    }
    _drawSymbolAndTime(canvas, params);
    if (params.showMarkersPriceLines) {
      // draw line prices on the side
      for (int i = 0; i < params.candles.length; i++) {
        skipPriceTicks |=
            _drawSingleDayMarkers(canvas, params, i, MarkerElement.priceLabel);
      }
    }
    _drawPriceGridAndLabels(canvas, params, skipPriceTicks);
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
    if (params.showMarkersPriceLines) {
      for (int i = 0; i < params.candles.length; i++) {
        _drawSingleDayMarkers(canvas, params, i, MarkerElement.priceLine);
      }
    }
    if (params.showMarketsTimeLines) {
      for (int i = 0; i < params.candles.length; i++) {
        _drawSingleDayMarkers(canvas, params, i, MarkerElement.timeLine);
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
    final opacity = 0.1;

    final symbolTp = TextPainter(
      text: TextSpan(
        text: params.symbolLabel,
        style: TextStyle(
          color: Colors.grey.withOpacity(opacity),
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
          color: Colors.grey.withOpacity(opacity),
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
  }

  // TO DO more price levels and locked by division
  void _drawPriceGridAndLabels(
      canvas, PainterParams params, bool skipPriceTicks) {
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
      if (!skipPriceTicks) {
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
      }
    });
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
    final thinWidth = max(params.candleWidth * 0.2, 0.2);
    // Draw price bar
    final open = candle.open;
    final close = candle.close;
    final high = candle.high;
    final low = candle.low;
    if (open != null && close != null) {
      final color = open > close
          ? params.style.priceLossColor
          : params.style.priceGainColor;
      canvas.drawLine(
        Offset(x, params.fitPrice(open)),
        Offset(x, params.fitPrice(close)),
        Paint()
          ..strokeWidth = thickWidth
          ..color = color,
      );
      if (high != null && low != null) {
        canvas.drawLine(
          Offset(x, params.fitPrice(high)),
          Offset(x, params.fitPrice(low)),
          Paint()
            ..strokeWidth = thinWidth
            ..color = color,
        );
      }
    }
    // Draw volume bar
    final volume = candle.volume;
    if (volume != null) {
      canvas.drawLine(
        Offset(x, params.chartHeight),
        Offset(x, params.fitVolume(volume)),
        Paint()
          ..strokeWidth = thickWidth
          ..color = params.style.volumeColor,
      );
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
  }

  bool _drawSingleDayMarkers(
      canvas, PainterParams params, int i, MarkerElement element) {
    final candle = params.candles[i];
    final candleStartTimestamp = candle.timestamp;
    final candleEndTimestamp = candleStartTimestamp + params.candleTimePeriod;
    final x = i * params.candleWidth;
    final thickWidth = max(params.candleWidth * 0.8, 0.8);
    final thinWidth = max(params.candleWidth * 0.2, 0.2);
    final extraThinWidth = max(params.candleWidth * 0.1, 0.1);
    bool painted = false;
    // Draw ovelaping markers which are in range of candles
    final markers = params.markers.where((element) =>
        element.timestamp >= candleStartTimestamp &&
        element.timestamp <= candleEndTimestamp);
    // when to show prices inside marks and loose side price
    int _showPriceCandlesLimit = isMobile() ? 20 : 40;
    int _showCircleCandleLimit = isMobile() ? 80 : 120;
    double _markerCircleScale = isMobile() ? 3.0 : 2.0;
    int visibeMarkersCount = markers.length;
    markers.forEach((marker) {
      double y = params.fitPrice(marker.price ?? 0.0);
      // first draw all lines then markers on top
      switch (element) {
        case MarkerElement.marker:
          {
            canvas.save();
            // rotate to draw square diamonds
            rotate(canvas: canvas, cx: x, cy: y, angle: 45 * pi / 180.0);
            // TODO decide on number of candles
            // draw circles so tardes are easier visible
            if (params.candles.length > _showCircleCandleLimit) {
              canvas.drawCircle(
                Offset(x, y),
                params.candleWidth * _markerCircleScale,
                Paint()..color = marker.color ?? Colors.transparent,
              );
            }
            canvas.drawRect(
              Rect.fromCenter(
                  center: Offset(x, y),
                  width: params.candleWidth * 1.1,
                  height: params.candleWidth * 1.1),
              Paint()..color = marker.color ?? Colors.transparent,
            );
            canvas.drawRect(
              Rect.fromCenter(
                  center: Offset(x, y),
                  width: params.candleWidth * 1.2,
                  height: params.candleWidth * 1.2),
              Paint()
                ..strokeWidth = extraThinWidth
                ..style = PaintingStyle.stroke
                ..color = Colors.black,
            );
            canvas.restore();

            double price = marker.price ?? 0.0;
            // TODO check number of candles
            if (params.candles.length < _showPriceCandlesLimit) {
              // show trade price inside diamond
              final priceTp = TextPainter(
                text: TextSpan(
                  text: getPriceLabel(price),
                  style: TextStyle(
                    color: marker.markerPriceColor,
                    fontWeight: FontWeight.bold,
                    fontSize: params.candleWidth / 2.0,
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
                  ..strokeWidth = max(thinWidth, 2.0)
                  ..color = marker.priceLineStyle?.color ?? Colors.transparent,
              );
              painted = true;
            }
          }
          break;

        case MarkerElement.priceLabel:
          {
            if (params.candles.length > _showPriceCandlesLimit &&
                marker.price != null) {
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
                    params.chartWidth + 2,
                    y - priceTp.height / 2,
                  ));
              painted = true;
            }
          }
          break;
        case MarkerElement.timeLine:
          {
            // plot trade price line in specific color
            // if requested by marker
            if (marker.showMarkerTimeLine ?? false) {
              canvas.drawLine(
                Offset(x, y),
                Offset(x, params.chartHeight),
                Paint()
                  ..strokeWidth = max(thinWidth, 2.0)
                  ..color = marker.priceLineStyle?.color ?? Colors.transparent,
              );
              painted = true;
            }
          }
          break;
        case MarkerElement.timeLabel:
          {
            if (marker.showMarkerTimeLine ?? false) {
              final timeTp = TextPainter(
                text: TextSpan(
                  text: intl.DateFormat('HH:mm').format(
                      DateTime.fromMillisecondsSinceEpoch(marker.timestamp)),
                  style: TextStyle(color: marker.color, fontSize: 17.0),
                ),
              )
                ..textDirection = TextDirection.ltr
                ..layout();
              final topPadding = params.style.timeLabelHeight - timeTp.height;
              timeTp.paint(
                  canvas,
                  Offset(
                    x - timeTp.width / 2,
                    params.chartHeight + topPadding,
                  ));
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
