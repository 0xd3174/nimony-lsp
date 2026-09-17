# Unicode test sample
let emoji_rocket = "🚀 Blastoff!"
let greeting = "Hello, 🌍 world!"
let accents = "Café au lait & Über"
let cjk = "你好世界"

proc echoEmoji*(x: string): string =
  result = x & " 🌟"

let res = echoEmoji(emoji_rocket)
