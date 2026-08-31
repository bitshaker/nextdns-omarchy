.pragma library

function profileId(value) {
  var id = String(value === undefined || value === null ? "" : value).trim()
  return /^[A-Za-z0-9]{3,64}$/.test(id) ? id : ""
}

function profileName(value, fallback) {
  var name = String(value === undefined || value === null ? "" : value).trim()
  if (name !== "") return name
  return String(fallback === undefined || fallback === null ? "" : fallback).trim()
}

function normalize(values) {
  // Arrays parsed through shell.json can arrive in QML as array-like
  // QJSValues rather than native JS arrays.
  if (!values || typeof values === "string" || typeof values.length !== "number") return []

  var result = []
  var seen = []
  for (var i = 0; i < values.length; i++) {
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
