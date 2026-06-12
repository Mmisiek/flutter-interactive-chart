import 'package:flutter/material.dart';
import 'package:tuple/tuple.dart';

enum MarkerElement {
  priceLine,
  priceLabel,
  marker,
  markerLabel,
  timeLine,
  timeLabel,
  stopLine,
  stopLabel,
  limitLine,
  limitLabel,
  limitStopLines,
  limitStopPrices,
}

class MarkerData {
  final String symbol;
  final int volume;
  final bool isOpen;
  final int timestamp;
  final double? price;
  final String? side;
  final String? type;
  // color can be updated for selection
  Color? color;
  final Color? borderColor;
  final bool? showPriceLine;
  final bool? showMarkerTimeLine;
  final TextStyle? priceLineStyle;
  final bool? showMarkerPrice;
  final Color? markerPriceColor;
  final List<Tuple2<DateTime, double>> stopPrices;
  final List<Tuple2<DateTime, double>> limitPrices;
  final TextStyle? stopLineStyle;
  final TextStyle? limitLineStyle;
  Rect? rect;
  // Limit R lines
  final List<Tuple2<int, double>> limitRList;
  // stop R lines
  final List<Tuple2<int, double>> stopRList;
  bool? selected;

  MarkerData(
      {required this.symbol,
      required this.volume,
      required this.isOpen,
      required this.timestamp,
      this.price,
      this.side,
      this.type,
      this.color,
      this.borderColor,
      this.showPriceLine = true,
      this.showMarkerTimeLine = true,
      this.priceLineStyle = const TextStyle(
          fontSize: 14.0, color: Colors.black, fontWeight: FontWeight.bold),
      this.showMarkerPrice = true,
      this.markerPriceColor = Colors.black,
      this.stopPrices = const [],
      this.limitPrices = const [],
      this.stopLineStyle = const TextStyle(
          fontSize: 14, color: Colors.red, fontWeight: FontWeight.bold),
      this.limitLineStyle = const TextStyle(
          fontSize: 14, color: Colors.green, fontWeight: FontWeight.bold),
      required this.limitRList,
      required this.stopRList,
      this.selected = false});

  void setRect(Rect _rect) => this.rect = _rect;

  void setSelected(bool _selected) => this.selected = _selected;

  void setColor(Color _color) => this.color = _color;
}
