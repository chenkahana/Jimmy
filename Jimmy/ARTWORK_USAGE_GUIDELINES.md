# Artwork Usage Guidelines

## Core Rule: Shows get show artwork, episodes get episode artwork

This document outlines the strict guidelines for artwork usage throughout the Jimmy podcast app to ensure consistency and proper visual hierarchy.

## Primary Rule

**Episodes should ALWAYS use episode artwork first, with podcast artwork as fallback.**
**Shows/Podcasts should ALWAYS use podcast artwork.**

## Implementation Pattern

For any view displaying an episode, use this pattern:
```swift
AsyncImage(url: episode.artworkURL ?? podcast.artworkURL)
```

For any view displaying a podcast/show, use this pattern:
```swift
AsyncImage(url: podcast.artworkURL)
```

## File-by-File Guidelines

### Episode Views
- `EpisodeRowView.swift` ✅ - Uses `episode.artworkURL ?? podcast.artworkURL`
- `EpisodeDetailView.swift` ✅ - Uses `episode.artworkURL ?? podcast.artworkURL`
- `CurrentPlayView.swift` ✅ - Uses `episode.artworkURL ?? podcast?.artworkURL`
- `EpisodePlayerView.swift` ✅ - Uses `episode.artworkURL ?? podcast?.artworkURL`
- `QueueEpisodeCardView.swift` ✅ - Uses `episode.artworkURL ?? podcast?.artworkURL`
- `MiniPlayerView.swift` ✅ - Uses `episode.artworkURL ?? podcast?.artworkURL`
- `LibraryView.swift` (EpisodeLibraryRowView) ✅ - Uses `episode.artworkURL ?? podcast.artworkURL`

### Podcast/Show Views
- `LibraryView.swift` (PodcastGridItemView) ✅ - Uses `podcast.artworkURL`
- `PodcastDetailView.swift` (PodcastDetailHeaderView) ✅ - Uses `podcast.artworkURL`
- `SearchResultDetailView.swift` ✅ - Uses `result.artworkURL` (podcast artwork)

### Widget
- `JimmyWidgetExtension.swift` ✅ - Uses episode artwork (no podcast context available)

## RSS Parsing Improvements

The RSS parser has been enhanced to better extract podcast artwork:

### Enhanced Artwork Detection
- `itunes:image` elements (primary)
- `image` elements with `href` or `url` attributes
- `media:thumbnail` elements
- `<image><url>artwork_url</url></image>` patterns
- Text content within `url` elements

### Automatic Artwork Updates
- Podcast artwork is now automatically updated when episodes are fetched
- No longer requires podcasts to have `nil` artwork to be updated
- The `PodcastService.refreshPodcastMetadata()` method can force-update all metadata

## Fixing Existing Artwork Issues

If podcasts are displaying episode artwork instead of show artwork:

### Option 1: Use Settings (Recommended)
1. Go to Settings → Debug/Developer Mode
2. Tap "Fix Podcast Artwork"
3. This will refresh metadata for all podcasts and update their artwork

### Option 2: Manual Refresh
Each time you visit a podcast page, the artwork will be automatically updated if available from the RSS feed.

## Common Issues & Solutions

### Issue: Show displays first episode's artwork
**Cause**: RSS feed was parsed before artwork enhancement, or feed has complex artwork structure
**Solution**: Use "Fix Podcast Artwork" button in Settings

### Issue: Episode shows podcast artwork instead of episode-specific artwork
**Cause**: Episode doesn't have its own artwork in the RSS feed
**Solution**: This is correct behavior - use podcast artwork as fallback

### Issue: Widget shows wrong artwork
**Cause**: Widget has limited context and uses episode artwork when available
**Solution**: This is expected behavior due to widget limitations

## Testing Checklist

When implementing new views that display artwork:

- [ ] Episodes use `episode.artworkURL ?? podcast.artworkURL`
- [ ] Podcasts use `podcast.artworkURL`
- [ ] Fallback behavior is properly implemented
- [ ] No hardcoded artwork URLs
- [ ] AsyncImage is used for all network images
- [ ] Placeholder images are provided

## Never Break This Rule

❌ **NEVER** use episode artwork for podcast/show displays
❌ **NEVER** use podcast artwork when episode-specific artwork is available
❌ **NEVER** skip the fallback mechanism

✅ **ALWAYS** implement the fallback pattern: `episode.artworkURL ?? podcast.artworkURL`
✅ **ALWAYS** use podcast artwork for show/podcast displays
✅ **ALWAYS** test both scenarios (with and without episode artwork)

## RSS Feed Artwork Hierarchy

When parsing RSS feeds, artwork is extracted in this priority order:

1. **Episode artwork**: `item > itunes:image`, `item > image`, `item > media:thumbnail`
2. **Podcast artwork**: `channel > itunes:image`, `channel > image`, `channel > media:thumbnail`, `channel > image > url`

This ensures that episodes get their specific artwork when available, while maintaining podcast artwork as the universal fallback.

## Breaking This Rule

**Never break this rule.** If you need to modify artwork display:

1. Update this document first
2. Ensure all affected views follow the new pattern
3. Test thoroughly across all views
4. Update the testing checklist above

## Common Mistakes to Avoid

❌ Using only podcast artwork for episodes
❌ Using only episode artwork without fallback
❌ Inconsistent patterns across different views
❌ Not updating this document when making changes

## Future Enhancements

- Widget could be enhanced to include podcast data for proper fallback
- Consider caching artwork for better performance
- Add artwork validation and error handling 