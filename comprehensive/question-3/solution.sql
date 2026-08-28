-- 找出分數排名第二名學生所在的班級。
--
-- 用 DENSE_RANK 而不是 ORDER BY score DESC LIMIT 1 OFFSET 1：後者取的是
-- 「第二列」，不是「第二名」。兩人並列第一時，第二列仍是第一名的另一個人。
-- 見 test_solution.py 的第二組測資。
SELECT c.class
FROM (
    SELECT name, DENSE_RANK() OVER (ORDER BY score DESC) AS rnk
    FROM score
) AS s
JOIN class AS c ON c.name = s.name
WHERE s.rnk = 2;
