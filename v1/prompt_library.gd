class_name PromptLibrary
extends RefCounted
## Client requests. Each entry: [tier, archetype, client name, line to say, traits]
## Traits: pitch (high/low), level (loud/soft), pace (fast/slow), expr (dramatic/flat)
## Higher tiers ask for more things at once and unlock as your rank grows.

const PROMPTS := [
	# ---------------- Tier 0: one thing to get right ----------------
	[0, "pirate", "Captain Salty", "Arrr! Hoist the sails, me hearties!", {"level": "loud"}],
	[0, "granny", "Granny Rose", "Come here, dear, I baked some fresh cookies.", {"level": "soft"}],
	[0, "kid", "Little Timmy", "Wow, this is the best day ever!", {"pitch": "high"}],
	[0, "chef", "Chef Marco", "Tonight we are cooking spaghetti with meatballs.", {"pace": "slow"}],
	[0, "cowboy", "Sheriff Jack", "Howdy partner, welcome to our little town.", {"pitch": "low"}],
	[0, "rocker", "DJ Blaze", "Hello Cairo, are you ready to rock tonight?", {"pace": "fast"}],
	[0, "alien", "Zorg", "Take me to your leader, human.", {"expr": "flat"}],
	[0, "knight", "Sir Gallant", "Hear me, good people of the kingdom!", {"expr": "dramatic"}],
	[0, "wizard", "Old Merlock", "The magic potion is almost ready.", {"level": "soft"}],
	[0, "astronaut", "Commander Nova", "Houston, we have a tiny problem.", {"pace": "slow"}],
	[0, "robot", "Beep-9000", "Beep boop. I am your friendly robot.", {"expr": "flat"}],
	[0, "kid", "Little Mia", "Mommy, can I have some ice cream, please?", {"pitch": "high"}],
	[0, "cowboy", "Dusty Pete", "Yee-haw! The sheriff is coming to town!", {"level": "loud"}],
	[0, "granny", "Granny Fatma", "Oh my, what a lovely sunny morning.", {"pace": "slow"}],
	# ---------------- Tier 1: two things ----------------
	[1, "pirate", "Captain Salty", "Shiver me timbers, there be treasure here!", {"level": "loud", "pitch": "low"}],
	[1, "rocker", "DJ Blaze", "Make some noise, everybody, let's go!", {"level": "loud", "pace": "fast"}],
	[1, "wizard", "Old Merlock", "Beware the ancient and spooky forest.", {"pitch": "low", "pace": "slow"}],
	[1, "kid", "Little Timmy", "I found a puppy and he is so cute!", {"pitch": "high", "expr": "dramatic"}],
	[1, "chef", "Chef Marco", "Quick, quick, the soup is burning!", {"pace": "fast", "level": "loud"}],
	[1, "granny", "Granny Rose", "Let me tell you a bedtime story.", {"level": "soft", "pace": "slow"}],
	[1, "astronaut", "Commander Nova", "Ten, nine, eight, we are ready for launch!", {"level": "loud", "pace": "slow"}],
	[1, "businessman", "Mr. Sterling", "Our quarterly profits are doubling this year!", {"expr": "dramatic", "level": "loud"}],
	[1, "alien", "Zorg", "Greetings, we come in peace.", {"expr": "flat", "pitch": "high"}],
	[1, "knight", "Sir Gallant", "Do not fear, I shall protect you.", {"pitch": "low", "expr": "dramatic"}],
	[1, "robot", "Beep-9000", "Warning, battery low, please recharge me.", {"expr": "flat", "pace": "slow"}],
	[1, "cowboy", "Sheriff Jack", "Whoa there, easy now, nice and slow.", {"pace": "slow", "level": "soft"}],
	[1, "kid", "Little Mia", "Tag, you're it, catch me if you can!", {"pace": "fast", "pitch": "high"}],
	[1, "businessman", "Ms. Sharp", "Please hold, your call is very important to us.", {"expr": "flat", "pace": "slow"}],
	# ---------------- Tier 2: three things ----------------
	[2, "pirate", "Captain Salty", "Avast ye! The ship is sinking, abandon ship!", {"level": "loud", "pace": "fast", "expr": "dramatic"}],
	[2, "granny", "Granny Rose", "Oh sweetheart, I missed you so much.", {"level": "soft", "pitch": "high", "expr": "dramatic"}],
	[2, "wizard", "Old Merlock", "By the power of the moon, I command you!", {"pitch": "low", "level": "loud", "expr": "dramatic"}],
	[2, "robot", "Beep-9000", "Initiating self destruct in three seconds.", {"expr": "flat", "pitch": "low", "pace": "slow"}],
	[2, "rocker", "DJ Blaze", "One, two, three, four, let's go!", {"level": "loud", "pace": "fast", "pitch": "high"}],
	[2, "chef", "Chef Marco", "Magnifique! This soup is perfection itself!", {"expr": "dramatic", "pitch": "high", "level": "loud"}],
	[2, "alien", "Zorg", "We are not here to hurt you, earthling.", {"expr": "flat", "level": "soft", "pace": "slow"}],
	[2, "astronaut", "Commander Nova", "Mission control, we found something amazing!", {"expr": "dramatic", "pitch": "high", "pace": "fast"}],
	[2, "knight", "Sir Gallant", "Charge! For the glory of the kingdom!", {"level": "loud", "pitch": "low", "pace": "fast"}],
	[2, "kid", "Little Timmy", "Please, please, please can we stay longer?", {"pitch": "high", "level": "soft", "expr": "dramatic"}],
	[2, "businessman", "Mr. Sterling", "Sign here, and we will both become rich.", {"pitch": "low", "level": "soft", "pace": "slow"}],
	[2, "cowboy", "Dusty Pete", "There's a storm coming, get the horses inside!", {"level": "loud", "pace": "fast", "pitch": "low"}],
	# ---------------- Tier 3: four things (pro level) ----------------
	[3, "businessman", "Big Announcer", "And the winner of the whole championship is...", {"pitch": "low", "level": "loud", "pace": "slow", "expr": "dramatic"}],
	[3, "kid", "Little Timmy", "Surprise! Happy birthday to you!", {"pitch": "high", "level": "loud", "pace": "fast", "expr": "dramatic"}],
	[3, "robot", "Beep-9000", "Error. Error. System failure is imminent.", {"expr": "flat", "pitch": "low", "pace": "slow", "level": "soft"}],
	[3, "wizard", "Old Merlock", "Run! The dragon is breathing fire!", {"pitch": "high", "level": "loud", "pace": "fast", "expr": "dramatic"}],
	[3, "granny", "Granny Fatma", "Shh, the baby is finally sleeping.", {"level": "soft", "pitch": "high", "pace": "slow", "expr": "flat"}],
	[3, "pirate", "Captain Salty", "Yo ho ho, a pirate's life be the life for me!", {"level": "loud", "pitch": "low", "pace": "fast", "expr": "dramatic"}],
	[3, "alien", "Zorg", "Earth will be conquered by tomorrow.", {"expr": "flat", "pitch": "high", "level": "loud", "pace": "slow"}],
	[3, "astronaut", "Commander Nova", "Five, four, three, two, one, liftoff!", {"level": "loud", "pitch": "low", "pace": "fast", "expr": "dramatic"}],
]

const TAGS := {
	"pitch": {"high": "🐭 HIGH VOICE", "low": "🐻 DEEP VOICE"},
	"level": {"loud": "🔊 LOUD", "soft": "🤫 SOFT"},
	"pace": {"fast": "⚡ FAST", "slow": "🐢 SLOW"},
	"expr": {"dramatic": "🎭 DRAMATIC", "flat": "🤖 FLAT / ROBOTIC"},
}


static func tags_for(traits: Dictionary) -> String:
	var parts: Array = []
	for key in ["level", "pitch", "pace", "expr"]:
		if traits.has(key):
			parts.append(TAGS[key][traits[key]])
	return "  •  ".join(parts)


## Rough syllable count so we know how long the line should take to say.
static func syllables(text: String) -> int:
	var total := 0
	for raw in text.to_lower().split(" ", false):
		var w := ""
		for ch in raw:
			if ch >= "a" and ch <= "z":
				w += ch
		if w.is_empty():
			continue
		var count := 0
		var prev_vowel := false
		for ch in w:
			var v: bool = "aeiouy".contains(ch)
			if v and not prev_vowel:
				count += 1
			prev_vowel = v
		if w.length() > 2 and w.ends_with("e") and not w.ends_with("le") and count > 1:
			count -= 1
		total += maxi(1, count)
	return maxi(total, 1)
