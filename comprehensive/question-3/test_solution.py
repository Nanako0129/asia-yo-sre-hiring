from pathlib import Path
import sqlite3

query = Path(__file__).with_name("solution.sql").read_text(encoding="utf-8")

SCHEMA = """
CREATE TABLE score (name TEXT, score INT);
CREATE TABLE class (name TEXT, class TEXT);
INSERT INTO class VALUES ('John', 'A'), ('David', 'C'), ('Sara', 'B'), ('Mary', 'A');
"""


def run(scores):
    db = sqlite3.connect(":memory:")
    db.executescript(SCHEMA)
    db.executemany("INSERT INTO score VALUES (?, ?)", scores)
    # 排序後再比對，查詢本身不保證回傳順序。
    return sorted(db.execute(query).fetchall())


# 題目給的資料：Mary 100 第一，John 97 第二，John 在 A 班。
assert run([("John", 97), ("Mary", 100), ("David", 83), ("Sara", 89)]) == [("A",)]

# 並列第一。排名第二是 89 分的 Sara（B 班），不是同為 100 分的 John。
# LIMIT 1 OFFSET 1 在這組資料上會答 A，這就是不用它的原因。
assert run([("John", 100), ("Mary", 100), ("David", 83), ("Sara", 89)]) == [("B",)]

# 並列第二，兩個班級都算數。
assert run([("John", 89), ("Mary", 100), ("David", 83), ("Sara", 89)]) == [("A",), ("B",)]

print("OK")
