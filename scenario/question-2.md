# 情境實戰測驗 題目二：叢集中單一機器回應逾時

> 試想有一個 API 伺服器叢集，背後由多台機器組成，此時服務監控系統發現其中一台回應時間
> 經常逾時，僅有此機器異常。請簡易描述你將會如何進行問題排查？考量的細節是什麼？

## 那句「僅有此機器異常」

「僅有此機器異常」是這題最強的線索。所有機器共用的東西 —— 程式碼、資料庫、下游 API、
設定範本 —— 壞掉會一起壞。既然其他機器都好好的，嫌疑範圍就只剩下這台機器獨有的東西。

所以排查方向不是「API 為什麼慢」，而是「這台跟其他台有什麼不一樣」。這兩個問題會把人
帶去完全不同的地方。

## 這個叢集是什麼？慢又是誰量的？

**這個「叢集」是什麼？** 題目沒說。傳統 VM／裸機叢集和 Kubernetes 的排查路徑差很多，
而且在 K8s 上「一台機器」還要再分清楚是指某個 node 還是某個 pod。光是這一個答案，
就會讓下面一半的內容換掉，所以它是我進場後問的第一句話。

**「回應時間逾時」是誰量到的？** 這決定問題落在哪一層，而且不需要任何進階工具就能做：

| 量測點看到的 | 指向 |
|---|---|
| LB／ALB 說這台 target 慢，應用自己的 metrics 說正常 | 問題在應用之前：TCP accept queue 積壓、TLS handshake、網路重傳、SYN backlog |
| 兩邊都慢 | 問題在應用內部或它的下游 |
| 只有監控探針說慢，真實使用者流量的指標正常 | 監控自己的問題 —— exporter 卡住回傳 stale metrics、agent 吃光資源、探針走的路徑與真實流量不同 |
| 這台的 metrics 根本沒更新 | 不是慢，是 exporter 掛了，看到的是舊值 |

最後兩列是很容易被跳過的分支。花半天查一台其實沒問題的機器，只因為它的 node_exporter
卡在某個 `/proc` 讀取上，這種事並不罕見。

還有一個細節：題目用的詞是「經常逾時」。間歇性和持續性的嫌疑犯完全不同。
間歇性的話，我會先把延遲畫成時間分布找週期 —— 每小時整點、每天凌晨、每週某天，
這種形狀直接指向排程任務、log rotation、備份視窗，或是虛擬化鄰居的批次工作。

## 先止血，但別把現場一起清掉

確認影響範圍之後，先把這台從 LB 的流量中移除（drain，讓既有連線做完）。
服務先恢復，根因慢慢查。

**這時候不要重啟。** 重啟是最常見的處理，也是最糟的：症狀會消失，證據會一起消失，
然後同樣的問題三天後在同一台或另一台回來，而你手上什麼都沒有。

真要重啟的話 —— 半夜、服務在燒、沒有其他機器可以頂 —— 至少先花兩分鐘留下現場：

```bash
# 進程狀態與資源
top -b -n1 > /tmp/top.txt
ps auxf > /tmp/ps.txt
cat /proc/<pid>/status /proc/<pid>/limits > /tmp/proc.txt
ls /proc/<pid>/fd | wc -l          # 對照 ulimit -n

# 系統層
dmesg -T | tail -100 > /tmp/dmesg.txt
vmstat 1 10 > /tmp/vmstat.txt
iostat -x 1 10 > /tmp/iostat.txt
ss -s ; ss -tan | awk '{print $1}' | sort | uniq -c
```

抓完再重啟，這是可以接受的妥協。什麼都不抓就重啟不是。

## 這台機器獨有的東西

從流量拿掉之後，開始比對這台與正常機器的差異。由下往上：

**虛擬化與硬體層。** `top` 或 `vmstat` 的 steal time 欄位如果明顯高於其他台，就是宿主機
上的鄰居在搶 CPU，這台機器本身沒問題，換一台就好。磁碟看 `iostat -x` 的 `await` 與
`%util`，await 飆高而 IOPS 沒有相對應成長，通常是底層儲存的問題。`dmesg` 裡的 I/O error、
NIC reset、ECC 修正記錄都是硬體在求救。

**作業系統資源。** 磁碟滿或 inode 用盡會讓寫 log 這種小動作變成阻塞；conntrack table 滿了
會讓新連線直接被丟掉（`conntrack -C` 對照 `net.netfilter.nf_conntrack_max`）；file descriptor
逼近上限會讓 accept 失敗；大量 TIME_WAIT 堆積會耗盡本地連接埠。這些的共同特徵是
CPU 和記憶體看起來都很正常，所以只看 CPU／Memory 儀表板的話會完全錯過。

**這台上面跑的其他東西。** 備份代理、防毒掃描、log 收集器、監控 agent 自己 —— 任何一個
失控都會拖累同機的 API process。這也是間歇性延遲最常見的來源。

**應用 process 的狀態。** 連線池耗盡、worker 用完後請求開始排隊。以 PHP-FPM 為例，
`pm.max_children` 用滿時延遲會上升但 CPU 不會，因為請求全卡在 listen queue 裡等；
FPM 的 status page 可以直接看到 queue 長度，slowlog 則能抓到卡住的請求 stack。
Java 服務則要看 GC pause 與 thread dump。

**設定漂移。** 這台是不是漏了某次部署、跑著舊版本、kernel 參數不同、`resolv.conf` 指向
一個已經失聯的 DNS？如果環境是靠 Ansible 或其他工具管理，跑一次 dry-run 比對就知道；
如果是手工維護的機器，這個嫌疑會排得更前面。

**流量本身。** 有沒有可能這台拿到的流量根本比較多或比較重？LB 權重設錯、sticky session
把重量級使用者黏在這台、長連線分佈不均，都會讓單台過載。看這台的 RPS 和請求組成，
不要預設流量是平均的。

## 如果是 Kubernetes

**CPU limit 造成的 cgroup throttling** 是 VM 架構下不存在的陷阱。

Pod 的 CPU limit 設得太低時，容器會被 CFS 週期性節流，表現出來就是延遲飆高、
但 CPU 使用率看起來還很低 —— 因為它根本沒被允許用。只看 CPU 使用率會完全看不出來，
要看的是 throttling 指標：

```bash
# cgroup v2
cat /sys/fs/cgroup/cpu.stat        # nr_throttled、throttled_usec
```

對應的 Prometheus 指標是 `container_cpu_cfs_throttled_seconds_total`。

其他 K8s 特有的方向：這個 pod 所在 node 上有沒有吵鬧的鄰居 pod、node 是否有
memory pressure 或 disk pressure taint、CNI 的網路路徑是否正常、該 node 的
kubelet 與 CRI 是否健康。如果確認是 node 的問題，`kubectl cordon` 加 `drain`
就是這個架構下的止血動作。

## 有可觀測性平台的話

分散式追蹤（OpenTelemetry 打到 Tempo、Jaeger 之類）會讓這題快很多：直接比對這台與
正常機器的 trace，看時間到底花在應用內部運算、等資料庫、還是等下游 API。
單機異常的話，通常會看到某一段特別長，而其他機器的同一段是正常的。

eBPF 工具（bpftrace、Pixie、Parca）可以在不改程式碼、不重啟服務的情況下抓 on-CPU 與
off-CPU 火焰圖。off-CPU 特別有用，因為它顯示的是「時間花在等什麼」—— 延遲問題常常
卡在等 I/O 或等鎖，而這段時間 process 根本沒在 CPU 上，on-CPU 火焰圖完全看不到。

沒有這些工具也查得到，只是慢一點：`perf record -F 99 -p <pid> -g -- sleep 30` 產生的
火焰圖已經能回答大部分問題，`pidstat`、`strace -c`、`ss -ti` 也都夠用。答案不該預設
公司已經有一整套可觀測性平台 —— 而如果真的沒有，這次事件就是推動導入的好理由。

順帶一提，我不會一開始就開 `tcpdump` 或 `perf`。先看現成的 metrics 和 log，多數問題
在那裡就有答案了；抓封包很有成就感，但通常是排查順序裡靠後的動作。

## 收尾

找到可疑點之後，要能回答「為什麼只有這台」。如果解釋不了這件事，那八成還沒找到真正的
根因，只是找到了一個剛好也不太對勁的東西。

修好後放回流量，觀察一段時間再結案。如果查不出根因、機器本身也不貴，直接汰換重建是
合理的選擇（cattle not pets），但要留下記錄 —— 沒查清楚的問題會在別台重演，
而下一個接手的人需要知道這次發生過什麼。

最後是制度上的修復：健康檢查通常只檢查「有沒有回應」，不檢查「回應多快」。這就是為什麼
一台慢機器可以一直留在 LB 裡持續影響使用者。把延遲納入健康檢查、讓叢集能自動把
異常慢的成員摘掉，比修好這一台更有價值。
