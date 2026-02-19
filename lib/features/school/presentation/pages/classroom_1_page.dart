// classroom_1_page.dart
import 'package:flutter/material.dart';
import '../../../../core/widgets/classroom_base.dart';

class Classroom1Page extends BaseClassroomPage {
  const Classroom1Page({
    super.key,
    super.schoolCode,
    super.schoolName,
    super.schoolLevel,
  }) : super(classroomNumber: 1);

  @override
  State<Classroom1Page> createState() => _Classroom1PageState();
}

class _Classroom1PageState extends BaseClassroomPageState<Classroom1Page> {}