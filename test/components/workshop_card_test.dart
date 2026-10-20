import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexis_system/components/workshop_card.dart';
import 'package:alexis_system/models/workshop_order.dart';
import 'package:alexis_system/models/workshop_status.dart';

void main() {
  WorkshopOrder order({required WorkshopStatus status}) => WorkshopOrder(
    id: 'o1',
    orderId: '14039',
    customer: 'Chan Tai Man',
    item: 'VBC Jacket',
    status: status,
    priority: 'normal',
    dueDate: DateTime(2026, 12, 1),
    progress: 0,
  );

  Future<void> pump(WidgetTester tester, Widget card) =>
      tester.pumpWidget(MaterialApp(home: Scaffold(body: card)));

  group('WorkshopCard archive button', () {
    testWidgets('shows and triggers onArchive when the order is completed', (
      tester,
    ) async {
      var archived = false;
      await pump(
        tester,
        WorkshopCard(
          order: order(status: WorkshopStatus.completed),
          onTap: () {},
          onArchive: () => archived = true,
        ),
      );

      final archiveButton = find.byTooltip('Archive Order');
      expect(archiveButton, findsOneWidget);

      await tester.tap(archiveButton);
      expect(archived, isTrue);
    });

    testWidgets(
      'is hidden when the order is completed but onArchive is null',
      (tester) async {
        await pump(
          tester,
          WorkshopCard(order: order(status: WorkshopStatus.completed), onTap: () {}),
        );

        expect(find.byTooltip('Archive Order'), findsNothing);
      },
    );

    for (final status in [
      WorkshopStatus.measuring,
      WorkshopStatus.cutting,
      WorkshopStatus.sewing,
      WorkshopStatus.finishing,
    ]) {
      testWidgets(
        'is hidden for in-progress orders ($status) even when onArchive is set',
        (tester) async {
          await pump(
            tester,
            WorkshopCard(
              order: order(status: status),
              onTap: () {},
              onArchive: () {},
            ),
          );

          expect(find.byTooltip('Archive Order'), findsNothing);
        },
      );
    }
  });
}
