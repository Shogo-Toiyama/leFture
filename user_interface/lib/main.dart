import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app/app.dart';

const supabaseUrl = 'https://lvbpuywjxmmeecftinkb.supabase.co';
const supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imx2YnB1eXdqeG1tZWVjZnRpbmtiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjcwNTk1ODIsImV4cCI6MjA4MjYzNTU4Mn0.XmlBMJsXNy9U11VPs0YrTubVxG3LTP21Gh-86gn7KdI';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );

  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
}