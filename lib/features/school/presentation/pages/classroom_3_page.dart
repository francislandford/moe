// classroom_3_page.dart
import 'package:flutter/material.dart';
import '../../../../core/widgets/classroom_base.dart';


class Classroom3Page extends BaseClassroomPage {
  const Classroom3Page({
    super.key,
    super.schoolCode,
    super.schoolName,
    super.schoolLevel,
  }) : super(classroomNumber: 3);

  @override
  State<Classroom3Page> createState() => _Classroom3PageState();
}

class _Classroom3PageState extends BaseClassroomPageState<Classroom3Page> {}