// TODO: Specify output path
// TODO: Request desktop permissions upfront
// TODO: Maybe don't even save the JSON
// TODO: Post alert when done

var app = Application.currentApplication()
app.includeStandardAdditions = true

const DESKTOP_PATH = app.pathTo("desktop").toString()

const ENCODED_FILE_PATH = `${DESKTOP_PATH}/temp_watch_later.txt`
const PYTHON_SCRIPT_PATH = `${DESKTOP_PATH}/decode.py`
const DECODED_FILE_PATH = `${DESKTOP_PATH}/watch_later.txt`

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
output_path = sys.argv[2]

data = get_decoded_data(input_path)
write_data(data, output_path)
write_csv(data, output_path + '.csv')

`


const JS_FUNCS = `
window.__YE__COMPLETE = false
function isComplete() {
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
            // If count has not changed for 2 min
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

function openWatchLaterPage(safariApp) {
  safariApp.make({'new': 'document', 'withProperties': {
    'url': "https://www.youtube.com/playlist?app=desktop&list=WL"
  }})
}

function loadJSScripts(safariApp) {
  let window = safariApp.windows[0]
  let currentTab = window.currentTab
  safariApp.doJavaScript(JS_FUNCS, {"in": currentTab})
}

function startFetch(safariApp) {
  let window = safariApp.windows[0]
  let currentTab = window.currentTab
  safariApp.doJavaScript("startFetchingData()", {"in": currentTab})
}

function awaitFetchComplete(safariApp) {
  let window = safariApp.windows[0]
  let currentTab = window.currentTab
  for (var i=0; i<600; i++) {
    delay(1.0)
	let isComplete = safariApp.doJavaScript("isComplete()", {"in": currentTab})
	if (isComplete) {
	  return;
	}
  }
}

function getEncodedOutput(safariApp) {
  let window = safariApp.windows[0]
  let currentTab = window.currentTab
  return safariApp.doJavaScript('encodeURI(getJSONAsString())', {"in": currentTab})
}

function main() {
	SafariApp = Application('Safari')

	openWatchLaterPage(SafariApp)
	delay(2)
	loadJSScripts(SafariApp)
	startFetch(SafariApp)
	awaitFetchComplete(SafariApp)
	let encodedOutput = getEncodedOutput(SafariApp)

	writeTextToFile(encodedOutput, ENCODED_FILE_PATH, true)

	writeTextToFile(PY_SCRIPT, PYTHON_SCRIPT_PATH, true)
    app.doShellScript(`python3 ${PYTHON_SCRIPT_PATH} ${ENCODED_FILE_PATH} ${DECODED_FILE_PATH}`)

	// Clean up
	app.doShellScript(`rm ${PYTHON_SCRIPT_PATH}`)
	app.doShellScript(`rm ${ENCODED_FILE_PATH}`)
	
	app.say("Watch Later Playlist Extracted")
}

main()
