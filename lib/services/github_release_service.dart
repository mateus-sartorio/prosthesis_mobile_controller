import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/github_release.dart';

/// Fetches releases (binary versions) for the prosthesis logger from GitHub.
///
/// Configuration is hardcoded for now, mirroring the standalone Python updater
/// script. Releases are returned by the GitHub API newest-first and are fetched
/// one page at a time so the UI can lazily load more as the user scrolls.
class GithubReleaseService {
  // TODO: move these out of source before shipping (env / secure storage).
  static const String _repo = 'mateus-sartorio/prosthesis-logger';
  static const String _apiBase = 'https://api.github.com';
  static const String _token =
      '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';

  /// Number of releases requested per page.
  static const int perPage = 30;

  final http.Client _client;

  GithubReleaseService({http.Client? client})
    : _client = client ?? http.Client();

  Map<String, String> get _headers => {
    'User-Agent': 'prosthesis-mobile-controller',
    'Accept': 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
    if (_token.isNotEmpty) 'Authorization': 'Bearer $_token',
  };

  /// Fetch a single page of releases (1-based). An empty list means there are
  /// no more pages to load.
  Future<List<GithubRelease>> fetchReleases({int page = 1}) async {
    final uri = Uri.parse(
      '$_apiBase/repos/$_repo/releases?per_page=$perPage&page=$page',
    );

    // api.github.com rotates across multiple IPs (GitHub's own network and
    // Azure-fronted ones) with a short DNS TTL. On some networks a subset of
    // those IPs is unreachable, so a single attempt may hang until timeout
    // while a retry often lands on a reachable address. Retry transient
    // connection failures with a short backoff; never retry a real HTTP
    // response (a status code is a definitive answer).
    const maxAttempts = 3;
    http.Response? response;
    Object? lastError;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        response = await _client
            .get(uri, headers: _headers)
            .timeout(const Duration(seconds: 12));
        break;
      } on TimeoutException catch (e) {
        lastError = e;
        debugPrint('GitHub releases timed out (attempt $attempt/$maxAttempts)');
      } on SocketException catch (e) {
        lastError = e;
        debugPrint(
          'GitHub releases network error (attempt $attempt/$maxAttempts): $e',
        );
      } on http.ClientException catch (e) {
        lastError = e;
        debugPrint(
          'GitHub releases client error (attempt $attempt/$maxAttempts): $e',
        );
      }

      if (attempt < maxAttempts) {
        await Future.delayed(Duration(seconds: attempt));
      }
    }

    if (response == null) {
      if (lastError is TimeoutException) {
        throw const GithubReleaseException(
          'Timed out reaching GitHub after several attempts. '
          'Check the connection and try again.',
        );
      }
      if (lastError is SocketException) {
        throw GithubReleaseException(
          'Could not reach GitHub '
          '(${lastError.osError?.message ?? lastError.message}). '
          'Try again or switch networks.',
        );
      }
      throw GithubReleaseException('Could not reach GitHub: $lastError');
    }

    if (response.statusCode == 401) {
      throw const GithubReleaseException(
        'GitHub authentication failed — check the access token.',
        statusCode: 401,
      );
    }
    if (response.statusCode == 403 || response.statusCode == 429) {
      throw GithubReleaseException(
        'Rate limited by GitHub. Please try again later.',
        statusCode: response.statusCode,
      );
    }
    if (response.statusCode != 200) {
      throw GithubReleaseException(
        'GitHub returned ${response.statusCode} while fetching releases.',
        statusCode: response.statusCode,
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw const GithubReleaseException(
        'Unexpected response shape from GitHub releases endpoint.',
      );
    }

    return decoded
        .whereType<Map<String, dynamic>>()
        .map(GithubRelease.fromJson)
        .toList();
  }

  void dispose() => _client.close();
}

/// Error raised when releases cannot be retrieved from GitHub.
class GithubReleaseException implements Exception {
  final String message;
  final int? statusCode;

  const GithubReleaseException(this.message, {this.statusCode});

  @override
  String toString() => message;
}
