// One small file per portrait; the CSS class picks it, so the same face shows in
// recents, search, and cards, and the browser caches each file once.
export function addPortrait(avatar, index) {
  if (index == null || index === "") return
  const position = Number(index)
  if (!Number.isInteger(position) || position < 0 || position > 7) return
  const photo = document.createElement("span")
  photo.className = `avatar-photo avatar-photo--${position}`
  avatar.append(photo)
}
