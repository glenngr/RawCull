import 'package:flutter/material.dart';
import 'ffi/rawcull_bindings.dart';

void main() {
  runApp(const RawCullDesktopApp());
}

class RawCullDesktopApp extends StatelessWidget {
  const RawCullDesktopApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RawCull Rewrite',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const _CatalogScreen(),
    );
  }
}

class _CatalogScreen extends StatefulWidget {
  const _CatalogScreen();

  @override
  State<_CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<_CatalogScreen> {
  final List<_CatalogRow> _rows = <_CatalogRow>[];
  String _ffiStatus = 'FFI ikke initialisert';

  @override
  void initState() {
    super.initState();
    _initFfi();
    // M1 placeholder while the dynamic library integration is wired in CI/dev env.
    _rows.addAll(const <_CatalogRow>[
      _CatalogRow(path: 'Eksempel: sample_001.ARW', rating: 0),
      _CatalogRow(path: 'Eksempel: sample_002.NEF', rating: 0),
    ]);
  }

  void _initFfi() {
    try {
      final bindings = RawCullBindings.open();
      final version = bindings.apiVersion();
      setState(() => _ffiStatus = 'FFI lastet OK (api v$version)');
    } catch (error) {
      setState(() => _ffiStatus = 'FFI ikke lastet: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('RawCull M1 – Scan/Rating skeleton')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(_ffiStatus),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              itemCount: _rows.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final row = _rows[index];
                return ListTile(
                  dense: true,
                  title: Text(row.path),
                  subtitle: Text('Rating: ${row.rating}'),
                  trailing: DropdownButton<int>(
                    value: row.rating,
                    items: List.generate(
                      6,
                      (r) => DropdownMenuItem<int>(value: r, child: Text('$r')),
                    ),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _rows[index] = row.copyWith(rating: value));
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CatalogRow {
  const _CatalogRow({required this.path, required this.rating});

  final String path;
  final int rating;

  _CatalogRow copyWith({String? path, int? rating}) {
    return _CatalogRow(path: path ?? this.path, rating: rating ?? this.rating);
  }
}
