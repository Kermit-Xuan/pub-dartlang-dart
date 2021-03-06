// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:appengine/appengine.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:stack_trace/stack_trace.dart';

import '../frontend/service_utils.dart';
import '../frontend/templates.dart';

import 'handlers.dart';
import 'markdown.dart';
import 'utils.dart' show fileAnIssueContent;

Future runHandler(Logger logger, shelf.Handler handler,
    {bool sanitize: false}) {
  registerTemplateService(new TemplateService(templateDirectory: templatePath));

  handler = _userAuthParsingWrapper(handler);
  if (sanitize) {
    handler = _sanitizeRequestWrapper(handler);
  }
  handler = _redirectToHttpsWrapper(handler);
  handler = _logRequestWrapper(logger, handler);
  return runAppEngine((HttpRequest request) => _handleRequest(request, handler),
      shared: true);
}

Future _handleRequest(HttpRequest request, shelf.Handler handler) =>
    shelf_io.handleRequest(request, handler);

shelf.Handler _logRequestWrapper(Logger logger, shelf.Handler handler) {
  return (shelf.Request request) async {
    logger.info('Handling request: ${request.requestedUri}');
    try {
      return await handler(request);
    } catch (error, st) {
      logger.severe('Request handler failed', error, new Trace.from(st));

      final title = 'Pub is not feeling well';
      Map<String, String> debugHeaders;
      if (context.traceId != null) {
        debugHeaders = {'package-site-request-id': context.traceId};
      }
      final markdownText = '''# $title

**Fatal package site error.**

$fileAnIssueContent

Add these details to help us fix the issue:
````
Requested URL: ${request.requestedUri}
Request ID: ${context.traceId}
````
      ''';

      final content = templateService.renderLayoutPage(
          PageType.package, markdownToHtml(markdownText, null),
          title: title);
      return htmlResponse(content, status: 500, headers: debugHeaders);
    } finally {
      logger.info('Request handler done.');
    }
  };
}

shelf.Handler _sanitizeRequestWrapper(shelf.Handler handler) {
  return (shelf.Request request) async {
    return await handler(_sanitizeRequestedUri(request));
  };
}

shelf.Handler _userAuthParsingWrapper(shelf.Handler handler) {
  return (shelf.Request request) async {
    await registerLoggedInUserIfPossible(request);
    return await handler(request);
  };
}

shelf.Handler _redirectToHttpsWrapper(shelf.Handler handler) {
  return (shelf.Request request) async {
    if (context.isProductionEnvironment &&
        request.requestedUri.scheme != 'https') {
      final secureUri = request.requestedUri.replace(scheme: 'https');
      return new shelf.Response.seeOther(secureUri);
    } else {
      return await handler(request);
    }
  };
}

shelf.Request _sanitizeRequestedUri(shelf.Request request) {
  final uri = request.requestedUri;
  final resource = uri.path;
  final normalizedResource = path.normalize(resource);

  if (resource == normalizedResource) {
    return request;
  } else {
    // With the new flex VMs we can get requests from the load balancer which
    // can contain [Uri]s with e.g. double slashes
    //
    //    -> e.g. https://pub.dartlang.org//api/packages/foo
    //
    // Setting PUB_HOSTED_URL to a URL with a slash at the end can cause this.
    // (The pub client will not remove it and instead directly try to request
    //  "GET //api/..." :-/ )
    final changedUri = uri.replace(path: normalizedResource);
    return new shelf.Request(
      request.method,
      changedUri,
      protocolVersion: request.protocolVersion,
      headers: request.headers,
      body: request.read(),
      encoding: request.encoding,
      context: request.context,
    );
  }
}
