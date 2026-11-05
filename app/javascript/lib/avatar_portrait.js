// One local sprite keeps the same portrait across recents, search, and cards.
export function addPortrait(avatar, index) {
  if (index == null || index === "") return
  const position = Number(index)
  if (!Number.isInteger(position) || position < 0 || position > 7) return
  const photo = document.createElement("span")
  photo.className = "avatar-photo"
  photo.style.backgroundPosition = `${position % 4 * 100 / 3}% ${Math.floor(position / 4) * 100}%`
  avatar.append(photo)
}
