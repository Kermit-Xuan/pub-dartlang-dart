// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;

const _generatedStaticAssetPaths = const <String>['static-assets'];

// Storage contains package data in a form of /package/version/...
// This path contains '-' and is an invalid package name, safe of conflicts.
const _storageSharedAssetPrefix = 'shared-assets';

/// Whether the generated file can be moved to the shared assets.
bool isSharedAsset(String relativePath) {
  for (String parent in _generatedStaticAssetPaths) {
    if (p.isWithin(parent, relativePath)) return true;
  }
  return false;
}

/// The storage path of a shared generated file.
String sharedAssetObjectName(String dartdocVersion, String relativePath) =>
    p.join(_storageSharedAssetPrefix, 'dartdoc', dartdocVersion, relativePath);

/// Entry prefix for uploads in progress.
String inProgressPrefix(String packageName, String packageVersion) =>
    '$packageName/$packageVersion/in-progress';

/// ObjectName of the DartdocEntry for uploads in progress.
String inProgressObjectName(
        String packageName, String packageVersion, String uuid) =>
    '${inProgressPrefix(packageName, packageVersion)}/$uuid.json';

/// Entry prefix for completed uploads.
String entryPrefix(String packageName, String packageVersion) =>
    '$packageName/$packageVersion/entry';

/// ObjectName of the DartdocEntry for completed uploads.
String entryObjectName(
        String packageName, String packageVersion, String uuid) =>
    '${entryPrefix(packageName, packageVersion)}/$uuid.json';

/// Content path prefix.
String contentPrefix(String packageName, String packageVersion, String uuid) =>
    '$packageName/$packageVersion/content/$uuid';

/// ObjectName of the generated content.
String contentObjectName(String packageName, String packageVersion, String uuid,
    String relativePath) {
  return p.join(contentPrefix(packageName, packageVersion, uuid), relativePath);
}
