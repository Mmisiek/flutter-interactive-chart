import 'package:flutter/material.dart';

enum MarkerElement {
  priceLine,
  priceLabel,
  marker,
  markerLabel,
  timeLine,
  timeLabel
}

class MarkerData {
  final int timestamp;
  final double? price;
  final String? side;
  final String? type;
  final Color? color;
  final bool? showPriceLine;
  final bool? showMarkerTimeLine;
  final TextStyle? priceLineStyle;
  final bool? showMarkerPrice;
  final Color? markerPriceColor;

  MarkerData(this.timestamp,
      {this.price,
      this.side,
      this.type,
      this.color,
      this.showPriceLine = true,
      this.showMarkerTimeLine = true,
      this.priceLineStyle = const TextStyle(
          fontSize: 14.0, color: Colors.black, fontWeight: FontWeight.bold),
      this.showMarkerPrice = true,
      this.markerPriceColor = Colors.black});
}
