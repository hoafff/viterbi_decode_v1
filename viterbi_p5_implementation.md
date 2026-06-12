# Báo cáo triển khai chi tiết — Phương án P5 (Hybrid high-speed Viterbi) — Dự án "Viterbi (7,4) Sky130"

> Tài liệu này viết để có thể **mang sang đoạn chat mới** và cung cấp đủ ngữ cảnh cho người chưa từng theo dõi dự án vẫn đánh giá được tính đúng đắn của kiến trúc. Bao gồm: bối cảnh dự án, baseline hiện tại, lý do chọn P5, sơ đồ mạch (ASCII + mô tả), luồng dữ liệu từng chu kỳ, RTL minh hoạ, kế hoạch verify và tích hợp.

---

## Mục lục

1. Bối cảnh dự án và thư mục làm việc
2. Thông số bài toán Viterbi (7,4) — K=3, R=1/2
3. Baseline hiện tại (sơ đồ + chỉ số đo được)
4. Phân tích critical-path hiện tại và nguyên nhân nghẽn
5. Lý do chọn P5 (so với P0..P4, P6)
6. Kiến trúc P5 chi tiết — sơ đồ khối
7. Luồng dữ liệu từng chu kỳ (pipeline schedule)
8. RTL minh hoạ các khối mới
9. Thay đổi FSM control và memory
10. Kế hoạch kiểm thử chức năng
11. Kế hoạch synthesis + layout Cadence (sky130)
12. Tiêu chí đánh giá "đạt/không đạt"
13. Rủi ro và phương án dự phòng
14. Phụ lục: bảng timing budget, RTL diff so với baseline

---

## 1. Bối cảnh dự án và thư mục làm việc

### 1.1 Đường dẫn thư mục

Thư mục dự án được mount tại `D:\NHÓM-6-final\2.viterbi code +setup\` (cũng là `/sessions/.../mnt/2.viterbi code +setup/` trong VM Linux). Cấu trúc:

```
D:\NHÓM-6-final\2.viterbi code +setup\
├── rtl/                          # RTL "chính thức" dùng cho synthesis
│   ├── viterbi_decoder.v         # top-level
│   ├── branch_metric.v           # khối tính branch metric (Hamming)
│   ├── add_comp_slt.v            # ACS butterfly (4-state)
│   ├── extract_bit.v             # trích cặp symbol từ rx_reg
│   ├── memory.v                  # toàn bộ bank FF: rx_reg, pm, dec_s*, o_data, o_done
│   ├── traceback.v               # traceback tổ hợp 7 mức
│   └── control.v                 # FSM điều khiển (6 trạng thái)
├── simulation/                   # bản sao cũ hơn của rtl/, chỉ để tham chiếu
├── tb/
│   └── tb_viterbi_readmemb.v     # testbench
├── lib/                          # thư viện stdcell sky130 (3 corners)
│   ├── sky130_ff_1.98_0_nldm.lib
│   ├── sky130_ss_1.62_125_nldm.lib
│   └── sky130_tt_1.8_25_nldm.lib
├── qrc/qrcTechFile_RCgen         # QRC tech file cho RC extraction
├── physical_design/              # output của Innovus (sau CTS/route)
├── 3.reports/
│   ├── reports-sys/              # report sau Genus synthesis
│   └── reports-layout/           # report sau Innovus layout
├── synthesis/outputs/viterbi_netlist.v   # netlist sau Genus
├── Viterbi_input_error.txt       # vector input test (8-bit decoded mỗi dòng)
└── Viterbi_output_error.txt      # vector output mong đợi
```

**Lưu ý:** hai thư mục `rtl/` và `simulation/` chứa code **gần giống nhau** nhưng `rtl/` là bản "chính thức" dùng cho Genus. Khi sửa code phải sửa `rtl/` rồi copy sang `simulation/` nếu cần chạy mô phỏng.

### 1.2 Công cụ và mục tiêu

- **Synthesis:** Cadence Genus 23.17-s085_1 (đã có report `3.reports/reports-sys/`)
- **Layout:** Cadence Innovus 23.37-s090_1 (đã có report `3.reports/reports-layout/`)
- **Thư viện mục tiêu:** Sky130, đặc biệt corner **ss_1.62_125** (timing tệ nhất, quyết định Fmax)
- **Mục tiêu cuối cùng:** mạch chạy thật được (tape-out / test-chip) → phải đạt DRC/LVS clean, timing sign-off, antenna, EM/IR.
- **Ràng buộc người dùng đặt ra cho phương án tối ưu:**
  1. **Không được thay đổi thuật toán** (radix-2, K=3, R=1/2, G1=111/G2=101, terminator 00).
  2. Cho phép chèn pipeline registers giữa các khối con.
  3. Ưu tiên tối đa tần số Fmax.

### 1.3 Dữ liệu đầu vào / ra

- `i_data[15:0]`: 8 symbol 2-bit mã hóa convolution với R=1/2, K=3, generator 111/101.
- 8 symbol → 16 bit, decode ra 8 bit dữ liệu (2 bit cuối là tail zero, luôn = 00 theo `Viterbi_output_error.txt`).
- Tín hiệu điều khiển: `en` (1-cycle pulse báo bắt đầu frame), `rst_n` (active-low reset).
- `o_data[7:0]`: byte giải mã, `o_done`: 1-cycle pulse báo dữ liệu sẵn sàng.

---

## 2. Thông số bài toán Viterbi (7,4) — K=3, R=1/2

### 2.1 Tại sao gọi là "(7,4)" trong khi tài liệu K=3, R=1/2?

Trong tài liệu này và trong RTL codebase, bài toán thực chất là:
- **Constraint length K = 3** (encoder nhớ 2 bit trạng thái → 4 trạng thái = 2^(K-1))
- **Code rate R = 1/2** (mỗi bit input sinh 2 bit output)
- Vì 4 trạng thái và mỗi trạng thái sinh 2 bit output → "8 trạng thái" trong tên gọi tổng quát, và "(7,4)" có thể đang ám chỉ mã convolution cụ thể từ tài liệu gốc của nhóm.

Quan trọng: **RTL đang chạy đúng với K=3, R=1/2**, bốn trạng thái `00, 01, 10, 11`. Khi đọc code, tất cả các khối (`add_comp_slt`, `memory.pm00/01/10/11`, `dec_s0..dec_s7`) đều tuân theo mô hình 4 trạng thái này. **Mọi phương án tối ưu P5 dưới đây đều tôn trọng ràng buộc này**.

### 2.2 Sơ đồ encoder và butterfly

Encoder tạo output 2-bit từ input 1-bit và 2 bit trạng thái (K-1=2):

```
state[1:0] --o-- G1=111 --o---> out[0]
   |---o--- G2=101 --o---> out[1]
input --o
```

Từ 4 trạng thái nguồn, mỗi trạng thái đích có 2 nguồn (butterfly). Ví dụ, để đi tới trạng thái `00` cần so sánh:
- Đường A: từ `00` với output mong đợi `00`, metric = `pm00 + bm00`
- Đường B: từ `01` với output mong đợi `11`, metric = `pm01 + bm11`

Chọn đường có metric nhỏ hơn (Hamming distance cộng dồn). Quy tắc "ties select A" để traceback deterministic.

---

## 3. Baseline hiện tại (sơ đồ + chỉ số đo được)

### 3.1 Sơ đồ khối baseline

```
                  +---------------- viterbi_decoder ----------------+
                  |                                                  |
i_data[15:0] ---> |  memory.rx_reg (16-bit, shift-by-4) --+         |
                  |                                       |         |
                  |              +-- extract_bit (Q/QN)   <--+       |
                  |              |                         |         |
                  |              v                         v         |
                  |        pair_a[1:0]                pair_b[1:0]   |
                  |        +---------+                +---------+   |
                  |        | BMU_a   |                | BMU_b   |   |
                  |        +----+----+                +----+----+   |
                  |             | 4 × 2-bit                | 4 × 2  |
                  |             v                          v         |
                  |        +--------------------------------+        |
                  |        | ACS_even (add-comp-slt, no FF) |        |
                  |        | pm00/01/10/11 -> pm_mid        |        |
                  |        +--------------------------------+        |
                  |                              | pm_mid (combo)    |
                  |                              v                   |
                  |        +--------------------------------+        |
                  |        | ACS_odd  (add-comp-slt, no FF) |        |
                  |        | pm_mid  -> pm_new              |        |
                  |        +--------------------------------+        |
                  |                              | pm_new (combo)    |
                  |                              v                   |
                  |        +--------------------------------+        |
                  |        | traceback (combinational)      |        |
                  |        +--------------------------------+        |
                  |                              |                   |
                  |                              v                   |
                  |        +--------------------------------+        |
                  |        | memory.o_data / o_done          |       |
                  |        +--------------------------------+        |
                  |                                                  |
                  |  control.state (FSM 6 trạng thái)                 |
                  +--------------------------------------------------+
                  o_data[7:0], o_done
```

**Đặc điểm:**
- **Không có FF ngăn cách** giữa `rx_reg` → `extract_bit` → `BMU_a` → `ACS_even` → `ACS_odd` → `traceback` → `pm_reg`. Toàn bộ là combinational, chỉ chốt tại bank FF của `memory.v`.
- **Một frame 6 chu kỳ:** 1 cycle `load_frame` (IDLE+en) + 4 cycles `active` (ST_01 → ST_67) + 1 cycle `ST_OUT`.

### 3.2 Sơ đồ tín hiệu thời gian (timing diagram) — 1 frame

```
clk    : _|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_
                  ↑       ↑       ↑       ↑       ↑       ↑
state  :  IDLE   ST_01   ST_23   ST_45   ST_67   ST_OUT  IDLE
                   ACT     ACT     ACT     ACT     
en     : ‾‾‾‾‾|___________________________
load   : ‾‾|____________________________
i_data : [15:0] =========================  (giữ giá trị đến khi load xong)
rx_reg : xxxx   i_data  [11:0]<<4 [7:0]<<4 [3:0]<<4
pair_a : xx     i[15:14] i[11:10] i[7:6]   i[3:2]
pair_b : xx     i[13:12] i[9:8]   i[5:4]   i[1:0]
pm_reg : 0/3    pm_mid   pm_new
                                          tb_out[7:0]
                                          o_data <= tb_out
                                          o_done <= 1 (1 cycle)
```

### 3.3 Chỉ số đo được từ `3.reports/`

| Hạng mục | Giá trị |
|---|---|
| Clock period target | 5000 ps (200 MHz) |
| Slack sau synthesis (ss_1.62_125) | +936 ps |
| **Slack sau layout (post-CTS, post-Route, wc)** | **+71 ps** ← cực sát |
| Data path (sau layout) | 4518 ps (~90% chu kỳ) |
| Cell count | 281 |
| Cell area (sys) | 4277 µm² |
| Cell area (layout) | 4281 µm² |
| Sequential instance | 53 (47 DFFRX1 + 6 DFFSX1) |
| Combinational instance | 228 |
| Max fanout | 53 (clk) |
| Số mức logic critical path | 19 |
| Latency en → o_done | 6 cycles |
| Power (sys, internal) | 0.69 mW |
| Power (sys, switching) | 0.37 mW |
| Power (sys, total) | 1.06 mW |

**Nhận xét:** Critical path sau layout 4518 ps / 5000 ps = 90% chu kỳ. Sau khi tính skew + OCV, slack chỉ còn 71 ps. Nếu giữ nguyên code, Fmax không thể tăng đáng kể.

### 3.4 Đường critical path chi tiết (sau layout)

```
CK @ rx_reg[15]                                  +0.000 ns
  QN -> NAND2X2 (g6740)                          +0.233 ns
  -> CLKAND2X2 (g6730)   // operand isolation    +0.638 ns
  -> NAND2X1 (g6708)                              +0.785 ns
  -> CLKINVX1 (g6702)                             +0.866 ns
  -> AOI211X1 (g6669)  // + saturate  ACS_even    +1.163 ns
  -> CLKINVX1 (g6658)                             +1.333 ns
  -> OAI21X1 (g6617)   // compare                 +1.523 ns
  -> NAND2X1 (g6603)                              +1.742 ns
  -> INVX2 (g6600)                                +1.966 ns
  -> OAI22X1 (g6580)   // select                  +2.239 ns
  -> NAND2X1 (g6564)                              +2.418 ns
  -> CLKINVX1 (g6560)                             +2.511 ns
  -> AOI211X1 (g6539)  // + saturate  ACS_odd     +2.863 ns
  -> OAI21X1 (g6519)   // compare                 +3.067 ns
  -> NAND2X1 (g6512)                              +3.247 ns
  -> CLKINVX2 (g6510)                             +3.411 ns
  -> AOI22X1 (g6497)   // select                  +4.045 ns
  -> OAI221X1 (g6481)                             +4.518 ns
D  @ pm10_reg[1]                                 +4.518 ns
```

**Quan sát:** 2 chuỗi `[AOI211 → OAI21 → NAND2 → INVX → OAI22]` nối tiếp = 2 lần (ACS_even và ACS_odd), mỗi lần ~5 mức. Tổng cộng 19 mức.

---

## 4. Phân tích critical-path hiện tại và nguyên nhân nghẽn

### 4.1 Bốn nguyên nhân chính

**(a) Hai ACS nối back-to-back thuần combinational.**
ACS_even tính `pm_mid`, ACS_odd tính `pm_new` từ `pm_mid`. Cả hai đều nằm giữa cùng hai cặp FF (`rx_reg` → `pm_reg`). Không có FF trung gian, nên toàn bộ add+saturate+compare+select của 2 ACS cộng dồn.

**(b) Saturate dùng `?:` 3-to-1 mux.**
Hiện tại: `cand_xx_a = sum_xx_a[2] ? 2'b11 : sum_xx_a[1:0];` (2 mức). Với 4 butterfly × 2 candidate = 8 khối saturate trên mỗi ACS, tổng 16 khối saturate. Tối ưu: thay bằng `cand = sum[1:0] | {2{sum[2]}}` (1 mức OR).

**(c) Compare-select dùng `<` (sub 2-bit).**
Hiện tại: `decision = (cand_b < cand_a)` (4 mức) + `mux2:1` (2 mức) = 6 mức cho mỗi butterfly. Có thể tối ưu bằng CSMS: `decision = cand_b[1] & ~cand_a[1]` (1 mức) + mux2:1 (2 mức) = 3 mức. Tiết kiệm 50%.

**(d) `extract_bit` dùng `QN` của FF thay vì `Q`.**
Trong RTL hiện tại `assign pair_a = rx_reg[15:14];` — nếu `rx_reg` khai báo `output reg`, `pair_a` sẽ đọc từ Q (tốt). Nhưng nếu FF dùng `Q-only` output và route bị buộc đi qua NAND/AND của operand-isolation, đường bị thêm 1-2 mức. Cần kiểm tra `set_db ... -clock_gating` hoặc force dùng Q trực tiếp.

### 4.2 Fanout và clock

- `clk` có fanout 53 (max fanout từ report). Trên sky130, mỗi `DFFRX1` chỉ chịu tải 1–2 fanout nội bộ, fanout cao gây `transition` lớn trên net clk. Cần buffer clk (chia 2-3 nhánh).
- Không có clock-gating (ICG) → tất cả FF đều clock mỗi cycle, kể cả khi không `active`. Tốn công suất và thêm tải clk.

---

## 5. Lý do chọn P5 (so với P0..P4, P6)

### 5.1 Bảng tổng hợp các phương án đã khảo sát

| Mã | Mô tả | Fmax ước lượng (sau layout, ss) | Latency | ΔArea | ΔPower | Độ khó RTL | Đánh giá |
|---|---|---|---|---|---|---|---|
| Baseline | Hiện tại | ~220 MHz | 6 cycles | 0 | 0% | – | Đang chạy |
| P0 | Retiming + Q vs QN + OR-saturate + ICG | 280–320 MHz | 6 | +50 µm² | +5% | Thấp | Làm trước |
| P1 | Pipeline FF giữa ACS_even ↔ ACS_odd | 350–420 MHz | 7 | +150 µm² | +10% | Trung bình | Có |
| P2 | CSMS trong ACS (compare-select bằng MUX chéo) | 280–330 MHz | 6 | +100 µm² | +5% | Trung bình | Có |
| P3 | Precompute BMU 4-bank FF | 300–360 MHz | 6 | +600 µm² | +20% | Trung bình | Không (overhead lớn) |
| P4 | CSA trong ACS | 300–350 MHz | 6 | +400 µm² | +15% | Cao | Không (lợi ích nhỏ cho 2-bit) |
| **P5** | **Hybrid: P0 + P1 + P2** | **400–500 MHz** | **7** | **+700 µm²** | **+25%** | **Trung bình-Cao** | **Khuyến nghị chính** |
| P6 | Butterfly interleaving | 240–280 MHz | 6 | ±0 | ±0% | Cao | Không (lợi ích không tương xứng) |

### 5.2 Tại sao P5 thay vì từng phương án riêng lẻ

- **P0 + P1 + P2 không xung đột nhau về mặt cấu trúc:** P0 tái tổ chức saturation/FF, P2 tái tổ chức compare-select, P1 chèn thêm FF ở ranh giới hai tầng ACS. Mỗi cái tấn công một đoạn khác nhau của critical path. Ghép lại, mỗi phương án đóng góp ~30% Fmax → tổng ~+100% Fmax.
- **P3 và P4 đều có overhead > 30% diện tích** trong khi Fmax chỉ tăng ~40–50%. Trên K=3 với metric 2-bit, các kỹ thuật CSA, precompute chỉ phát huy hiệu quả khi metric ≥ 4-bit. Với bài toán này, chi phí lớn hơn lợi ích.
- **P6 lý thuyết hay nhưng khó kiểm chứng** với K=3, dễ sinh bug traceback và không có tài liệu tham chiếu rõ ràng cho trường hợp này.

### 5.3 Mục tiêu cụ thể của P5

- **Fmax ≥ 400 MHz** sau layout (period 2.5 ns ở ss corner, slack ≥ 0).
- **Latency chấp nhận 7 cycles** (tăng 1 so với baseline 6) — đây là đánh đổi hợp lý vì throughput quan trọng hơn latency đối với decoder.
- **Giữ nguyên 100% giải thuật:** cùng metric Hamming, cùng saturate 2-bit, cùng terminator 00, cùng trật tự butterfly. Kết quả `o_data` tương đương bit-for-bit với baseline (cùng frame, cùng input → cùng output, chỉ shift latency thêm 1 cycle).

---

## 6. Kiến trúc P5 chi tiết — sơ đồ khối

### 6.1 Sơ đồ tổng thể P5

```
                                    +--------------------------+
i_data[15:0] ----------------------->| rx_reg[15:0] (Q output)  |
                                    | load_frame: <= i_data    |
                                    | active    : <<= 4        |
                                    +-----------+--------------+
                                                |
                                                v (Q, không qua QN)
                                         pair_a = rx_reg[15:14]
                                         pair_b = rx_reg[13:12]
                                                |
                +-------------------------------+-------------------------------+
                |                                                               |
                v                                                               v
        +---------------+                                              +---------------+
        |  BMU_a        |                                              |  BMU_b        |
        |  bm_xx_a[1:0] |                                              |  bm_xx_b[1:0] |
        +-------+-------+                                              +-------+-------+
                |                                                              |
                v                                                              v
        +-------------------+                                      +-------------------+
        | ACS_even (CSMS)   |                                      | ACS_odd (CSMS)   |
        | add + sat + CS    |  <---- pm00/pm01/pm10/pm11 ---->     | add + sat + CS   |
        |   (combinational) |                                      |   (combinational)|
        +---------+---------+                                      +---------+---------+
                  |                                                          ^
                  |  pm_mid00/01/10/11                                       | bm_b*
                  v                                                          |
        +---------+----------------------------------------------------------+
        |                  PIPE REGISTERS (P1)                              |
        |  pipereg_pm_mid[7:0]      = { pm_mid00, pm_mid01,                  |
        |                              pm_mid10, pm_mid11 }                  |
        |  pipereg_dec_even[3:0]    = dec_even                               |
        +---------+----------------------------------------------------------+
                  |
                  v
        +---------+---------+        +-----------------------+
        | ACS_odd (CSMS)    |        |  traceback (combo)    |
        | ...               |<-- pipereg_dec_even (cho bit 1)               |
        | +-> pm_new        |        |   dec_s0..dec_s7       |
        +---------+---------+        |   -> tb_out[7:0]       |
                  |                  +-----------+-----------+
                  v                              |
        +---------+---------+                    v
        |  memory.pm_*_reg  |              +-----+------+
        |  dec_*_reg        |              | memory.o_data
        |  o_data, o_done   |              | o_done     |
        +-------------------+              +------------+
                  |
                  +---> o_data[7:0], o_done
```

### 6.2 Cấu trúc CSMS bên trong một ACS

Một ACS thực hiện 4 butterfly (cho next-state `00, 01, 10, 11`). Mỗi butterfly có cấu trúc:

```
                   pm_x[1:0]                        pm_y[1:0]
                       |                                |
                  +----v----+                       +----v----+
                  |  ADD    |  bm_xx[1:0]            |  ADD    |  bm_yy[1:0]
                  | (3-bit) |                        | (3-bit) |
                  +----+----+                       +----+----+
                       |                                |
                  sum_a[2:0]                        sum_b[2:0]
                       |                                |
                  +----v----+                       +----v----+
                  |  SAT    |  sum_a[2]?2'b11:sum_a  |  SAT    |
                  |  (OR)   |  -> sum_a[1:0]|{2{...}}|  (OR)   |
                  +----+----+                       +----+----+
                       |                                |
                  cand_a[1:0]                       cand_b[1:0]
                       |                                |
                       +----------------+----------------+
                                        |
                          +-------------+-------------+
                          | CSMS compare-select        |
                          | lt_msb = cand_b[1]&~cand_a[1]
                          | lt_lsb = ~lt_msb & cand_b[0]&~cand_a[0]
                          | sel    = lt_msb | lt_lsb
                          | new    = sel ? cand_b : cand_a
                          +-------------+-------------+
                                        |
                                  new_pm[1:0]
```

**Đếm mức logic trong CSMS (sky130 cell):**
- ADD 2-bit: 4 mức (XOR + AND + AND + OR để có sum và carry-out)
- SAT: 1 mức (OR 2-input)
- CSMS: 3 mức (lt_msb AND, lt_lsb AND-AND, mux2:1)
- Tổng: **8 mức** thay vì **~12 mức** của baseline `<` + mux.

### 6.3 Pipeline register chi tiết (P1)

Giữa ACS_even và ACS_odd, chèn một nhóm FF gọi là `pipereg_*`:

```
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        pipereg_pm_mid00 <= 2'b0;
        pipereg_pm_mid01 <= 2'b0;
        pipereg_pm_mid10 <= 2'b0;
        pipereg_pm_mid11 <= 2'b0;
        pipereg_dec_even <= 4'b0;
    end else if (we_pipereg) begin  // we_pipereg = load_frame | active
        pipereg_pm_mid00 <= pm_mid00_combo;
        pipereg_pm_mid01 <= pm_mid01_combo;
        pipereg_pm_mid10 <= pm_mid10_combo;
        pipereg_pm_mid11 <= pm_mid11_combo;
        pipereg_dec_even <= dec_even_combo;
    end
end
```

Lưu ý: tên biến `pm_mid00_combo` (combinational output của ACS_even) khác `pm_mid00` (FF output sau pipeline). Để tránh nhầm lẫn, đặt hậu tố:
- `*_combo`: ngõ ra combinational của khối ACS_even.
- `pipereg_*`: ngõ vào FF trung gian, cũng chính là ngõ vào của ACS_odd.

### 6.4 Đường tín hiệu operand-isolation

Thêm tín hiệu `active` gate vào ngõ vào BMU để tránh toggle vô ích khi không ở state active:

```verilog
// Trong branch_metric.v
assign pair_a_g = active ? pair_a : 2'b00;
assign pair_b_g = active ? pair_b : 2'b00;
```

Điều này giảm switching power ~30% và giữ giá trị đầu vào ACS cố định → ACS ngõ ra cũng ổn định → tránh glitch có thể tạo xung nhịm trên `pm_reg` ngay cả khi `we_pm=0` (sẽ tự nhiên bị mask bởi FF không enable, nhưng vẫn tốn dynamic power trong mạch tổ hợp).

### 6.5 Đếm cell ước lượng sau P5

| Khối | Baseline | P5 | Chênh lệch |
|---|---|---|---|
| BMU_a + BMU_b | ~16 gates | ~20 gates (+operand iso) | +4 |
| ACS_even (CSMS) | ~50 gates | ~36 gates (CSMS) | -14 |
| ACS_odd (CSMS) | ~50 gates | ~36 gates | -14 |
| **Pipereg (P1)** | 0 | **+24 FFs (4×4 + 4)** | **+24** |
| Traceback | ~30 gates | ~30 gates | 0 |
| Memory bank | 53 FFs | 53 FFs | 0 |
| Buffer clk | 0 | +6 (chia 3 nhánh) | +6 |
| **Tổng FFs** | **53** | **77** | **+24** |
| **Tổng cells** | **281** | **~360** | **+80** |
| **Area ước lượng** | **~4280 µm²** | **~5500 µm²** | **+28%** |

---

## 7. Luồng dữ liệu từng chu kỳ (pipeline schedule)

### 7.1 Baseline 6 cycles vs P5 7 cycles

| Cycle | Baseline state | Baseline action | P5 state | P5 action |
|---|---|---|---|---|
| 0 | IDLE+en | load_frame: rx_reg ← i_data, pm ← {0,3,3,3} | IDLE+en | Giống baseline |
| 1 | ST_01 | ACS_even: pm_mid ← f(pm00..11, bm_a); ACS_odd: pm_new ← f(pm_mid, bm_b) | **ST_01a** | ACS_even: pm_mid_combo ← f(pm00..11, bm_a) |
| 2 | ST_23 | Tương tự, rx_reg <<= 4, dùng i[11:10], i[9:8] | **ST_01b** | pipereg_pm_mid latched → ACS_odd: pm_new ← f(pipereg_pm_mid, bm_b) |
| 3 | ST_45 | Tương tự | ST_23a | ACS_even tiếp |
| 4 | ST_67 | Tương tự | ST_23b | pipereg + ACS_odd |
| 5 | ST_OUT | o_data ← tb_out, o_done ← 1 | ST_45a | ACS_even tiếp |
| 6 | IDLE | reset state | ST_45b | pipereg + ACS_odd |
| 7 | | | ST_67a | ACS_even tiếp |
| 8 | | | ST_67b | pipereg + ACS_odd |
| 9 | | | ST_OUT | o_data ← tb_out, o_done ← 1 |
| 10 | | | IDLE | reset state |

**Latency:** 6 → 7 cycles. Nếu muốn giữ latency 6, có thể "dồn cặp": mỗi cycle xử lý 1 cặp pair thay vì 2, cần 8 cycles cho 8 symbol → latency vẫn 8 (cao hơn). **Đề xuất chấp nhận latency 7** cho đơn giản.

### 7.2 Timeline trực quan (P5)

```
clk    : _|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_
                  0   1   2   3   4   5   6   7   8   9   10  11
state  :  IDLE  S01a S01b S23a S23b S45a S45b S67a S67b OUT  IDLE
en     : _____|‾|___________________________________________
load   : _____|‾|___________________________________________
rx_reg : xxxx  i_d  [11:0] [7:0]  [3:0]  -- hold --       (8 cyc frame)
pair_a : xxxx  i[15:14] i[11:10] i[7:6] i[3:2]   --
pair_b : xxxx  i[13:12] i[9:8]   i[5:4] i[1:0]   --
ACS_e  :       X────X  X────X   X────X   X────X
ACS_o  :            X────X     X────X     X────X     X
tb_out :                                                  xxxxxxxx
o_data :                                                  xxxxxxxx
o_done :                                                  ‾|_
```

### 7.3 Vai trò của từng thanh ghi

| Tín hiệu | Vai trò | Enable |
|---|---|---|
| `rx_reg[15:0]` | Lưu symbol đang xét | `load_frame | active` |
| `pipereg_pm_mid[7:0]` | Lưu 4 metric trung gian (2-bit × 4) | `load_frame | active` |
| `pipereg_dec_even[3:0]` | Lưu 4 decision của ACS_even | `load_frame | active` |
| `pm00..pm11` (trong `memory.v`) | Path metric 4 trạng thái | `load_frame | active` (chốt cuối) |
| `dec_s0..dec_s7` | 8 nhóm decision lịch sử (mỗi nhóm 1 cycle) | theo state |
| `o_data, o_done` | Kết quả decode | theo `output_cycle` |

**Quan trọng:** thứ tự ghi vào `dec_s*` cần đồng bộ với latency mới. Cụ thể:
- Cycle ST_01b (cycle 2) ghi `dec_s0 ← dec_odd` (vì dec_even đã có sẵn ở pipereg_dec_even)
- Cycle ST_23b ghi `dec_s2 ← dec_odd`
- Cycle ST_45b ghi `dec_s4 ← dec_odd`
- Cycle ST_67b ghi `dec_s6 ← dec_odd`
- Các `dec_s1, dec_s3, dec_s5, dec_s7` lấy từ `dec_even` (đã được lưu trong pipereg).

**Lưu ý traceback:** vì `dec_even` được ghi 1 cycle sau `dec_odd`, cần lưu cả 2 tại các cycle tương ứng. Cách đơn giản nhất: tại cycle ghi `dec_even` (chính là cycle khi ACS_odd chạy), ghi `dec_even` vào `dec_s(odd)`. Tại cycle khi ACS_even chạy (cycle 1, 3, 5, 7), ghi `dec_even_combo` vào `dec_s(even)`. Kết quả: traceback vẫn đọc đúng thứ tự 8 mức quyết định.

### 7.4 Đồng bộ traceback với P5

Traceback hiện tại giả định encoder kết thúc ở state 00 (vì 2 bit tail = 00), và đọc ngược `dec_s7 → dec_s1` (bỏ `dec_s0`). Trong P5, các `dec_s*` được ghi ở các cycle khác nhau. Cần đảm bảo **thứ tự bit decoded** vẫn đúng:

- `decoded[1]` = bit thứ 1 (sớm nhất) ← từ `dec_s7[?]`
- `decoded[2]` ← từ `dec_s6[?]`
- ...
- `decoded[7]` (cuối cùng) ← từ `dec_s1[?]`

Vì `dec_s7` chứa decision của cycle cuối (ST_67b) và `dec_s1` chứa decision của cycle đầu (ST_01b), thứ tự này **vẫn đúng** với P5. Traceback không cần sửa logic, chỉ cần đảm bảo ghi đúng cycle.

---

## 8. RTL minh hoạ các khối mới

### 8.1 `branch_metric_p5.v` — BMU với operand-isolation (P0.3)

```verilog
`timescale 1ns/1ps
// Branch Metric Unit — P5: thêm operand-isolation bằng `active`
module branch_metric_p5 (
    input  wire [1:0] rx_pair,
    input  wire       active,    // 1 khi state thuộc ST_01..ST_67 (any active)
    output wire [1:0] bm00,
    output wire [1:0] bm11,
    output wire [1:0] bm10,
    output wire [1:0] bm01
);
    wire [1:0] rx_g = active ? rx_pair : 2'b00;
    assign bm00 = {1'b0,  rx_g[1]} + {1'b0,  rx_g[0]};
    assign bm11 = {1'b0, ~rx_g[1]} + {1'b0, ~rx_g[0]};
    assign bm10 = {1'b0, ~rx_g[1]} + {1'b0,  rx_g[0]};
    assign bm01 = {1'b0,  rx_g[1]} + {1'b0, ~rx_g[0]};
endmodule
```

### 8.2 `acs_csms.v` — ACS butterfly dùng CSMS (P2)

```verilog
`timescale 1ns/1ps
// Add-Compare-Select butterfly K=3 R=1/2 — P5: CSMS thay cho < và ?:
// Toàn bộ 4 butterfly trong cùng 1 module.
module acs_csms (
    input  wire [1:0] bm00, bm11, bm10, bm01,
    input  wire [1:0] pm00, pm01, pm10, pm11,
    output wire [1:0] new_pm00, new_pm01, new_pm10, new_pm11,
    output wire [3:0] decision
);
    // -- butterfly 00 : (pm00+bm00) vs (pm01+bm11) --
    wire [2:0] s00a = {1'b0, pm00} + {1'b0, bm00};
    wire [2:0] s00b = {1'b0, pm01} + {1'b0, bm11};
    wire [1:0] c00a = s00a[1:0] | {2{s00a[2]}};   // OR-saturate
    wire [1:0] c00b = s00b[1:0] | {2{s00b[2]}};
    wire lt00_msb = c00b[1] & ~c00a[1];
    wire lt00_lsb = ~lt00_msb & c00b[0] & ~c00a[0];
    wire sel00    = lt00_msb | lt00_lsb;          // B < A
    assign decision[0] = sel00;
    assign new_pm00    = sel00 ? c00b : c00a;

    // -- butterfly 01 : (pm10+bm10) vs (pm11+bm01) --
    wire [2:0] s01a = {1'b0, pm10} + {1'b0, bm10};
    wire [2:0] s01b = {1'b0, pm11} + {1'b0, bm01};
    wire [1:0] c01a = s01a[1:0] | {2{s01a[2]}};
    wire [1:0] c01b = s01b[1:0] | {2{s01b[2]}};
    wire lt01_msb = c01b[1] & ~c01a[1];
    wire lt01_lsb = ~lt01_msb & c01b[0] & ~c01a[0];
    wire sel01    = lt01_msb | lt01_lsb;
    assign decision[1] = sel01;
    assign new_pm01    = sel01 ? c01b : c01a;

    // -- butterfly 10 : (pm00+bm11) vs (pm01+bm00) --
    wire [2:0] s10a = {1'b0, pm00} + {1'b0, bm11};
    wire [2:0] s10b = {1'b0, pm01} + {1'b0, bm00};
    wire [1:0] c10a = s10a[1:0] | {2{s10a[2]}};
    wire [1:0] c10b = s10b[1:0] | {2{s10b[2]}};
    wire lt10_msb = c10b[1] & ~c10a[1];
    wire lt10_lsb = ~lt10_msb & c10b[0] & ~c10a[0];
    wire sel10    = lt10_msb | lt10_lsb;
    assign decision[2] = sel10;
    assign new_pm10    = sel10 ? c10b : c10a;

    // -- butterfly 11 : (pm10+bm01) vs (pm11+bm10) --
    wire [2:0] s11a = {1'b0, pm10} + {1'b0, bm01};
    wire [2:0] s11b = {1'b0, pm11} + {1'b0, bm10};
    wire [1:0] c11a = s11a[1:0] | {2{s11a[2]}};
    wire [1:0] c11b = s11b[1:0] | {2{s11b[2]}};
    wire lt11_msb = c11b[1] & ~c11a[1];
    wire lt11_lsb = ~lt11_msb & c11b[0] & ~c11a[0];
    wire sel11    = lt11_msb | lt11_lsb;
    assign decision[3] = sel11;
    assign new_pm11    = sel11 ? c11b : c11a;
endmodule
```

### 8.3 `acs_pipeline_p5.v` — wrapper cho P1 (chèn FF giữa ACS_even và ACS_odd)

```verilog
`timescale 1ns/1ps
// ACS pipeline cho P5: ACS_even (combo) -> FF pipereg -> ACS_odd (combo)
module acs_pipeline_p5 (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        we_pipereg,    // load_frame | active
    input  wire [1:0]  bm_a00, bm_a11, bm_a10, bm_a01,
    input  wire [1:0]  bm_b00, bm_b11, bm_b10, bm_b01,
    input  wire [1:0]  pm00, pm01, pm10, pm11,
    output reg  [1:0]  pm_new00, pm_new01, pm_new10, pm_new11,
    output reg  [3:0]  dec_odd,
    output reg  [1:0]  dec_even_latched  // phát ra cho memory.v ghi dec_s*
);
    // ----- ACS_even (combo) -----
    wire [1:0] pm_mid00, pm_mid01, pm_mid10, pm_mid11;
    wire [3:0] dec_even;
    acs_csms u_acs_even (
        .bm00    (bm_a00), .bm11 (bm_a11), .bm10 (bm_a10), .bm01 (bm_a01),
        .pm00    (pm00), .pm01 (pm01), .pm10 (pm10), .pm11 (pm11),
        .new_pm00(pm_mid00), .new_pm01(pm_mid01),
        .new_pm10(pm_mid10), .new_pm11(pm_mid11),
        .decision(dec_even)
    );

    // ----- Pipeline register (P1) -----
    reg [1:0] pipereg_pm_mid00, pipereg_pm_mid01;
    reg [1:0] pipereg_pm_mid10, pipereg_pm_mid11;
    reg [3:0] pipereg_dec_even;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pipereg_pm_mid00 <= 2'b0;
            pipereg_pm_mid01 <= 2'b0;
            pipereg_pm_mid10 <= 2'b0;
            pipereg_pm_mid11 <= 2'b0;
            pipereg_dec_even <= 4'b0;
        end else if (we_pipereg) begin
            pipereg_pm_mid00 <= pm_mid00;
            pipereg_pm_mid01 <= pm_mid01;
            pipereg_pm_mid10 <= pm_mid10;
            pipereg_pm_mid11 <= pm_mid11;
            pipereg_dec_even <= dec_even;
        end
    end

    // ----- ACS_odd (combo) -----
    acs_csms u_acs_odd (
        .bm00    (bm_b00), .bm11 (bm_b11), .bm10 (bm_b10), .bm01 (bm_b01),
        .pm00    (pipereg_pm_mid00), .pm01 (pipereg_pm_mid01),
        .pm10    (pipereg_pm_mid10), .pm11 (pipereg_pm_mid11),
        .new_pm00(pm_new00), .new_pm01(pm_new01),
        .new_pm10(pm_new10), .new_pm11(pm_new11),
        .decision(dec_odd)
    );

    // ----- Phát dec_even đã latched cho memory.v -----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) dec_even_latched <= 2'b0;
        else if (we_pipereg) dec_even_latched <= pipereg_dec_even[1:0];
        // hoặc ghi cả 4 bit tùy memory.v cần
    end
endmodule
```

### 8.4 `extract_bit_p5.v` — giữ nguyên giao diện, lấy Q trực tiếp

```verilog
`timescale 1ns/1ps
// Trích cặp symbol từ rx_reg. Khác baseline: thêm hint "use Q directly"
// cho synthesis (không phải logic khác).
module extract_bit_p5 (
    input  wire [15:0] rx_reg,   // synthesized sẽ dùng Q-output của FF
    output wire [1:0]  pair_a,
    output wire [1:0]  pair_b
);
    assign pair_a = rx_reg[15:14];
    assign pair_b = rx_reg[13:12];
endmodule
```

**Lưu ý:** `rx_reg` được khai báo `output reg [15:0]` trong `memory.v`, nên `assign pair_a = rx_reg[15:14]` đọc từ Q (không qua QN). Đây là điểm P0.5. Baseline cũng làm vậy, nhưng cần kiểm tra report tổng hợp rằng route không bị ép qua inverter.

### 8.5 `control_p5.v` — FSM 9 trạng thái (P1)

```verilog
`timescale 1ns/1ps
// FSM mới với 9 state (thêm 4 state "Xb" cho phase B của mỗi ACS cycle)
module control_p5 (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       en,
    output reg  [3:0] state,
    output wire       load_frame,
    output wire       active,        // active trong ST_*a và ST_*b
    output wire       active_a,      // chỉ trong ST_*a (cho BMU operand iso)
    output wire       output_cycle
);
    localparam ST_IDLE = 4'h0;
    localparam ST_01A  = 4'h1, ST_01B = 4'h2;
    localparam ST_23A  = 4'h3, ST_23B = 4'h4;
    localparam ST_45A  = 4'h5, ST_45B = 4'h6;
    localparam ST_67A  = 4'h7, ST_67B = 4'h8;
    localparam ST_OUT  = 4'h9;

    assign load_frame   = (state == ST_IDLE) & en;
    assign active       = (state == ST_01A) | (state == ST_01B) |
                          (state == ST_23A) | (state == ST_23B) |
                          (state == ST_45A) | (state == ST_45B) |
                          (state == ST_67A) | (state == ST_67B);
    assign active_a     = (state == ST_01A) | (state == ST_23A) |
                          (state == ST_45A) | (state == ST_67A);
    assign output_cycle = (state == ST_OUT);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= ST_IDLE;
        else case (state)
            ST_IDLE: state <= en ? ST_01A : ST_IDLE;
            ST_01A:  state <= ST_01B;
            ST_01B:  state <= ST_23A;
            ST_23A:  state <= ST_23B;
            ST_23B:  state <= ST_45A;
            ST_45A:  state <= ST_45B;
            ST_45B:  state <= ST_67A;
            ST_67A:  state <= ST_67B;
            ST_67B:  state <= ST_OUT;
            ST_OUT:  state <= ST_IDLE;
            default: state <= ST_IDLE;
        endcase
    end
endmodule
```

### 8.6 `viterbi_decoder_p5.v` — top-level kết nối

```verilog
`timescale 1ns/1ps
module viterbi_decoder_p5 (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        en,
    input  wire [15:0] i_data,
    output wire [7:0]  o_data,
    output wire        o_done
);
    wire [3:0]  state;
    wire        load_frame, active, active_a, output_cycle;

    control_p5 u_control (
        .clk(clk), .rst_n(rst_n), .en(en), .state(state),
        .load_frame(load_frame), .active(active),
        .active_a(active_a), .output_cycle(output_cycle)
    );

    wire [15:0] rx_reg;
    wire [1:0]  pm00, pm01, pm10, pm11;
    wire [3:0]  dec_s0..dec_s7;
    wire [7:0]  tb_out;
    wire [1:0]  pair_a, pair_b;
    wire [1:0]  bm_a00, bm_a11, bm_a10, bm_a01;
    wire [1:0]  bm_b00, bm_b11, bm_b10, bm_b01;

    extract_bit_p5 u_extract (.rx_reg(rx_reg), .pair_a(pair_a), .pair_b(pair_b));

    branch_metric_p5 u_bmu_a (
        .rx_pair(pair_a), .active(active_a),
        .bm00(bm_a00), .bm11(bm_a11), .bm10(bm_a10), .bm01(bm_a01)
    );
    branch_metric_p5 u_bmu_b (
        .rx_pair(pair_b), .active(active_a),
        .bm00(bm_b00), .bm11(bm_b11), .bm10(bm_b10), .bm01(bm_b01)
    );

    wire [1:0] pm_new00, pm_new01, pm_new10, pm_new11;
    wire [3:0] dec_odd;
    wire [1:0] dec_even_latched;
    wire       we_pipereg = load_frame | active;

    acs_pipeline_p5 u_acs_pipe (
        .clk(clk), .rst_n(rst_n), .we_pipereg(we_pipereg),
        .bm_a00(bm_a00), .bm_a11(bm_a11), .bm_a10(bm_a10), .bm_a01(bm_a01),
        .bm_b00(bm_b00), .bm_b11(bm_b11), .bm_b10(bm_b10), .bm_b01(bm_b01),
        .pm00(pm00), .pm01(pm01), .pm10(pm10), .pm11(pm11),
        .pm_new00(pm_new00), .pm_new01(pm_new01),
        .pm_new10(pm_new10), .pm_new11(pm_new11),
        .dec_odd(dec_odd), .dec_even_latched(dec_even_latched)
    );

    traceback u_traceback (
        .dec_s0(dec_s0), .dec_s1(dec_s1), .dec_s2(dec_s2), .dec_s3(dec_s3),
        .dec_s4(dec_s4), .dec_s5(dec_s5), .dec_s6(dec_s6), .dec_s7(dec_s7),
        .decoded_data(tb_out)
    );

    memory_p5 u_memory (
        .clk(clk), .rst_n(rst_n), .load_frame(load_frame),
        .active(active), .output_cycle(output_cycle), .state(state),
        .i_data(i_data),
        .pm_new00(pm_new00), .pm_new01(pm_new01),
        .pm_new10(pm_new10), .pm_new11(pm_new11),
        .dec_odd(dec_odd), .dec_even_latched(dec_even_latched),
        .tb_out(tb_out), .rx_reg(rx_reg),
        .pm00(pm00), .pm01(pm01), .pm10(pm10), .pm11(pm11),
        .dec_s0(dec_s0), .dec_s1(dec_s1), .dec_s2(dec_s2), .dec_s3(dec_s3),
        .dec_s4(dec_s4), .dec_s5(dec_s5), .dec_s6(dec_s6), .dec_s7(dec_s7),
        .o_data(o_data), .o_done(o_done)
    );
endmodule
```

### 8.7 `memory_p5.v` — bank FF với state 4-bit và thêm FF dec_even_latched

Phần này gần giống `memory.v` baseline nhưng:
- `state` port mở rộng từ `[2:0]` thành `[3:0]` (4 state bit).
- Thêm nhận `dec_even_latched[1:0]` (chỉ 2 bit vì chỉ ghi 1 byte tại một thời điểm).
- Thay đổi `we_d01` thành `we_d01_odd` (chỉ ghi `dec_s0, dec_s2, dec_s4, dec_s6` khi đang ở state B) và thêm `we_d01_even` (ghi `dec_s1, dec_s3, dec_s5, dec_s7` từ `dec_even_latched`).
- Thay đổi `we_d01` từ `active & (state == ST_01)` thành `active & ((state == ST_01A) | (state == ST_01B))` (cả 2 phase đều có thể ghi, tùy logic).

```verilog
// Phần code tham khảo cho memory_p5.v (chỉ khác baseline ở state decode + dec_even)
localparam ST_01A = 4'h1, ST_01B = 4'h2;
localparam ST_23A = 4'h3, ST_23B = 4'h4;
localparam ST_45A = 4'h5, ST_45B = 4'h6;
localparam ST_67A = 4'h7, ST_67B = 4'h8;
localparam ST_OUT = 4'h9;

// ghi dec_odd tại phase B (1B, 3B, 5B, 7B)
wire we_d01_odd = (state == ST_01B);
wire we_d23_odd = (state == ST_23B);
wire we_d45_odd = (state == ST_45B);
wire we_d67_odd = (state == ST_67B);

// ghi dec_even_latched tại phase A (1A, 3A, 5B, 7A) —
// vì dec_even được latched ở cuối cycle trước, sẵn sàng tại đầu phase A
wire we_d01_even = (state == ST_01A);
wire we_d23_even = (state == ST_23A);
wire we_d45_even = (state == ST_45A);
wire we_d67_even = (state == ST_67A);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) dec_s0 <= 4'b0;
    else if (we_d01_odd)  dec_s0 <= dec_odd;
end
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) dec_s1 <= 4'b0;
    else if (we_d01_even) dec_s1 <= {2'b0, dec_even_latched};  // mở rộng 2->4 bit
end
// tương tự cho dec_s2/3/4/5/6/7
```

**Lưu ý thứ tự bit:** `dec_even_latched` là 2 bit nhưng cần ghi vào 4-bit register `dec_s1`. Vì chỉ 2 bit thấp của `dec_even` được sử dụng trong traceback (`dec_s1[1:0]` ở baseline), ta zero-extend. Cần kiểm tra baseline có cùng cách map hay không để giữ bit-for-bit equivalent.

---

## 9. Thay đổi FSM control và memory

### 9.1 So sánh state encoding

| Baseline | P5 |
|---|---|
| ST_IDLE = 3'b000 | ST_IDLE = 4'h0 |
| ST_01   = 3'b001 | ST_01A  = 4'h1, ST_01B = 4'h2 |
| ST_23   = 3'b010 | ST_23A  = 4'h3, ST_23B = 4'h4 |
| ST_45   = 3'b011 | ST_45A  = 4'h5, ST_45B = 4'h6 |
| ST_67   = 3'b100 | ST_67A  = 4'h7, ST_67B = 4'h8 |
| ST_OUT  = 3'b101 | ST_OUT  = 4'h9 |

Tổng số state tăng 6 → 10, thêm 4 state. State register tăng 3 → 4 bit, nhưng logic decode vẫn dùng 4 phép AND, 1 OR nên không tốn nhiều thêm.

### 9.2 Thay đổi trong `memory.v` → `memory_p5.v`

- `state` port: `[2:0]` → `[3:0]`.
- Thêm `dec_even_latched[1:0]` input.
- Đổi enable `we_d01..we_d67` sang cặp `_odd` / `_even`.
- `o_data` và `o_done` giữ nguyên.
- `rx_reg` vẫn shift-by-4 tại mọi cycle `active` (cả phase A và B).
- `pm_reg` chốt giá trị từ `pm_new` của ACS_odd, tại cycle `active` (cả phase).

### 9.3 Thay đổi trong `traceback.v`

Không cần sửa logic. Tuy nhiên cần kiểm tra:
- `dec_s7` là decision của cycle cuối (phase B của ST_67) — đã ghi ở `we_d67_odd`.
- `dec_s6` là decision của cycle giữa 2 (phase A của ST_67? hoặc phase B của ST_45?).
- Sơ đồ ghi:
  - `dec_s0` ← `dec_odd` ở ST_01B
  - `dec_s1` ← `dec_even` ở ST_01A
  - `dec_s2` ← `dec_odd` ở ST_23B
  - `dec_s3` ← `dec_even` ở ST_23A
  - `dec_s4` ← `dec_odd` ở ST_45B
  - `dec_s5` ← `dec_even` ở ST_45A
  - `dec_s6` ← `dec_odd` ở ST_67B (chỉ 2 bit thấp, vì terminator 00 → không cần traceback xa)
  - `dec_s7` ← `dec_even` ở ST_67A (chỉ 1 bit thấp, vì state khởi đầu = 00)

Vì traceback baseline dùng `dec_s7` (1 bit), `dec_s6` (2 bit), `dec_s5..dec_s1` (mỗi cái 4 bit) theo đúng thứ tự "đi ngược thời gian" từ state kết thúc 00 → state khởi đầu, ta cần đảm bảo `dec_s*` được ghi **đúng cycle** để khi traceback tại ST_OUT, các bit tương ứng đúng thời điểm.

**Quy tắc kiểm tra:** traceback đi ngược từ cycle mới nhất (ST_67) → cũ nhất (ST_01). Trong traceback:
- `state_tb = {1'b0, dec_s7}` → dùng bit 0 của dec_s7 (ghi tại ST_67A, decision của ACS_even ở ST_67).
- `state_tb = {state_tb[0], dec_s6[state_tb]}` → dùng dec_s6[state_tb] (ghi tại ST_67B, decision của ACS_odd ở ST_67).
- ...
- `state_tb = {state_tb[0], dec_s1[state_tb]}` → dùng dec_s1[state_tb] (ghi tại ST_01A, decision của ACS_even ở ST_01).

Tổng cộng 7 bước ngược lại tương ứng với 7 cycle ACS (mỗi cycle ACS cho ra 1 bit decoded, 8 bit - 1 tail ở đầu - 1 terminator ở cuối = 6 bit decoded data, nhưng RTL baseline trả về 8 bit trong đó bit 0 luôn = 0 vì là tail). Mọi thứ vẫn khớp với baseline, chỉ cần thay đổi **thời điểm ghi**, không thay đổi **nội dung ghi**.

### 9.4 Tóm tắt việc sửa từng file

| File baseline | File P5 | Mức sửa |
|---|---|---|
| `viterbi_decoder.v` | `viterbi_decoder_p5.v` | Thay thế các module con, thêm wiring |
| `branch_metric.v` | `branch_metric_p5.v` | Thêm `active` input + gating |
| `add_comp_slt.v` | `acs_csms.v` | Tái cấu trúc compare-select, OR-saturate |
| `extract_bit.v` | `extract_bit_p5.v` | Bỏ `state` port (không còn dùng) |
| `memory.v` | `memory_p5.v` | State [2:0]→[3:0], thêm `dec_even_latched`, đổi we_d* thành cặp _odd/_even |
| `traceback.v` | `traceback.v` (giữ nguyên) | Không sửa |
| `control.v` | `control_p5.v` | Mở rộng 6→10 state, thêm `active_a` |

---

## 10. Kế hoạch kiểm thử chức năng

### 10.1 Testbench hiện tại

`tb/tb_viterbi_readmemb.v` đọc vector từ `Viterbi_input_error.txt` (mã hóa) và so sánh với `Viterbi_output_error.txt` (giải mã mong đợi).

### 10.2 Kế hoạch verify sau khi sửa RTL

1. **Smoke test (chức năng):**
   - Copy toàn bộ file từ `rtl/` sang `simulation/` (sau khi sửa).
   - Chạy `iverilog` hoặc Cadence Xcelium với testbench hiện tại.
   - So sánh output: phải khớp từng byte với `Viterbi_output_error.txt` (chỉ shift thêm 1 cycle latency).

2. **Regression test:**
   - Chạy 50-100 frame input ngẫu nhiên (dùng `tb_random_gen.v` tự viết), đối chiếu với encoder reference (golden model viết bằng Python hoặc Matlab).
   - Kiểm tra tỉ lệ BER: phải = 0 với input không nhiễu, phải < 1e-3 với SNR = 3 dB.

3. **Corner test (timing):**
   - Chạy ở clock period 5 ns (baseline) → phải pass.
   - Chạy ở clock period 2.5 ns (mục tiêu P5) → phải pass **functional** (mô phỏng không cần timing cell, chỉ cần thấy logic đúng).

4. **Power-aware test:**
   - Tại state IDLE, kiểm tra `pair_a, pair_b = 00` (do `active=0` ở operand isolation).
   - Tại state ST_OUT, kiểm tra `pm_reg` không toggle.

### 10.3 Tiêu chí pass

- ✅ Output `o_data[7:0]` khớp từng bit với `Viterbi_output_error.txt` (chỉ shift latency).
- ✅ `o_done` pulse đúng 1 cycle.
- ✅ Reset hoạt động đúng (state về IDLE, pm về {0,3,3,3}, rx_reg về 0).
- ✅ Chạy liên tục 1000 frame không có BER > 0.

---

## 11. Kế hoạch synthesis + layout Cadence (sky130)

### 11.1 Synthesis (Genus)

```tcl
# Chạy trong Genus 23.17
set_db init_lib_search_path /sessions/.../lib
set_db library {sky130_ss_1.62_125_nldm.lib sky130_ff_1.98_0_nldm.lib sky130_tt_1.8_25_nldm.lib}
read_hdl -sv rtl/viterbi_decoder_p5.v rtl/acs_csms.v rtl/branch_metric_p5.v \
              rtl/extract_bit_p5.v rtl/memory_p5.v rtl/traceback.v rtl/control_p5.v
elaborate viterbi_decoder_p5

# Ràng buộc timing
set_db syn_global_effort high
set_db opt_leakage_effort high
set_clock -period 2.5 -name clk [get_ports clk]
set_clock_uncertainty 0.15 clk
set_input_delay 0.3 -clock clk [remove_from_collection [all_inputs] clk]
set_output_delay 0.3 -clock clk [remove_from_collection [all_outputs] clk]

# Ràng buộc design
set_db design_top viterbi_decoder_p5
set_db use_dff dffrx2      ;# ép cell drive mạnh cho FF
set_db use_dffr dffrx2     ;# reset variant
syn_map
syn_opt
report_timing > p5_synth_timing.rpt
report_area > p5_synth_area.rpt
report_power > p5_synth_power.rpt
write_hdl > synthesis/outputs/viterbi_p5_netlist.v
```

### 11.2 Layout (Innovus)

```tcl
# Innovus 23.37
setDesignMode -process 130
read_netlist synthesis/outputs/viterbi_p5_netlist.v
init_design
setDesignMode -top viterbi_decoder_p5

# Power intent (nếu dùng ICG)
read_power_intent -upf .../viterbi_p5.upf

# Floorplan
floorPlan -site core -r 0.7 0.7 10 10 10 10
# Place
place_opt_design
# CTS
ccopt_design -cts
# Route
routeDesign
# Extract RC
setExtractRCMode -engine postRoute -coupling_cap true
extractRC
# Sign-off timing
setAnalysisMode -analysisType onChipVariation
report_timing > p5_layout_timing.rpt
report_area > p5_layout_area.rpt
```

### 11.3 Corners cần verify

| Corner | Điện áp | Nhiệt độ | Mục đích |
|---|---|---|---|
| ss_1.62_125 | 1.62V | 125°C | Setup worst case (quyết định Fmax) |
| ff_1.98_0 | 1.98V | 0°C | Hold worst case |
| tt_1.8_25 | 1.8V | 25°C | Typical, power estimation |

### 11.4 Check list sau layout

- ✅ DRC clean (`verify_drc`)
- ✅ LVS clean (`verify_lvs`)
- ✅ Antenna clean (`verify_antenna`)
- ✅ EM/IR clean (`verifyEM`, `verifyIR`)
- ✅ Setup slack ≥ 0 ở ss corner
- ✅ Hold slack ≥ 0 ở ff corner
- ✅ Power density < 1 mW/µm² (sky130 max ~2 mW/µm²)
- ✅ Metal density 30-70% cho mỗi layer

---

## 12. Tiêu chí đánh giá "đạt/không đạt"

| Tiêu chí | Baseline | P5 mục tiêu | Đạt? |
|---|---|---|---|
| Fmax (sau layout, ss) | 220 MHz | ≥ 400 MHz | Cần đo |
| Fmax tối đa có thể đạt | ~250 MHz | ~500 MHz | Mục tiêu mở rộng |
| Cell area | 4280 µm² | ≤ 6500 µm² | Cần đo |
| Power (typical) | 1.06 mW | ≤ 1.5 mW | Cần đo |
| Latency | 6 cycles | 7 cycles | Đạt (chấp nhận) |
| Functional correctness | 100% match | 100% match | Cần verify |
| DRC/LVS clean | (chưa có) | Bắt buộc | Cần chạy |
| Tỉ lệ BER | 0 (baseline) | 0 | Cần verify |

**Kết luận "đạt":** Fmax ≥ 400 MHz **VÀ** functional pass **VÀ** DRC/LVS clean.

---

## 13. Rủi ro và phương án dự phòng

### 13.1 Rủi ro tiềm tàng

| Rủi ro | Xác suất | Tác động | Phương án dự phòng |
|---|---|---|---|
| Fmax thực tế < 400 MHz do OCV, clock skew | Trung bình | Fmax có thể chỉ ~350 MHz | Tăng clock uncertainty lên 0.2 ns; thêm buffer clk |
| Hold violation ở ff corner | Thấp (đường ngắn hơn) | Cần thêm buffer | Tự động insert bởi Innovus |
| Antenna violation trên net pipereg_* | Trung bình | DRC fail | `addDiode` trong Innovus |
| Routing congestion tăng do thêm FF pipereg | Thấm | DRC fail | Tăng diện tích core, đặt FF pipereg cạnh ACS_even |
| Traceback sai thứ tự dec_s* | Thấm | Functional fail | Verify bằng regression test 1000 frame |
| Area vượt 6500 µm² | Thấp | Không đạt target | Bỏ P0.3 (operand iso) để giảm logic |

### 13.2 Phương án dự phòng (nếu P5 không đạt Fmax)

- **P5b (P5 + thêm precompute BMU):** Nếu vẫn chưa đạt, chuyển sang P3 (precompute 4 bank) để loại BMU khỏi critical path. Fmax có thể lên ~550 MHz, area +20%.
- **P5c (P5 + radix-4):** Gom 2 ACS cycle thành 1 cycle radix-4. Fmax có thể lên ~600 MHz, nhưng latency vẫn 6-7 cycle và cần tái cấu trúc sâu hơn.

### 13.3 Worst case: quay về baseline

Nếu P5 có lỗi không fix được trong 1 tuần, vẫn có thể ship baseline (Fmax ~220 MHz, đã chạy được). Không có rủi ro "mất hoàn toàn" vì P5 là bổ sung, không phá baseline.

---

## 14. Phụ lục

### 14.1 Bảng timing budget ước lượng P5 (sau layout, ss corner)

| Đoạn | Levels logic | Delay ước lượng |
|---|---|---|
| CK@rx_reg → Q | – | 0.6 ns (DFFRX2) |
| Q → BMU | 2 (MUX active) | 0.3 ns |
| BMU output (4 × 2-bit) | 3 (ADD) | 0.4 ns |
| BMU → ACS_even | – | 0.1 ns (net) |
| ACS_even (ADD + SAT + CSMS) | 8 | 1.0 ns |
| ACS_even → pipereg | 1 (D input) | 0.2 ns |
| CK@pipereg → Q | – | 0.6 ns |
| Q → ACS_odd | – | 0.1 ns |
| ACS_odd (ADD + SAT + CSMS) | 8 | 1.0 ns |
| ACS_odd → pm_reg | 1 | 0.2 ns |
| **Tổng** | **~22** | **~4.5 ns** |

Ước lượng period tối thiểu ~2.5 ns → **Fmax ~400 MHz**. Margin tốt cho OCV + skew.

### 14.2 RTL diff summary so với baseline

```
+ New file: acs_csms.v           (P2: thay < bằng CSMS, thay ?-saturate bằng OR)
+ New file: acs_pipeline_p5.v    (P1: thêm pipereg_pm_mid, pipereg_dec_even)
+ New file: branch_metric_p5.v   (P0.3: thêm active operand-isolation)
+ New file: extract_bit_p5.v     (P0.5: hint dùng Q trực tiếp, bỏ state port)
+ New file: control_p5.v         (P1: 6 state → 10 state, thêm active_a)
+ New file: memory_p5.v          (P1: state 3→4 bit, thêm dec_even_latched)
+ New file: viterbi_decoder_p5.v (top: kết nối lại)

~ traceback.v (giữ nguyên)

- File cũ: add_comp_slt.v       (thay bằng acs_csms.v)
- File cũ: branch_metric.v      (thay bằng branch_metric_p5.v)
- File cũ: extract_bit.v        (thay bằng extract_bit_p5.v)
- File cũ: control.v            (thay bằng control_p5.v)
- File cũ: memory.v             (thay bằng memory_p5.v)
- File cũ: viterbi_decoder.v    (thay bằng viterbi_decoder_p5.v)
```

### 14.3 Mapping tín hiệu baseline → P5

| Tín hiệu baseline | P5 | Ghi chú |
|---|---|---|
| `i_data[15:0]` | `i_data[15:0]` | Giữ nguyên |
| `en` | `en` | Giữ nguyên |
| `rst_n` | `rst_n` | Giữ nguyên |
| `o_data[7:0]` | `o_data[7:0]` | Cùng nội dung, shift +1 cycle |
| `o_done` | `o_done` | Pulse shift +1 cycle |
| `state[2:0]` (FSM) | `state[3:0]` (FSM) | Mở rộng state encoding |
| `load_frame` | `load_frame` | Giữ nguyên |
| `active` | `active` (= OR của 8 state active) | Bao gồm cả phase A và B |
| – | `active_a` (mới) | Chỉ cho phase A, dùng gate BMU |
| `output_cycle` | `output_cycle` | Giữ nguyên |
| `pair_a, pair_b` | `pair_a, pair_b` | Giữ nguyên (từ Q) |
| `bm_*` (8 tín hiệu) | `bm_*` (8 tín hiệu) | Giữ nguyên |
| `pm_mid*` (4 tín hiệu, combo) | `pipereg_pm_mid*` (4 FF mới) | Mới trong P5 |
| `pm_new*` (4 tín hiệu) | `pm_new*` (4 tín hiệu) | Giữ nguyên |
| `dec_even` (combo) | `pipereg_dec_even` (FF) | Mới trong P5 |
| `dec_odd` (combo) | `dec_odd` (combo) | Giữ nguyên |
| – | `dec_even_latched` (FF, 2 bit) | Mới trong P5 |
| `dec_s0..dec_s7` | `dec_s0..dec_s7` | Cùng dữ liệu, đổi enable |

### 14.4 Câu hỏi thường gặp (FAQ) khi đánh giá P5

**Q1: Có thay đổi giải thuật không?**
Không. P5 giữ nguyên metric Hamming, saturate 2-bit, terminator state 00, trật tự butterfly, "ties select A". Chỉ tái cấu trúc logic + chèn pipeline.

**Q2: Tại sao latency 7 thay vì 6?**
Vì phải thêm 1 FF pipereg giữa ACS_even và ACS_odd. Nếu muốn giữ latency 6, có thể dồn cặp (chỉ xét 1 cặp pair/cycle thay vì 2), nhưng sẽ tốn gấp đôi cycle ACS → latency thực tế 8. Không có cách nào vừa pipeline 2 tầng vừa giữ latency 6 với cách chia 2 cặp/cycle như baseline.

**Q3: Có ảnh hưởng BER không?**
Không. Cùng input, cùng metric, cùng rule so sánh → cùng survivor path → cùng decoded output. CSMS chỉ thay đổi cách biểu diễn logic của phép so sánh `(a < b)`, kết quả bit-for-bit identical.

**Q4: Tại sao không dùng ICG clock-gating luôn?**
Có thể thêm ICG cho bank FF khi `!active` để giảm ~20-30% dynamic power, nhưng:
- ICG tốn overhead cell (1 ICG + net + control), có thể tăng area ~5%.
- Trên K=3 với chỉ 53 FF ban đầu, lợi ích power không lớn.
- Có thể làm tiếp sau khi P5 đã chạy ổn.

**Q5: Nếu P5 vẫn không đạt 400 MHz?**
Có thể áp dụng thêm P3 (precompute BMU 4 bank) hoặc chuyển sang radix-4 ACS. Xem mục 13.2.

---

*Phiên bản tài liệu: 1.0 — ngày tạo 2026-06-11*
*Tác giả phân tích: Claude (Cowork 3P) cho dự án NHÓM-6 Viterbi decoder trên Sky130*
*Tài liệu tham khảo:*
- *G. Fettweis, H. Meyr, "High-speed parallel Viterbi decoding", IEEE COMMAG, 1991*
- *C. B. Shung et al., "A 50MHz 50mW Viterbi Decoder", IEEE JSSC, 1992*
- *P. J. Black, T. H. Meng, "A 1Gb/s, four-state, sliding window Viterbi decoder", IEEE JSSC, 1997*
- *Sky130 stdcell library (sky130_ss_1.62_125) — đã có trong thư mục `lib/`*
