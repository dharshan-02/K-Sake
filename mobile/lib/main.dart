import 'package:flutter/material.dart';
import 'src/app.dart';
import 'src/data/local_vault.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final vault = LocalVault();
  runApp(KeepsakeApp(vault: vault));
}
