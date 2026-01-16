// lib/models/workshop_status.dart

enum WorkshopStatus {
  measuring,
  cutting,
  sewing,
  finishing,
  completed,
  archived;

  // 增加一個 helper method 來把 Enum 轉成好看的標題 (例如 "Measuring")
  String get label {
    switch (this) {
      case WorkshopStatus.measuring:
        return 'Measuring';
      case WorkshopStatus.cutting:
        return 'Cutting';
      case WorkshopStatus.sewing:
        return 'Sewing';
      case WorkshopStatus.finishing:
        return 'Finishing';
      case WorkshopStatus.completed:
        return 'Completed';
      case WorkshopStatus.archived:
        return 'Archived';
    }
  }
}
