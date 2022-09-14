import 'package:flutter/material.dart';

class MarkerData {
  final int timestamp;
  final double? price;
  final String? side;
  final String? type;
  final Color? color;
  final bool? showPriceLine;
  final TextStyle? labelStyle;

  MarkerData(this.timestamp,
      {this.price,
      this.side,
      this.type,
      this.color,
      this.showPriceLine,
      this.labelStyle = const TextStyle(
          fontSize: 14.0, color: Colors.black, fontWeight: FontWeight.bold)});
}
