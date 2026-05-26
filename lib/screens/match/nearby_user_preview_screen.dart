// Kept for backwards compatibility.
// NearbyUserPreviewScreen is now an alias for ProfilePreviewScreen.
export 'package:love_vibe_pro/screens/match/profile_preview_screen.dart';

import 'package:love_vibe_pro/screens/match/profile_preview_screen.dart';

/// Alias — delegates entirely to [ProfilePreviewScreen].
class NearbyUserPreviewScreen extends ProfilePreviewScreen {
  const NearbyUserPreviewScreen({
    super.key,
    required super.user,
    super.onProposal,
    super.proposalSent,
  });
}
