.pragma library

var MAX_PROFILES = 32
var MAX_PROFILE_NAME_LENGTH = 80

function profileId(value) {
  var id = String(value === undefined || value === null ? "" : value).trim()
  return /^[0-9a-f]{6}$/.test(id) ? id : ""
}

function profileName(value, fallback) {
  var name = String(value === undefined || value === null ? "" : value).trim()
  if (name !== "" && name.length <= MAX_PROFILE_NAME_LENGTH
      && !/[\u0000-\u001f\u007f-\u009f\u202a-\u202e\u2066-\u2069]/.test(name))
    return name
  return profileId(fallback)
}

function normalize(values) {
  // Arrays parsed through shell.json can arrive in QML as array-like
  // QJSValues rather than native JS arrays.
  if (!values || typeof values === "string" || typeof values.length !== "number") return []

  var result = []
  var seen = []
  var length = Math.min(values.length, MAX_PROFILES)
  for (var i = 0; i < length; i++) {
    var value = values[i]
    if (!value || typeof value !== "object") continue

    var id = profileId(value.id)
    if (id === "" || seen.indexOf(id) !== -1) continue

    seen.push(id)
    result.push({
      name: profileName(value.name, id),
      id: id
    })
  }
  return result
}

function fromSettings(settings) {
  var source = settings || {}
  return normalize(source.profiles)
}

function nameFor(values, id) {
  var target = String(id === undefined || id === null ? "" : id)
  var profiles = normalize(values)
  for (var i = 0; i < profiles.length; i++) {
    if (profiles[i].id === target) return profiles[i].name
  }
  return target
}

function savedNameFor(values, id) {
  var target = String(id === undefined || id === null ? "" : id)
  var profiles = normalize(values)
  for (var i = 0; i < profiles.length; i++) {
    if (profiles[i].id === target) return profiles[i].name
  }
  return ""
}
