// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:gcloud/service_scope.dart' as ss;
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:pool/pool.dart';

import '../dartdoc/dartdoc_runner.dart' show statusFilePath;
import '../dartdoc/models.dart' show DartdocEntry;
import '../job/backend.dart';

import 'configuration.dart';
import 'dartdoc_memcache.dart';
import 'utils.dart' show getUrlWithRetry;

export '../dartdoc/models.dart' show DartdocEntry;

final Logger _logger = new Logger('dartdoc.client');

/// Sets the dartdoc client.
void registerDartdocClient(DartdocClient client) =>
    ss.register(#_dartdocClient, client);

/// The active dartdoc client.
DartdocClient get dartdocClient => ss.lookup(#_dartdocClient) as DartdocClient;

/// Client methods that access the dartdoc service.
class DartdocClient {
  final http.Client _client = new http.Client();
  String get _dartdocServiceHttpHostPort =>
      activeConfiguration.dartdocServicePrefix;

  Future<List<DartdocEntry>> getEntries(
      String package, List<String> versions) async {
    final resultFutures = <Future<DartdocEntry>>[];
    final pool = new Pool(4); // concurrent requests
    for (String version in versions) {
      final future = pool.withResource(() => getEntry(package, version));
      resultFutures.add(future);
    }
    return await Future.wait(resultFutures);
  }

  Future triggerDartdoc(
      String package, String version, Set<String> dependentPackages) async {
    if (jobBackend == null) {
      _logger.warning('Job backend is not initialized!');
      return;
    }
    await jobBackend.trigger(JobService.dartdoc, package, version);
    for (final String package in dependentPackages) {
      await jobBackend.trigger(JobService.dartdoc, package);
    }
  }

  Future close() async {
    _client.close();
  }

  Future<List<int>> getContentBytes(
      String package, String version, String relativePath,
      {Duration timeout}) async {
    final url = p.join(_dartdocServiceHttpHostPort, 'documentation', package,
        version, relativePath);
    try {
      final rs = await getUrlWithRetry(_client, url, timeout: timeout);
      if (rs.statusCode != 200) {
        return null;
      }
      return rs.bodyBytes;
    } catch (e) {
      _logger
          .info('Error getting content for: $package $version $relativePath');
    }
    return null;
  }

  Future<DartdocEntry> getEntry(String package, String version) async {
    final cachedEntry = await dartdocMemcache?.getEntry(package, version);
    if (cachedEntry != null) {
      return cachedEntry;
    }
    final content = await getContentBytes(package, version, statusFilePath);
    if (content == null) {
      return null;
    }
    final entry = new DartdocEntry.fromBytes(content);
    await dartdocMemcache?.setEntry(entry);
    return entry;
  }
}
