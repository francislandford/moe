// classroom_2_page.dart
import 'package:flutter/material.dart';
import '../../../../core/widgets/classroom_base.dart';

class Classroom2Page extends BaseClassroomPage {
  const Classroom2Page({
    super.key,
    super.schoolCode,
    super.schoolName,
    super.schoolLevel,
  }) : super(classroomNumber: 2);

  @override
  State<Classroom2Page> createState() => _Classroom2PageState();
}

class _Classroom2PageState extends BaseClassroomPageState<Classroom2Page> {}