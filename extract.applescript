var app = Application.currentApplication()
app.includeStandardAdditions = true

function getTempDir() {
  let path = app.doShellScript("mktemp -d")
  return path
}

// The max time in seconds that the program should attempt to fetch new videos from youtube.
// For me, the program takes ~7 minutes (~420 sec), but your time may vary depending on your network/computer speed.
const MAX_RUNTIME = 900

const YT_WATCH_LATER_URL = "https://www.youtube.com/playlist?app=desktop&list=WL"

const BASE_DIR = getTempDir()
const ENCODED_FILE_PATH = `${BASE_DIR}/__temp_watch_later.txt`
const PYTHON_SCRIPT_PATH = `${BASE_DIR}/__decode.py`
const DECODED_JSON_FILE_PATH = `${BASE_DIR}/watch_later.json`
const DECODED_CSV_FILE_PATH = `${BASE_DIR}/watch_later.csv`

const PY_SCRIPT = `
import sys
import json
import csv
from urllib.parse import unquote

def get_decoded_data(path):
    file = open(path, "r")
    data = file.read()
    file.close()
    return unquote(data)

def write_data(data, path):
    file = open(path, "w")
    file.write(data)
    file.close()

def write_csv(data, path):
    def ordered_values(header, row):
        values = []
        for h in header:
            values.append(row[h])
        return values

    file = open(path, "w")
    csv_writer = csv.writer(file)

    rows = json.loads(data)

    count = 0
    header = None
    for row in rows:
        if count == 0:
            header = list(row.keys())
            header.sort()
            csv_writer.writerow(header)
            count += 1
        values = ordered_values(header, row)
        csv_writer.writerow(values)
    file.close()

input_path = sys.argv[1]
json_output_path = sys.argv[2]
csv_output_path = sys.argv[3]

data = get_decoded_data(input_path)
write_data(data, json_output_path)
write_csv(data, csv_output_path)

`

const JS_SCRIPT = `
window.__YE__COMPLETE = false
function isComplete() {
  // AppleScript has issues dealing with plain boolean values
  // Return a string to get a "truthy" value.
  return window.__YE__COMPLETE ? "complete" : null;
}

function extractData(item) {
    function safeDo(defaultVal, f) {
        try {
            let out = f()
            return out
        } catch (error) {
            console.log(error)
            return defaultVal
        }
    }
	
	function parseDuration(val) {
	  let parts = val.split(':').reverse().map(x => parseInt(x))
	  let time = 0
	  if (parts.length > 0) {
	    time += parts[0]
	  }
	  if (parts.length > 1) {
	    time += parts[1] * 60
	  }
	  if (parts.length > 2) {
	    time += parts[2] * 60 * 60
	  }
	  return time
	}
    
    let videoTitleElem = safeDo(null, () => item.querySelector("a#video-title"))
    let videoTitle = safeDo(null, () => videoTitleElem.textContent.trim())
    let videoURL = safeDo(null, () => videoTitleElem.href)
    let videoDurationString = safeDo(null, () => item.querySelector('.ytd-thumbnail-overlay-time-status-renderer#text').textContent.trim())
    let videoThumbnail = safeDo(null, () => item.querySelector('yt-img-shadow img').src)
    
	let channelURL = safeDo(null, () => item.querySelector('.ytd-channel-name a').href)
    let channelTitle = safeDo(null, () => item.querySelector('.ytd-channel-name a').textContent.trim())
	
	let videoDuration = parseDuration(videoDurationString)
	
    return {
        videoURL,
        videoTitle,
		videoDuration,
        videoDurationString,
        videoThumbnail,
        channelURL,
        channelTitle,
    }
}

function getItems() {
    return document.querySelectorAll('ytd-playlist-video-renderer')
}

function getJSONAsString() {
    let allItems = getItems()
    let allData = [...allItems].map(extractData)
    return JSON.stringify(allData, null, 2)
}

// Periodically scrolls page down to trigger YouTube to fetch new videos
// Once the function detects that no new videos are available, it sets the
// flag __YE__COMPLETE to true.
function startFetchingData() {
    console.log(new Date());
    window.__YE__COMPLETE = false

    let records = []
    function getPrevRecord() {
        if (records.length > 0) {
            return records[records.length - 1]
        } else {
            return null
        }
    }

    let timer = setInterval(function(){
        let count = getItems().length
        let prevRecord = getPrevRecord()
    
        let isFirst = !prevRecord
        let hasNewCount = prevRecord && prevRecord.count != count
    
        let date = new Date()
        if (isFirst || hasNewCount) {
            records.push({
                count, date
            })
        } else if (!isFirst) {
            let delta = date - prevRecord.date
            // If count has not changed for 1 min
            // there is probably no more data to fetch
            console.log(date, delta)
            if (delta > (60 * 1000)) {
                clearInterval(timer)
                window.__YE__COMPLETE = true
            }
        }
    
        window.scrollBy(0, 5000);
    }, 250)
}

`
 
function writeTextToFile(text, file, overwriteExistingContent) {
    try {
        var fileString = file.toString()
        var openedFile = app.openForAccess(Path(fileString), { writePermission: true })
        if (overwriteExistingContent) {
            app.setEof(openedFile, { to: 0 })
        }
        app.write(text, { to: openedFile, startingAt: app.getEof(openedFile) })
        app.closeAccess(openedFile)
        return true
    } catch(error) {
        try {
            app.closeAccess(file)
        } catch(error) {
            console.log(`Couldn't close file: ${error}`)
        }
        return false
    }
}

function getWindowID(safariApp) {
  let window = safariApp.windows[0]
  let windowID = window.id()
  return windowID
}

function getWindowFromID(safariApp, windowID) {
  for (i=0; i<safariApp.windows.length; i++) {
    let window = safariApp.windows[i]
    if (windowID == window.id()) {
	  return window
	}
  }

  return null;
}

function openWatchLaterPage(safariApp) {
  safariApp.make({'new': 'document', 'withProperties': {
    'url': YT_WATCH_LATER_URL
  }})
  delay(2)
  return getWindowID(safariApp)
}

function loadJSScripts(safariApp, windowID) {
  // Wait a few sec to ensure page is loaded
  delay(2)
  let window = getWindowFromID(safariApp, windowID)
  let currentTab = window.currentTab
  safariApp.doJavaScript(JS_SCRIPT, {"in": currentTab})
}

function startFetch(safariApp, windowID) {
  let window = getWindowFromID(safariApp, windowID)
  let currentTab = window.currentTab
  safariApp.doJavaScript("startFetchingData()", {"in": currentTab})
}

function awaitFetchComplete(safariApp, windowID) {
  let window = getWindowFromID(safariApp, windowID)
  let currentTab = window.currentTab
  for (var i=0; i<MAX_RUNTIME; i++) {
    delay(1.0)
	let isComplete = safariApp.doJavaScript("isComplete()", {"in": currentTab})
	if (isComplete) {
	  return;
	}
  }
}

function getEncodedOutput(safariApp, windowID) {
  let window = getWindowFromID(safariApp, windowID)
  let currentTab = window.currentTab
  // use encodeURI to ensure unicode characters are preserved as-is
  // later we use python to decode the string back to unicode characters
  return safariApp.doJavaScript('encodeURI(getJSONAsString())', {"in": currentTab})
}

function finishedAlert() {
  let body = `Extraction complete! Your watch later playlist is available here:\n\n${BASE_DIR}\n\nClick OK to open directory.`
  app.displayDialog(body, {
    'withTitle': "YouTube Watch Later Extractor"
  })
}

function openOutputDirectory() {
  app.doShellScript(`open ${BASE_DIR}`)
}

function main() {
	SafariApp = Application('Safari')

	let windowID = openWatchLaterPage(SafariApp)
	
	loadJSScripts(SafariApp, windowID)
	startFetch(SafariApp, windowID)
	awaitFetchComplete(SafariApp, windowID)
	let encodedOutput = getEncodedOutput(SafariApp, windowID)

	writeTextToFile(encodedOutput, ENCODED_FILE_PATH, true)

	writeTextToFile(PY_SCRIPT, PYTHON_SCRIPT_PATH, true)
    app.doShellScript(`python3 ${PYTHON_SCRIPT_PATH} ${ENCODED_FILE_PATH} ${DECODED_JSON_FILE_PATH} ${DECODED_CSV_FILE_PATH}`)
	
	let window = getWindowFromID(SafariApp, windowID)
    window.close()

	finishedAlert()
    openOutputDirectory()
}

main()
