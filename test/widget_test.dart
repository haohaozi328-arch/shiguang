import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguanlast/data/in_memory_app_repository.dart';
import 'package:shiguanlast/data/seed_data.dart';
import 'package:shiguanlast/main.dart';

void main() {
  testWidgets('app boots', (tester) async {
    final repository = InMemoryAppRepository();
    await SeedData.ensureInitialized(repository);
    await tester.pumpWidget(ShiguangApp(repository: repository));
    await tester.pump(const Duration(milliseconds: 1600));
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
