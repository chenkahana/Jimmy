# 📝 Google Sheets Feedback Script

This short Apps Script receives JSON feedback from the app and writes it to your Google Sheet.

## Steps

1. Open your Google Sheet and choose **Extensions → Apps Script**.
2. Replace any code with the snippet below.
3. Click **Deploy → New deployment**, select **Web app**, and allow access to Anyone (or choose your preferred restrictions).
4. Copy the deployment URL and set it as `FeedbackService.shared.endpointURL` in the app.

```javascript
function doPost(e) {
  if (!e.postData || !e.postData.contents) {
    return ContentService.createTextOutput('No data received');
  }

  var data = JSON.parse(e.postData.contents);
  var sheet = SpreadsheetApp.getActiveSpreadsheet().getSheets()[0];
  var nextNo = sheet.getLastRow(); // assumes row 1 has headers "no.", "user", "notes"
  sheet.appendRow([nextNo, data.name, data.notes]);

  return ContentService.createTextOutput('OK');
}
```

The script expects a JSON payload with `name` and `notes` fields. Each submission appends a new row with an incrementing number, name, and suggestion/bug note.

