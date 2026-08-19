import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/github_release.dart';
import '../services/github_release_service.dart';

/// Lists the prosthesis logger binary versions (GitHub releases) in a vertical,
/// lazily-paginated list. The release currently in use is highlighted; tapping
/// another release changes the selection (visual only for now) and shows a
/// confirmation toast.
class ReleasesScreen extends StatefulWidget {
  const ReleasesScreen({super.key});

  @override
  State<ReleasesScreen> createState() => _ReleasesScreenState();
}

class _ReleasesScreenState extends State<ReleasesScreen> {
  final GithubReleaseService _service = GithubReleaseService();
  final ScrollController _scrollController = ScrollController();
  final DateFormat _dateFormat = DateFormat('MMM d, yyyy');

  final List<GithubRelease> _releases = [];

  /// Id of the release currently "in use". Defaults to the latest release once
  /// the first page loads.
  int? _selectedReleaseId;

  int _nextPage = 1;
  bool _isLoadingFirstPage = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _error;

  /// Set when a "load more" page fails, to stop the scroll listener from
  /// retrying on every frame. Cleared when the user taps the retry footer.
  bool _loadMoreError = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadFirstPage();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _service.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    // Pre-fetch the next page a little before the very bottom is reached.
    if (position.pixels >= position.maxScrollExtent - 300) {
      _loadMore();
    }
  }

  Future<void> _loadFirstPage() async {
    setState(() {
      _isLoadingFirstPage = true;
      _error = null;
      _loadMoreError = false;
      _releases.clear();
      _nextPage = 1;
      _hasMore = true;
    });

    try {
      final page = await _service.fetchReleases(page: _nextPage);
      if (!mounted) return;
      setState(() {
        _releases.addAll(page);
        _nextPage += 1;
        _hasMore = page.length >= GithubReleaseService.perPage;
        // Keep the user's chosen release if it still exists after a refresh;
        // otherwise default the "in use" release to the latest (first) one.
        final selectionStillPresent =
            _selectedReleaseId != null &&
            _releases.any((r) => r.id == _selectedReleaseId);
        if (!selectionStillPresent) {
          _selectedReleaseId = _releases.isNotEmpty ? _releases.first.id : null;
        }
        _isLoadingFirstPage = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoadingFirstPage = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore ||
        !_hasMore ||
        _isLoadingFirstPage ||
        _error != null ||
        _loadMoreError) {
      return;
    }

    setState(() => _isLoadingMore = true);

    try {
      final page = await _service.fetchReleases(page: _nextPage);
      if (!mounted) return;
      setState(() {
        _releases.addAll(page);
        _nextPage += 1;
        _hasMore = page.length >= GithubReleaseService.perPage;
        _isLoadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      // Stop auto-retrying on every scroll frame; the footer offers a manual
      // retry instead.
      setState(() {
        _isLoadingMore = false;
        _loadMoreError = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load more releases: $e'),
          backgroundColor: const Color(0xFFEF4444),
        ),
      );
    }
  }

  void _retryLoadMore() {
    setState(() => _loadMoreError = false);
    _loadMore();
  }

  void _selectRelease(GithubRelease release) {
    if (release.id == _selectedReleaseId) return;

    setState(() => _selectedReleaseId = release.id);

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Active version changed to ${release.displayName}'),
          duration: const Duration(seconds: 2),
          backgroundColor: const Color(0xFF2563EB),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text(
          'Versions',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFF1E293B)),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoadingFirstPage) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF2563EB)),
      );
    }

    if (_error != null) {
      return _buildError();
    }

    if (_releases.isEmpty) {
      return const Center(
        child: Text(
          'No releases found.',
          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 15),
        ),
      );
    }

    return RefreshIndicator(
      color: const Color(0xFF2563EB),
      backgroundColor: const Color(0xFF1E293B),
      onRefresh: _loadFirstPage,
      child: ListView.separated(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        // +1 for the trailing loader / end-of-list footer.
        itemCount: _releases.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (index >= _releases.length) {
            return _buildFooter();
          }
          return _buildReleaseTile(_releases[index]);
        },
      ),
    );
  }

  Widget _buildReleaseTile(GithubRelease release) {
    final isSelected = release.id == _selectedReleaseId;
    const accent = Color(0xFF2563EB);

    return GestureDetector(
      onTap: () => _selectRelease(release),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: isSelected ? accent.withValues(alpha: 0.12) : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? accent : const Color(0xFF334155),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: isSelected ? accent : const Color(0xFF475569),
              size: 24,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    release.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    release.publishedAt != null
                        ? _dateFormat.format(release.publishedAt!)
                        : 'Unknown date',
                    style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'In use',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    if (_isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: Color(0xFF2563EB),
            ),
          ),
        ),
      );
    }

    if (_loadMoreError) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: TextButton.icon(
            onPressed: _retryLoadMore,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text("Couldn't load more — tap to retry"),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF94A3B8),
            ),
          ),
        ),
      );
    }

    if (!_hasMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: Text(
            'End of list',
            style: TextStyle(color: Color(0xFF475569), fontSize: 13),
          ),
        ),
      );
    }

    return const SizedBox(height: 8);
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              color: Color(0xFF475569),
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              'Could not load releases',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? 'Unknown error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _loadFirstPage,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text(
                'Retry',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF334155),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
