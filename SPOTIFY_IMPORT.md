# 🎵 Spotify Subscriptions Import

This guide explains how to import your followed podcasts from Spotify into Jimmy.

1. **Export Show Links**
   - Open the Spotify web player and navigate to **Your Library → Podcasts**.
   - Run the helper script from the project (`spotify-export.js`) or copy each show link manually.
   - Save the list of show URLs into a text file (one URL per line).

2. **Import in Jimmy**
   - In **Settings → Other Import Options**, choose **Import Spotify File**.
   - Select the text file you created in step 1. Jimmy will resolve each link to an RSS feed and add the podcasts to your library.

3. **Verify**
   - After import, Jimmy will display an alert with the number of podcasts added. You can also open the **Library** tab to confirm all shows appear.

The importer uses the show page metadata to search the Apple Podcasts directory and find the matching RSS feeds. Some Spotify exclusives without public feeds cannot be imported.
