import 'package:alexis_system/models/workshop_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WorkshopStatus.next', () {
    test('moves active statuses forward in production order', () {
      expect(WorkshopStatus.measuring.next, WorkshopStatus.cutting);
      expect(WorkshopStatus.cutting.next, WorkshopStatus.sewing);
      expect(WorkshopStatus.sewing.next, WorkshopStatus.finishing);
      expect(WorkshopStatus.finishing.next, WorkshopStatus.completed);
    });

    test('returns null for terminal statuses', () {
      expect(WorkshopStatus.completed.next, isNull);
      expect(WorkshopStatus.archived.next, isNull);
    });
  });
}
