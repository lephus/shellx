import 'package:flutter/material.dart';

class ItemNotFound extends StatelessWidget {
  const ItemNotFound({
    super.key,
    this.height = 150.0,
    required this.message,
  });

  final double height;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (message.isEmpty == false)
            Text(
              message,
            ),
        ],
      ),
    );
  }
}
