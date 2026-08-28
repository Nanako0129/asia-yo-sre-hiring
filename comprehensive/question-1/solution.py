from collections import Counter
from pathlib import Path
import re

text = Path(__file__).with_name("words.txt").read_text(encoding="utf-8")

# \w' keeps "don't" whole and drops every surrounding punctuation mark.
counts = Counter(re.findall(r"[\w']+", text.lower()))

for word, n in counts.most_common(1):
    print(n, word)
