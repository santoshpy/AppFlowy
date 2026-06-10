import 'dart:convert';

import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/features/share_tab/data/models/models.dart';
import 'package:appflowy/features/share_tab/data/repositories/rust_share_with_user_repository_impl.dart';
import 'package:appflowy/features/share_tab/data/repositories/share_with_user_repository.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-error/code.pbenum.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:http/http.dart' as http;

/// A [ShareWithUserRepository] backed by the self-hosted team RBAC object-grant
/// API (`/api/object-grant/...`) instead of AppFlowy's built-in "guest editor"
/// share, which the OSS self-hosted cloud does not support. Per-page sharing maps
/// to object grants: a grant == a share, and the access level == AFAccessLevel
/// (read-only 10 / comment 20 / edit 30 / full 50). Permissions are enforced
/// server-side (the object.manage capability), so the UI never gates on the
/// client side.
class ObjectGrantShareRepository implements ShareWithUserRepository {
  ObjectGrantShareRepository({required this.workspaceId});

  final String workspaceId;
  final RustShareWithUserRepositoryImpl _rust =
      RustShareWithUserRepositoryImpl();
  final http.Client _client = http.Client();

  // --- object-grant operations (HTTP) ---

  @override
  Future<FlowyResult<SharedUsers, FlowyError>> getSharedUsersInPage({
    required String pageId,
  }) async {
    final result = await _request(
      method: 'GET',
      path: '/api/object-grant/workspace/$workspaceId/$pageId',
    );
    return result.fold(
      (data) => FlowyResult.success(_grantsToUsers(data)),
      (error) => FlowyResult.failure(error),
    );
  }

  @override
  Future<FlowyResult<void, FlowyError>> sharePageWithUser({
    required String pageId,
    required ShareAccessLevel accessLevel,
    required List<String> emails,
  }) async {
    for (final email in emails.map((e) => e.trim()).where((e) => e.isNotEmpty)) {
      final result = await _request(
        method: 'PUT',
        path: '/api/object-grant/workspace/$workspaceId',
        body: {
          'object_type': 'page',
          'object_id': pageId,
          'email': email,
          'access_level': _toAccessLevelValue(accessLevel),
        },
      );
      final failure = result.fold((_) => null, (error) => error);
      if (failure != null) {
        return FlowyResult.failure(failure);
      }
    }
    return FlowyResult.success(null);
  }

  @override
  Future<FlowyResult<void, FlowyError>> removeSharedUserFromPage({
    required String pageId,
    required List<String> emails,
  }) async {
    // The delete endpoint is keyed by uid, so resolve email -> uid from the
    // current grants first.
    final listed = await _request(
      method: 'GET',
      path: '/api/object-grant/workspace/$workspaceId/$pageId',
    );
    final grants = listed.fold(
      (data) => (data?['grants'] as List?) ?? const [],
      (_) => const [],
    );
    final emailToUid = <String, int>{
      for (final g in grants)
        (g['email'] as String? ?? ''): (g['uid'] as num?)?.toInt() ?? -1,
    };
    for (final email in emails) {
      final uid = emailToUid[email];
      if (uid == null || uid < 0) {
        continue;
      }
      final result = await _request(
        method: 'DELETE',
        path: '/api/object-grant/workspace/$workspaceId/$pageId/user/$uid',
      );
      final failure = result.fold((_) => null, (error) => error);
      if (failure != null) {
        return FlowyResult.failure(failure);
      }
    }
    return FlowyResult.success(null);
  }

  @override
  Future<FlowyResult<void, FlowyError>> changeRole({
    required String workspaceId,
    required String email,
    required ShareRole role,
  }) async {
    // Object grants model access levels, not member/guest roles.
    return FlowyResult.failure(
      FlowyError()
        ..msg = 'Changing roles is not supported for object-grant sharing'
        ..code = ErrorCode.Internal,
    );
  }

  @override
  Future<FlowyResult<SharedUsers, FlowyError>> getAvailableSharedUsers({
    required String pageId,
  }) async =>
      FlowyResult.success(const <SharedUser>[]);

  // --- delegated / trivial ---

  @override
  Future<FlowyResult<UserProfilePB, FlowyError>> getCurrentUserProfile() =>
      _rust.getCurrentUserProfile();

  @override
  Future<FlowyResult<SharedSectionType, FlowyError>> getCurrentPageSectionType({
    required String pageId,
  }) async =>
      FlowyResult.success(SharedSectionType.private);

  @override
  Future<bool> getUpgradeToProButtonClicked({
    required String workspaceId,
  }) async =>
      true; // no pro upsell in the object-grant model

  @override
  Future<void> setUpgradeToProButtonClicked({
    required String workspaceId,
  }) async {}

  // --- helpers ---

  SharedUsers _grantsToUsers(Map<String, dynamic>? data) {
    final grants = (data?['grants'] as List?) ?? const [];
    return grants.map((g) {
      final email = g['email'] as String? ?? '';
      final name = (g['name'] as String?);
      return SharedUser(
        email: email,
        name: name != null && name.isNotEmpty ? name : email,
        role: ShareRole.member,
        accessLevel: _fromAccessLevelValue((g['access_level'] as num?)?.toInt()),
      );
    }).toList();
  }

  int _toAccessLevelValue(ShareAccessLevel level) {
    switch (level) {
      case ShareAccessLevel.readOnly:
        return 10;
      case ShareAccessLevel.readAndComment:
        return 20;
      case ShareAccessLevel.readAndWrite:
        return 30;
      case ShareAccessLevel.fullAccess:
        return 50;
    }
  }

  ShareAccessLevel _fromAccessLevelValue(int? value) {
    switch (value) {
      case 20:
        return ShareAccessLevel.readAndComment;
      case 30:
        return ShareAccessLevel.readAndWrite;
      case 50:
        return ShareAccessLevel.fullAccess;
      case 10:
      default:
        return ShareAccessLevel.readOnly;
    }
  }

  /// Makes an authed request and unwraps the AppFlowy `{code, message, data}`
  /// envelope. Returns the `data` map on success (code 0), else a FlowyError.
  Future<FlowyResult<Map<String, dynamic>?, FlowyError>> _request({
    required String method,
    required String path,
    Map<String, dynamic>? body,
  }) async {
    try {
      final baseUrl = await getAppFlowyCloudUrl();
      final profileResult = await getCurrentUserProfile();
      final token = profileResult.fold(_accessToken, (_) => null);
      if (token == null || token.isEmpty) {
        return FlowyResult.failure(
          FlowyError()
            ..msg = 'Not authenticated'
            ..code = ErrorCode.UserUnauthorized,
        );
      }
      final uri = Uri.parse('$baseUrl$path');
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };
      final http.Response resp;
      switch (method) {
        case 'PUT':
          resp = await _client.put(uri, headers: headers, body: jsonEncode(body));
          break;
        case 'DELETE':
          resp = await _client.delete(uri, headers: headers);
          break;
        case 'GET':
        default:
          resp = await _client.get(uri, headers: headers);
      }
      final decoded = resp.body.isNotEmpty
          ? jsonDecode(resp.body) as Map<String, dynamic>
          : <String, dynamic>{};
      final code = (decoded['code'] as num?)?.toInt() ?? -1;
      if (code == 0) {
        return FlowyResult.success(decoded['data'] as Map<String, dynamic>?);
      }
      return FlowyResult.failure(
        FlowyError()
          ..msg = (decoded['message'] as String?) ??
              'Request failed (HTTP ${resp.statusCode})'
          ..code = ErrorCode.Internal,
      );
    } catch (e) {
      Log.error('[ObjectGrantShare] $method $path failed: $e');
      return FlowyResult.failure(
        FlowyError()
          ..msg = '$e'
          ..code = ErrorCode.Internal,
      );
    }
  }

  String? _accessToken(UserProfilePB profile) {
    try {
      final decoded = jsonDecode(profile.token);
      return decoded is Map ? decoded['access_token'] as String? : null;
    } catch (_) {
      return null;
    }
  }
}
