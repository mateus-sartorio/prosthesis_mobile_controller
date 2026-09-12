/// Model representing a single GitHub release for the logger binaries repo.
///
/// Mirrors the subset of the GitHub Releases API response that the app needs.
/// See: https://docs.github.com/en/rest/releases/releases#list-releases
class GithubRelease {
  final int id;
  final String tagName;
  final String? name;
  final DateTime? publishedAt;
  final bool isPrerelease;
  final bool isDraft;

  const GithubRelease({
    required this.id,
    required this.tagName,
    this.name,
    this.publishedAt,
    this.isPrerelease = false,
    this.isDraft = false,
  });

  /// Human-friendly title: the release name when present, otherwise the tag.
  String get displayName {
    final trimmed = name?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed;
    }
    return tagName;
  }

  factory GithubRelease.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    // `published_at` is null for drafts; fall back to `created_at`.
    final rawDate = json['published_at'] ?? json['created_at'];

    return GithubRelease(
      id: id is int ? id : int.tryParse('$id') ?? 0,
      tagName: (json['tag_name'] as String?) ?? '',
      name: json['name'] as String?,
      publishedAt: rawDate is String
          ? DateTime.tryParse(rawDate)?.toLocal()
          : null,
      isPrerelease: json['prerelease'] == true,
      isDraft: json['draft'] == true,
    );
  }
}
