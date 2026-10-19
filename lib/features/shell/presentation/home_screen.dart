import 'package:flutter/material.dart';

import '../../learning_path/presentation/path_screen.dart';

/// The Home destination of the navigation shell.
///
/// Home is the learner's learning path: the authored sequence of step circles
/// with their locked / available / completed state and the completion/unlock
/// flow. The rendering lives in [PathScreen] (the learning-path feature);
/// this shell screen simply mounts it so the Home branch of the navigation
/// shell shows the path. (Requirements 3.2, 3.3, 3.4, 12.1, 12.2)
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) => const PathScreen();
}
