import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nigergram/core/design_system/colors.dart';
import 'package:nigergram/core/utils/app_auth.dart';
import 'package:nigergram/features/gist_hub/data/services/community_service.dart';
import 'package:nigergram/features/gist_hub/domain/entities/community_entity.dart';

class CommunityDetailView extends StatefulWidget {
  final String communityId;
  const CommunityDetailView({required this.communityId, super.key});

  @override
  State<CommunityDetailView> createState() => _CommunityDetailViewState();
}

class _CommunityDetailViewState extends State<CommunityDetailView> {
  final _service = CommunityService();
  final _postController = TextEditingController();
  String? _myRole;
  bool _isPosting = false;

  @override
  void initState() {
    super.initState();
    _loadRole();
  }

  Future<void> _loadRole() async {
    final role = await _service.getMemberRole(widget.communityId, AppAuth.uid);
    if (mounted) setState(() => _myRole = role);
  }

  Future<void> _post() async {
    if (_postController.text.trim().isEmpty) return;
    setState(() => _isPosting = true);
    try {
      await FirebaseFirestore.instance
          .collection('communities')
          .doc(widget.communityId)
          .collection('posts')
          .add({
        'userId': AppAuth.uid,
        'username': AppAuth.displayHandle,
        'text': _postController.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });
      _postController.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _isPosting = false);
    }
  }

  Future<void> _leave() async {
    try {
      await _service.leaveCommunity(widget.communityId);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMember = _myRole != null;
    final canPost = _myRole == 'owner' || _myRole == 'moderator';

    return Scaffold(
      backgroundColor: NGColors.background,
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('communities').doc(widget.communityId).snapshots(),
        builder: (context, communitySnap) {
          if (!communitySnap.hasData || !communitySnap.data!.exists) {
            return const Center(child: CircularProgressIndicator());
          }
          final community = CommunityEntity.fromMap(
            communitySnap.data!.data() as Map<String, dynamic>,
            communitySnap.data!.id,
          );

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                backgroundColor: NGColors.surface,
                pinned: true,
                title: Text(community.name, style: const TextStyle(color: Colors.white)),
                actions: [
                  if (isMember && _myRole != 'owner')
                    IconButton(
                      icon: const Icon(Icons.logout, color: Colors.redAccent),
                      tooltip: 'Leave community',
                      onPressed: _leave,
                    ),
                ],
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(community.description, style: TextStyle(color: NGColors.textMuted)),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(
                            community.type == CommunityType.channel ? Icons.campaign_outlined : Icons.groups_outlined,
                            size: 14,
                            color: NGColors.textMuted,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${community.memberCount} members • ${community.type == CommunityType.channel ? "Channel" : "Group"}',
                            style: TextStyle(color: NGColors.textMuted, fontSize: 12),
                          ),
                          if (_myRole != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: NGColors.accent.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _myRole!.toUpperCase(),
                                style: TextStyle(color: NGColors.accent, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (community.rules.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        const Text('Rules', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        ...community.rules.map((r) => Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text('• $r', style: TextStyle(color: NGColors.textMuted, fontSize: 13)),
                            )),
                      ],
                      const Divider(height: 32, color: NGColors.divider),
                      if (!isMember)
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () async {
                              await _service.joinCommunity(widget.communityId);
                              _loadRole();
                            },
                            style: ElevatedButton.styleFrom(backgroundColor: NGColors.accent),
                            child: const Text('Join Community'),
                          ),
                        )
                      else if (canPost || community.type == CommunityType.group)
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _postController,
                                enabled: canPost || community.type == CommunityType.group,
                                style: const TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  hintText: canPost || community.type == CommunityType.group
                                      ? 'Post something...'
                                      : 'Only moderators can post here',
                                  hintStyle: TextStyle(color: NGColors.textMuted),
                                  filled: true,
                                  fillColor: NGColors.surface,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                                ),
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.send, color: NGColors.accent),
                              onPressed: _isPosting ? null : _post,
                            ),
                          ],
                        ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('communities')
                    .doc(widget.communityId)
                    .collection('posts')
                    .orderBy('createdAt', descending: true)
                    .limit(50)
                    .snapshots(),
                builder: (context, postsSnap) {
                  if (!postsSnap.hasData) {
                    return const SliverToBoxAdapter(child: SizedBox.shrink());
                  }
                  final posts = postsSnap.data!.docs;
                  if (posts.isEmpty) {
                    return SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        child: Center(
                          child: Text('No posts yet', style: TextStyle(color: NGColors.textMuted)),
                        ),
                      ),
                    );
                  }
                  return SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final data = posts[index].data() as Map<String, dynamic>;
                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: NGColors.surface,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('@${data['username'] ?? 'user'}',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                              const SizedBox(height: 4),
                              Text(data['text'] ?? '', style: TextStyle(color: NGColors.textSecondary)),
                            ],
                          ),
                        );
                      },
                      childCount: posts.length,
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}
