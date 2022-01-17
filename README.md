# Read Me

This Mac Automation script extracts your YouTube watch later playlist into a CSV. It includes the following data about each video: 

* videoURL

* videoTitle

* videoDuration

* videoDurationString

* videoThumbnail

* channelURL

* channelTitle

Before running the script, make sure you are signed in to YouTube on safari. Also make sure you have enabled `Safari > Develop > Enable JavaScript from Apple Events`. The script requires this because it injects javascript into YouTube's watch later page to automatically fetch new videos.

To run the script you can either: 

1. Run this command in the Command Line: `$ osascript -l JavaScript ./extract.applescript`

2. Or open the script in "Script Editor", change the language to JavaScript and run it.

Here's how the script works at a high-level:

* The script opens your watch later page in Safari and injects some JavaScript to periodically scroll the page down. This causes YouTube to fetch new videos if possible

* Once the script detects that there are no more videos, it scrapes the DOM for data about each video and saves it as a JSON file

* Using Python the script converts the JSON file into a CSV

The same general approach should work on other platforms too. You will just need to find a way to inject javascript into your browser and export data from it.

