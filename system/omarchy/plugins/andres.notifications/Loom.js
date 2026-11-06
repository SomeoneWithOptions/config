.pragma library

function parseLoomRecording(value) {
  if (!value) return null
  var obj = value
  if (typeof value === "string") {
    if (value.length > 16384) return null
    try {
      obj = JSON.parse(value)
    } catch (e) {
      return null
    }
  }
  if (!obj || typeof obj !== "object" || Array.isArray(obj)) return null

  if (obj.version !== 1) return null

  var videoPath = obj.videoPath
  if (typeof videoPath !== "string" || !videoPath || videoPath.length > 4096) return null
  if (videoPath.charAt(0) !== "/") return null
  if (videoPath.indexOf("\0") !== -1) return null

  var accent = obj.accent
  if (typeof accent !== "string" || !accent) return null
  if (!/^#[0-9a-fA-F]{6}$/.test(accent)) return null

  return {
    version: 1,
    videoPath: videoPath,
    accent: accent
  }
}

function normalizeLoomRecording(value) {
  var parsed = parseLoomRecording(value)
  if (!parsed) return ""
  return JSON.stringify(parsed)
}

function loomRecordingFromHints(hints) {
  try {
    if (hints) {
      var raw = hints["x-loom-recording"]
      if (raw !== undefined && raw !== null) {
        return normalizeLoomRecording(raw)
      }
    }
  } catch (e) {}
  return ""
}


// Repeated standard toasts collapse, but recordings and distinct actions do not.
function sameToast(left, right) {
  if (!left || !right || left.key === right.key) return false
  var roles = ["app", "source", "summary", "body", "image", "execArgv", "execActions", "loomRecording"]
  for (var i = 0; i < roles.length; i++)
    if (String(left[roles[i]] || "") !== String(right[roles[i]] || "")) return false
  return true
}
