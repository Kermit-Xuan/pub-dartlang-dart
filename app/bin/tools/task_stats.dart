// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Creates a report about analysis and dartdoc task failures.
/// Example use:
///   dart bin/tools/task_stats.dart --output report.json

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appengine/appengine.dart';
import 'package:args/args.dart';
import 'package:gcloud/db.dart';
import 'package:pool/pool.dart';

import 'package:pub_dartlang_org/frontend/models.dart';
import 'package:pub_dartlang_org/frontend/service_utils.dart';
import 'package:pub_dartlang_org/shared/analyzer_client.dart';
import 'package:pub_dartlang_org/shared/analyzer_memcache.dart';
import 'package:pub_dartlang_org/shared/dartdoc_client.dart';
import 'package:pub_dartlang_org/shared/dartdoc_memcache.dart';

Future main(List<String> args) async {
  final ArgParser parser = new ArgParser()
    ..addOption('max-age',
        defaultsTo: '365', help: 'The maximum age of the package in days.')
    ..addOption('output', help: 'The report output file (or stdout otherwise)');
  final ArgResults argv = parser.parse(args);
  final int maxAgeDays = int.parse(argv['max-age'] as String);

  final pool = new Pool(20);

  final Map report = {};

  await withProdServices(() async {
    registerAnalyzerMemcache(new AnalyzerMemcache(memcacheService));
    registerDartdocMemcache(new DartdocMemcache(memcacheService));
    registerAnalyzerClient(new AnalyzerClient());
    registerDartdocClient(new DartdocClient());

    final statFutures = <Future<_Stat>>[];
    final updatedAfter =
        new DateTime.now().subtract(new Duration(days: maxAgeDays));
    final query = dbService.query(Package)..filter('updated >=', updatedAfter);
    await for (Package p in query.run()) {
      statFutures
          .add(pool.withResource(() => _getStat(p.name, p.latestVersion)));
    }

    final stats = await Future.wait(statFutures);
    report['analyzer'] = _summarize(stats, (s) => s.analyzer);
    report['dartdoc'] = _summarize(stats, (s) => s.dartdoc);
  });

  final String json = new JsonEncoder.withIndent('  ').convert(report);
  if (argv['output'] != null) {
    final File outputFile = new File(argv['output'] as String);
    print('Writing report to ${outputFile.path}');
    await outputFile.parent.create(recursive: true);
    await outputFile.writeAsString(json + '\n');
  } else {
    print(json);
  }

  exit(0);
}

Future<String> _analyzerStatus(String package, String version) async {
  final extract = await analyzerClient
      .getAnalysisExtract(new AnalysisKey(package, version));
  if (extract == null || extract.analysisStatus == null) return 'awaiting';
  return extract.analysisStatus.toString().split('.').last;
}

Future<String> _dartdocStatus(String package, String version) async {
  final list = await dartdocClient.getEntries(package, [version]);
  final entry = list.single;
  if (entry == null) return 'awaiting';
  return entry.hasContent ? 'success' : 'failure';
}

Future<_Stat> _getStat(String package, String version) async {
  final List<String> statusList = await Future.wait([
    _analyzerStatus(package, version),
    _dartdocStatus(package, version),
  ]);
  return new _Stat(
    package: package,
    version: version,
    analyzer: statusList[0],
    dartdoc: statusList[1],
  );
}

class _Stat {
  final String package;
  final String version;
  final String analyzer;
  final String dartdoc;

  _Stat({this.package, this.version, this.analyzer, this.dartdoc});
}

Map<String, List<String>> _groupBy(
    List<_Stat> stats, String keyFn(_Stat stat)) {
  final result = <String, List<String>>{};
  for (_Stat stat in stats) {
    final String key = keyFn(stat);
    result.putIfAbsent(key, () => []).add(stat.package);
  }
  result.values.forEach((list) => list.sort());
  return result;
}

Map _summarize(List<_Stat> stats, String keyFn(_Stat stat)) {
  final values = _groupBy(stats, keyFn);
  final counts = <String, int>{};
  for (String key in values.keys) {
    counts[key] = values[key].length;
  }
  values.remove('success');
  return {
    'counts': counts,
    'values': values,
  };
}
