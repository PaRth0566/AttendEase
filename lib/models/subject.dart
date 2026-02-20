class Subject {
  final int? id;
  final String name;
  final double requiredPercent;
  final int semester; // ✅ NEW: Links the subject to a specific semester

  Subject({
    this.id,
    required this.name,
    required this.requiredPercent,
    required this.semester,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'required_percent': requiredPercent,
      'semester': semester,
    };
  }

  factory Subject.fromMap(Map<String, dynamic> map) {
    return Subject(
      id: map['id'],
      name: map['name'],
      requiredPercent: map['required_percent'],
      semester: map['semester'] ?? 1,
    );
  }
}
