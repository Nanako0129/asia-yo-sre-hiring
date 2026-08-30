# AsiaYo SRE Hiring Pre-Test

## 解答索引

| 類別 | 題目 | 解答 | 狀態 |
|---|---|---|---|
| 綜合應用測驗 | 題目一：統計出現次數最多的單字 | [solution.py](./comprehensive/question-1/solution.py) | 已驗證 |
| 綜合應用測驗 | 題目二：EKS 架構與 k8s manifest | [question-2/](./comprehensive/question-2/) | 未部署驗證，見該題 README |
| 綜合應用測驗 | 題目三：查出分數第二名的班級 | [solution.sql](./comprehensive/question-3/solution.sql) | 已驗證 |
| 情境實戰測驗 | 題目一：活動網頁的百倍流量 | [question-1.md](./scenario/question-1.md) | — |
| 情境實戰測驗 | 題目二：叢集中單一機器回應逾時 | [question-2.md](./scenario/question-2.md) | — |
| 情境實戰測驗 | 題目三：EC2 服務正常但無法 SSH | [question-3.md](./scenario/question-3.md) | — |

## 執行

```bash
cd comprehensive/question-1
python3 solution.py
python3 test_solution.py

cd ../question-3
python3 test_solution.py
```
