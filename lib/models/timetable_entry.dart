class TimetableEntry {
  final int? id;
  final int dayOfWeek; // 1 = Monday, 6 = Saturday
  final int subjectId;
  final int lectureOrder;

  TimetableEntry({
    this.id,
    required this.dayOfWeek,
    required this.subjectId,
    required this.lectureOrder,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'day_of_week': dayOfWeek,
      'subject_id': subjectId,
      'lecture_order': lectureOrder,
    };
  }

  factory TimetableEntry.fromMap(Map<String, dynamic> map) {
    return TimetableEntry(
      id: map['id'],
      dayOfWeek: map['day_of_week'],
      subjectId: map['subject_id'],
      lectureOrder: map['lecture_order'],
    );
  }
}
