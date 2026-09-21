import 'package:cloud_firestore/cloud_firestore.dart';

class ContactLog {
  final String id;
  final String type; // 'call' | 'fitting' | 'message' | 'note'
  final String notes;
  final DateTime createdAt;
  final DateTime? followUpDate;

  ContactLog({
    required this.id,
    required this.type,
    required this.notes,
    required this.createdAt,
    this.followUpDate,
  });

  factory ContactLog.fromFirestore(String id, Map<String, dynamic> data) {
    DateTime ts = DateTime.now();
    final raw = data['createdAt'];
    if (raw is Timestamp) ts = raw.toDate();

    DateTime? followUp;
    final rawFollowUp = data['followUpDate'];
    if (rawFollowUp is Timestamp) followUp = rawFollowUp.toDate();

    return ContactLog(
      id: id,
      type: data['type']?.toString() ?? 'note',
      notes: data['notes']?.toString() ?? '',
      createdAt: ts,
      followUpDate: followUp,
    );
  }

  Map<String, dynamic> toFirestore() => {
    'type': type,
    'notes': notes,
    'createdAt': createdAt,
    if (followUpDate != null) 'followUpDate': followUpDate,
  };
}
