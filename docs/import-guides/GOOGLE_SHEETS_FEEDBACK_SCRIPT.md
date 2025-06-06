# 📝 Google Sheets Feedback Script

This short Apps Script receives JSON feedback from the app and writes it to your Google Sheet.

## Steps

1. Open your Google Sheet and choose **Extensions → Apps Script**.
2. Replace any code with the snippet below, updating the `openById` call if your sheet ID ever changes.
3. Click **Deploy → New deployment**, select **Web app**, and allow access to Anyone (or choose your preferred restrictions).
4. Copy the deployment URL and set it as `FeedbackService.shared.endpointURL` in the app (the app defaults to the script URL provided in the repo).

If requests to your script return **401 Unauthorized**, ensure the web app is deployed with **Who has access** set to **Anyone**.

> **Important**: The demo endpoint included in this repository may be disabled or rate limited. Deploy your own copy of the script and update `FeedbackService.shared.endpointURL` with its URL to ensure submissions succeed.

The script responds with a temporary redirect (HTTP `302`) before returning the
`OK` message. Most HTTP clients, including `URLSession`, follow this redirect
automatically. If you are testing with `curl`, avoid using `-X POST` together
with `-L` or you may receive a `405` error from the redirect URL.

```javascript
function doPost(e) {
  if (!e.postData || !e.postData.contents) {
    return ContentService.createTextOutput('No data received');
  }

  var data = JSON.parse(e.postData.contents);
  var sheet = SpreadsheetApp
      .openById('1eqOJQlUkj5NVMwm7OI26blyru5gsPxZqN9xPEDD8JgI')
      .getSheets()[0];
  var nextNo = sheet.getLastRow(); // assumes row 1 has headers "no.", "user", "notes"
  sheet.appendRow([nextNo, data.name, data.notes]);

  return ContentService.createTextOutput('OK');
}
```

The script expects a JSON payload with `name` and `notes` fields. Each submission appends a new row with an incrementing number, name, and suggestion/bug note.

