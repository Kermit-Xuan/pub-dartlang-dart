// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library pub_dartlang_org.handlers_test;

import 'dart:async';

import 'package:gcloud/db.dart';
import 'package:test/test.dart';

import 'package:pub_dartlang_org/shared/analyzer_service.dart';
import 'package:pub_dartlang_org/shared/task_scheduler.dart'
    show TaskTargetStatus;

import 'package:pub_dartlang_org/analyzer/backend.dart';
import 'package:pub_dartlang_org/analyzer/models.dart';

import '../shared/handlers_test_utils.dart';
import '../shared/utils.dart';

import 'handlers_test_utils.dart';

void main() {
  group('handlers', () {
    group('not found', () {
      scopedTest('/xxx', () async {
        await expectNotFoundResponse(await issueGet('/xxx'));
      });
      scopedTest('/packages', () async {
        await expectNotFoundResponse(await issueGet('/packages'));
      });

      scopedTest('/packages/unknown', () async {
        registerAnalysisBackend(new MockAnalysisBackend());
        await expectNotFoundResponse(await issueGet('/packages/unknown'));
      });

      scopedTest('/packages/pkg_foo/unknown', () async {
        registerAnalysisBackend(new MockAnalysisBackend());
        await expectNotFoundResponse(
            await issueGet('/packages/pkg_foo/unknown'));
      });

      scopedTest('/packages/pkg_foo/1.2.3/unknown', () async {
        registerAnalysisBackend(new MockAnalysisBackend());
        await expectNotFoundResponse(
            await issueGet('/packages/pkg_foo/1.2.3/unknown'));
      });

      scopedTest('/packages/pkg_foo/1.2.3/1', () async {
        registerAnalysisBackend(new MockAnalysisBackend());
        await expectNotFoundResponse(
            await issueGet('/packages/pkg_foo/1.2.3/1'));
      });
    });

    group('get analysis', () {
      scopedTest('/packages/pkg_foo', () async {
        registerAnalysisBackend(new MockAnalysisBackend());
        await expectJsonResponse(await issueGet('/packages/pkg_foo'), body: {
          'packageName': 'pkg_foo',
          'packageVersion': '1.2.3',
          'analysis': 242345,
          'timestamp': '2017-06-26T12:48:00.000',
          'runtimeVersion': '2018.3.8',
          'panaVersion': '0.2.0',
          'flutterVersion': '0.0.11',
          'analysisStatus': 'success',
          'analysisContent': {'content': 'from-pana'},
          'maintenanceScore': 0.86,
        });
      });

      scopedTest('/packages/pkg_foo/1.2.3', () async {
        registerAnalysisBackend(new MockAnalysisBackend());
        await expectJsonResponse(await issueGet('/packages/pkg_foo/1.2.3'),
            body: {
              'packageName': 'pkg_foo',
              'packageVersion': '1.2.3',
              'analysis': 242345,
              'timestamp': '2017-06-26T12:48:00.000',
              'runtimeVersion': '2018.3.8',
              'panaVersion': '0.2.0',
              'flutterVersion': '0.0.11',
              'analysisStatus': 'success',
              'analysisContent': {'content': 'from-pana'},
              'maintenanceScore': 0.86,
            });
      });

      scopedTest('/packages/pkg_foo/1.2.3/242345', () async {
        registerAnalysisBackend(new MockAnalysisBackend());
        await expectJsonResponse(
            await issueGet('/packages/pkg_foo/1.2.3/242345'),
            body: {
              'packageName': 'pkg_foo',
              'packageVersion': '1.2.3',
              'analysis': 242345,
              'timestamp': '2017-06-26T12:48:00.000',
              'runtimeVersion': '2018.3.8',
              'panaVersion': '0.2.0',
              'flutterVersion': '0.0.11',
              'analysisStatus': 'success',
              'analysisContent': {'content': 'from-pana'},
              'maintenanceScore': 0.86,
            });
      });
    });
  });
}

class MockAnalysisBackend implements AnalysisBackend {
  final _map = <String, AnalysisData>{};

  MockAnalysisBackend() {
    _storeAnalysisSync(testAnalysis);
  }

  @override
  DatastoreDB get db => throw new Exception('No DB access.');

  @override
  Future<AnalysisData> getAnalysis(String package,
      {String version, int analysis, String panaVersion}) async {
    return _map.values.firstWhere(
        (AnalysisData a) =>
            (package == a.packageName) &&
            (version == null || a.packageVersion == version) &&
            (analysis == null || a.analysis == analysis),
        orElse: () => null);
  }

  BackendAnalysisStatus _storeAnalysisSync(Analysis analysis) {
    final String key = [
      analysis.packageName,
      analysis.packageVersion,
      analysis.analysis,
    ].join('/');
    _map[key] = new AnalysisData(
        packageName: analysis.packageName,
        packageVersion: analysis.packageVersion,
        analysis: analysis.analysis,
        timestamp: analysis.timestamp,
        runtimeVersion: analysis.runtimeVersion,
        panaVersion: analysis.panaVersion,
        flutterVersion: analysis.flutterVersion,
        analysisStatus: analysis.analysisStatus,
        maintenanceScore: analysis.maintenanceScore,
        analysisContent: analysis.analysisJson);
    return new BackendAnalysisStatus(false, false, false);
  }

  @override
  Future<BackendAnalysisStatus> storeAnalysis(Analysis analysis) async {
    return _storeAnalysisSync(analysis);
  }

  @override
  Future<TaskTargetStatus> checkTargetStatus(
      String packageName, String packageVersion, DateTime updated) {
    throw new UnimplementedError();
  }

  @override
  Future deleteObsoleteAnalysis(String package, String version) {
    throw new UnimplementedError();
  }

  @override
  Future<PackageStatus> getPackageStatus(String package, String version) {
    throw new UnimplementedError();
  }
}

final Analysis testAnalysis = new Analysis()
  ..packageName = 'pkg_foo'
  ..packageVersion = '1.2.3'
  ..id = 242345
  ..analysisStatus = AnalysisStatus.success
  ..runtimeVersion = '2018.3.8'
  ..panaVersion = '0.2.0'
  ..flutterVersion = '0.0.11'
  ..timestamp = new DateTime(2017, 06, 26, 12, 48, 00)
  ..maintenanceScore = 0.86
  ..analysisJson = <String, dynamic>{'content': 'from-pana'};
