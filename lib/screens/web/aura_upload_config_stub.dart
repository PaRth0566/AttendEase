import 'package:flutter/material.dart';
import '../../models/subject.dart';

class AuraUploadConfig extends StatefulWidget {
  final Function(
    List<Subject> subjects,
    Map<int, Map<String, int>> stats,
    Map<String, String> meta,
    double overallTarget,
    double subjectTarget,
  )? onConfigured;

  const AuraUploadConfig({super.key, this.onConfigured});

  @override
  State<AuraUploadConfig> createState() => _AuraUploadConfigState();
}

class _AuraUploadConfigState extends State<AuraUploadConfig> {
  @override
  Widget build(BuildContext context) {
    return const Center(child: Text("Web only feature."));
  }
}
