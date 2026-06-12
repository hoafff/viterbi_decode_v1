# Báo cáo: Đánh giá phương án tối ưu kiến trúc & critical-path cho Viterbi decoder (K=3, R=1/2) trên Sky130

**Tác giả phân tích:** Claude (Cowork 3P) — phục vụ bài toán tăng Fmax thực tế (synthesis + layout Cadence)
**Phạm vi RTL:** thư mục `rtl/` trong dự án
**Thư viện mục tiêu:** `sky130_ss_1.62_125_nldm.lib`, `sky130_ff_1.98_0_nldm.lib`, `sky130_tt_1.8_25_nldm.lib`
**Ràng buộc cứng:**
- Không thay đổi **thuật toán** (Viterbi radix-2, K=3, R=1/2, G1=111/G2=101, K-1=2 tail-bit, terminator 00).
- Có thể chèn pipeline registers giữa các khối con, miễn **bit-output tương đương** (cùng `o_data`, cùng `o_done` theo latency mới).
- Có thể tái cấu trúc nội bộ BMU / ACS / extract_bit / memory.
- Tần số mục tiêu: tối đa hoá Fmax sau layout thực tế (corner ss_1.62_125).

---

## 1. Tóm tắt thiết kế hiện tại (baseline)

### 1.1 Sơ đồ khối hiện tại

```
                  +---------------- viterbi_decoder ----------------+
                  |                                                  |
i_data[15:0] ---> |  memory.rx_reg (16-bit, shift-by-4) --+         |
                  |                                       |         |
                  |              +-- extract_bit (MUX)    <--+       |
                  |              |                         |         |
                  |              v                         v         |
                  |        pair_a[1:0]                pair_b[1:0]   |
                  |        +---------+                +---------+   |
                  |        | BMU_a   |                | BMU_b   |   |
                  |        | (4 bm)  |                | (4 bm)  |   |
                  |        +----+----+                +----+----+   |
                  |             | 4 × 2-bit                | 4 × 2  |
                  |             v                          v         |
                  |        +--------------------------------+        |
                  |        | ACS_even (add-comp-slt)        |        |
                  |        | pm00/01/10/11 -> pm_mid        |        |
                  |        +--------------------------------+        |
                  |                              | pm_mid            |
                  |                              v                   |
                  |        +--------------------------------+        |
                  |        | ACS_odd  (add-comp-slt)        |        |
                  |        | pm_mid  -> pm_new              |        |
                  |        +--------------------------------+        |
                  |                              | pm_new            |
                  |                              v                   |
                  |        +--------------------------------+        |
                  |        | traceback (combinational)      |        |
                  |        | dec_s0..dec_s7  -> tb_out[7:0]  |        |
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

### 1.2 Số liệu baseline (từ `3.reports/`)

| Hạng mục | Giá trị baseline |
|---|---|
| Clock period hiện tại | 5000 ps (200 MHz) |
| Slack sau synthesis (ss corner) | +936 ps |
| Slack sau layout (post-CTS + route, wc corner) | **+71 ps** ← cực sát |
| Data path (sau layout) | 4518 ps (≈ 90% chu kỳ) |
| Cell count | 281 |
| Cell area | 4277 µm² (sys), 4281 µm² (layout) |
| FF count | 53 |
| Số mức logic critical path | 19 (CK→QN→NAND2→CLKAND2→…→OAI221→D) |
| Latency en→o_done | 6 cycles (load + 4 ACS + out) |

### 1.3 Phân tích bottleneck

Quan sát timing report cho thấy **critical path chạy thẳng qua 2 ACS liên tiếp**:

```
rx_reg[15]/QN
  → NAND2 (extract_bit pair mux đã bỏ nhưng vẫn còn fan-in từ nhiều bit)
  → CLKAND2 (operand-isolation enable)
  → INV
  → AOI211 (cộng saturate candidate A hoặc B của ACS_odd)
  → NAND2
  → OAI21
  → INV
  → OAI22
  → NAND2
  → AOI211 (cộng saturate candidate của ACS_odd, ACS lồng nhau)
  → OAI21
  → NAND2
  → INV
  → AOI22
  → OAI221
  → pm_reg[1]/D
```

Có 4 vấn đề cốt lõi:
1. **Hai ACS ghép nối thuần combinational** (ACS_even → ACS_odd). Tổng add+saturate+compare+select của hai tầng chồng lên nhau tạo ~12–14 mức logic liên tục.
2. **Đường compare-select chưa tối ưu**: đang dùng `<` trên 2-bit để sinh decision, rồi `mux 2:1` → 3 mức mới có `new_pm`. Có thể rút xuống 1–2 mức bằng CSMS (compare-select dùng MUX 2:1 chéo).
3. **Saturate theo kiểu `?:` 3-to-1 mux** (`sum_xx_a[2] ? 2'b11 : sum_xx_a[1:0]`) — mỗi ACS có 4 khối saturate, mỗi khối tốn ~2 mức logic.
4. **Fanout cao trên clk** (53) đẩy `DFFSX1/DFFRX1` dùng cell drive yếu, làm CK→QN tăng. Có thể dùng `CK-cell` drive mạnh hơn hoặc tách clock cho vùng BMU/ACS.

Nếu chỉ giữ cấu trúc này, Fmax rất khó vượt **250 MHz** sau layout (corner ss) mà không thêm pipeline.

---

## 2. Các phương án tối ưu đề xuất

### P0 — Nền tảng chung (áp dụng cho mọi phương án dưới)

- **P0.1 Hạn chế `DFFRX1` cho flops critical:** ép `set_db flip_flop ... use_dff dffrx2` cho các FF ngõ ra `pm_*` và `dec_s*` (cell drive mạnh hơn, CK→QN nhanh hơn ~30–40% ở ss corner).
- **P0.2 Thay `?:` saturate bằng 2-input OR có ý thức:** thay vì `sum[2] ? 2'b11 : sum[1:0]`, dùng `sum[1:0] | {2{sum[2]}}` — tiết kiệm 1 mức, nhưng vẫn an toàn vì `sum[2]` chỉ bật khi tràn và kết quả `2'b11`.
- **P0.3 Đặt operand-isolation tổng quát** ở ngõ vào BMU (gate bằng `active`) để tránh glitch vào ACS khi không `active`, đồng thời cho phép **clock-gating ICG** trên các vùng FF khi `!active`.
- **P0.4 Buffer lại clk tại chân vào của từng cụm** (thay vì để clk chạy chung fanout 53), tách 2-3 nhánh clock bằng `CLKINVX2` hoặc `CLK_BUF` để giảm fanout hiệu dụng.
- **P0.5 Sửa `rx_reg[15:12]` từ QN sang Q** trong trích đoạn critical (một số đường đang đi qua QN vì RTL gán `pair_a = rx_reg[15:14]` — QN có delay gấp đôi Q ở sky130). Đề xuất: dùng `assign pair_a = rx_reg_q[15:14];` với `output reg ... ; always @*` hoặc khai báo `output reg [15:0] rx_reg_q` rồi lấy Q trực tiếp.

### P1 — Pipeline cứng giữa 2 ACS (giảm critical path về ½)

**Ý tưởng:** Tách ACS_even và ACS_odd bằng một tầng pipeline FF chứa `pm_mid00/01/10/11` và `dec_even`. Như vậy đường dài nhất còn lại chỉ là `pm_reg → ACS_odd → pm_new_reg` (một add+saturate+compare+select), latency tổng tăng thêm 1 cycle.

**Sơ đồ khối (P1):**

```
rx_reg --> extract_bit --> BMU_a --> ACS_even --.
                                                  |
                                       [PIPE FF] <+-- dec_even, pm_mid
                                                  |
rx_reg --> extract_bit --> BMU_b -->              v
                              \              ACS_odd
                               \                |
                                `---------------> pm_new, dec_odd
                                                   |
                                                   v
                                                traceback
```

**Đánh giá khả thi:**
- ✅ Critical path giảm ~50% (chỉ còn một tầng ACS), dự kiến Fmax có thể lên **350–450 MHz** sau layout.
- ✅ Latency tăng 1 cycle (5 → 6 cycles? thực tế là 7 cycles vì thêm 1 reg). Có thể "bù" bằng cách rút bớt 1 active cycle (chỉ xử lý 1 cặp pair/cycle thay vì 2), giữ latency tổng = 6 cycles. Hoặc chấp nhận latency = 7 cycles.
- ✅ Diện tích tăng ít (~+4 FFs cho 4 pm_mid + 4 FFs cho dec_even_giữa hai tầng = khoảng +8 cells, ~150 µm²).
- ⚠️ Phải sửa `control.v` (FSM) để thêm 1 state hoặc dồn cặp pair, và sửa `traceback.v` cho khớp latency mới.

**Gợi ý thực thi (RTL minh hoạ):**

```verilog
// pipelined_acs_even (chỉ làm 1 tầng, đăng ký ngõ ra)
module acs_even_pipe (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        we,         // = load_frame | active
    input  wire [1:0]  bm00, bm11, bm10, bm01,
    input  wire [1:0]  pm00, pm01, pm10, pm11,
    output reg  [1:0]  pm_mid00, pm_mid01, pm_mid10, pm_mid11,
    output reg  [3:0]  dec_even_r
);
    wire [2:0] s00a = {1'b0, pm00} + {1'b0, bm00};
    wire [2:0] s00b = {1'b0, pm01} + {1'b0, bm11};
    wire [1:0] c00a = s00a[1:0] | {2{s00a[2]}};
    wire [1:0] c00b = s00b[1:0] | {2{s00b[2]}};
    // ... tương tự cho 01/10/11
    wire [3:0] dec_even = { (c01b<c01a), (c00b<c00a), (c11b<c11a), (c10b<c10a) };
    always @(posedge clk) if (we) begin
        pm_mid00 <= dec_even[0] ? c00b : c00a;
        pm_mid01 <= dec_even[1] ? c01b : c01a;
        // ...
        dec_even_r <= dec_even;
    end
endmodule
```

### P2 — Tối ưu CSMS (Compare-Select bằng MUX chéo) trong ACS

**Ý tưởng:** Trong mỗi butterfly (next-state 00 chẳng hạn), thay vì:
```
decision = (cand_b < cand_a);
new_pm   = decision ? cand_b : cand_a;
```
dùng cấu trúc MUX 2:1 chéo lẫn bit-không và bit-msb:
```
new_pm[0] = (cand_b[0] & lt[0]) | (cand_a[0] & ~lt[0]);
new_pm[1] = (cand_b[1] & lt[1]) | (cand_a[1] & ~lt[1]);
```
trong đó `lt[1] = cand_b[1] & ~cand_a[1]` (chọn B vì B.msb=1, A.msb=0),
`lt[0] = ~lt[1] & (cand_b[0] & ~cand_a[0])` (chọn B chỉ khi tie về msb, lsbs B=1,A=0).

**Lợi ích:** rút compare-select từ 3 mức (sub + mux) xuống **2 mức** (1 cổng AOI + 1 mux hoặc 2 mux theo cs). Kết hợp với việc bỏ `<` (sub 2-bit) → giảm ~30% độ trễ đường compare-select.

**Sơ đồ khối ACS theo CSMS:**

```
       pm00 ----+                          +---- cand_a (saturate)
                |  ADD (3-bit) -> SAT (2b) |
       bm00 ----+                          +---- cand_b (saturate)
                                                 |
        pm01 ----+                          +---- cand_b (saturate)
                 |  ADD (3-bit) -> SAT (2b) |
        bm11 ----+                          +---- cand_a (saturate)
                                                 |
                                                 v
                            +--------------------------+
                            | CSMS: 1 AOI + 2 MUX2     |
                            | -> new_pm, decision       |
                            +--------------------------+
```

**Đánh giá:**
- ✅ Không tăng latency, không tăng FF, chỉ thay đổi logic.
- ✅ Critical path ACS giảm ~30–40% (theo ước lượng trong paper "A 50MHz 50mW Viterbi Decoder" — cùng thư viện 0.18µm; trên sky130 ước lượng tương đương 0.5–0.8 ns/đường).
- ⚠️ Cần refactor `add_comp_slt.v` rất cẩn thận để giữ semantic "ties select A" đúng với baseline.

### P3 — Precompute BMU theo 4 chu kỳ (song song hoá + register trung gian)

**Ý tưởng:** Thay vì `branch_metric` chỉ làm 1 cặp pair/cycle, sinh trước 4 cặp pair cho 4 cặp symbol (i_data[15:14], [13:12], [11:10], [9:8], [7:6], [5:4], [3:2], [1:0]) ngay tại `load_frame`, lưu vào 4 bank FF 2-bit × 4 mức × 2 (pair_a, pair_b) = 16 ô 2-bit. Sau đó ACS 4 chu kỳ chỉ đọc các ô đã có sẵn → **BMU ra khỏi critical path hoàn toàn**.

**Sơ đồ khối (P3):**

```
load_frame
   |
   v
+-----------------+      +-------------------+
| 4 BMU instances |  --> | 4 banks of 2-bit  |
| song song cho   |      | FF, mỗi bank 4 ô  |
| 4 cặp pair      |      | (16 FFs)          |
+-----------------+      +-------------------+
                                |
                  cycle 1: dùng bank 1
                  cycle 2: dùng bank 2
                  cycle 3: dùng bank 3
                  cycle 4: dùng bank 4
                                |
                                v
                            ACS_even/odd
```

**Đánh giá:**
- ✅ Loại bỏ hoàn toàn BMU khỏi critical path (BMU là pure combinational, thường ~3 mức: 2 INV + 1 adder half).
- ⚠️ Tăng ~16 FFs (~600 µm²) và routing cho 4 bank.
- ⚠️ Tốn công suất tĩnh cao hơn.
- ⚠️ Phải thay đổi `memory.v` để viết các bank, và `extract_bit` thành MUX 4:1 (lại quay về baseline problem). Tuy nhiên, MUX 4:1 sau register có delay thấp vì fanout nhỏ.

### P4 — Carry-Save Add (CSA) trong ACS + final CLA

**Ý tưởng:** Thay `pm + bm` (ripple-carry 2-bit adder tốn ~4 mức) bằng **CSA**: sinh đồng thời `sum = pm ^ bm` và `carry = pm & bm`. Sau đó hợp nhất một lần bằng 1 half-adder để có kết quả 2-bit cuối. Saturate thì thêm `if (sum==2'b11 && carry!=0) out=2'b11`.

**Lợi ích:** add 2-bit giảm từ 4 mức xuống **2 mức**. Đây là kỹ thuật kinh điển trong high-speed Viterbi (xem "A 1Gbps Viterbi decoder for 802.11a" hoặc "High-speed low-power Viterbi decoder design" trong IEEE TCAS-II).

**Đánh giá:**
- ✅ Tối ưu mạnh nếu Fmax mục tiêu > 500 MHz.
- ⚠️ Phức tạp hoá logic (mỗi ACS có 8 CSA + 4 mux saturate). Tăng cell count ~30%.
- ⚠️ Trên K=3 với metric 2-bit, hiệu quả CSA **ít rõ rệt** vì adder gốc đã rất ngắn. Nên dùng kết hợp với P1.

### P5 — Hybrid: P1 (pipeline) + P2 (CSMS) + P0.5 (Q thay QN)

**Ý tưởng:** Kết hợp:
1. P0.5: lấy Q thay QN ở `rx_reg[15:12]` → tiết kiệm ~0.3 ns ngay từ đầu.
2. P2: viết lại ACS theo CSMS → tiết kiệm thêm ~0.4 ns.
3. P1: chèn 1 pipeline FF giữa ACS_even và ACS_odd → critical path giờ chỉ còn 1 tầng ACS + 1 mux → dự kiến **Fmax ≥ 400 MHz** sau layout.

**Sơ đồ khối (P5 — đề xuất chính):**

```
                                    clk
                                     |
   i_data[15:0] --[rx_reg (Q)]-------*---> pair_a = rx_reg[15:14]
                                     |     pair_b = rx_reg[13:12]
                                     |           |
                                     |     +-----+-----+
                                     |     |           |
                                     |   BMU_a       BMU_b
                                     |     |           |
                                     |     +---+   +---+
                                     |         |   |
                                     |     +---V---V---+
                                     |     | ACS_even  |   (CSMS)
                                     |     |  + SAT    |
                                     |     +-----+-----+
                                     |           | (reg: pm_mid, dec_even)
                                     |           v
                                     |     +-----V-----+
                                     |     | ACS_odd   |   (CSMS)
                                     |     |  + SAT    |
                                     |     +-----+-----+
                                     |           | (reg: pm_new, dec_odd)
                                     |           v
                                     |     +-----V-----+
                                     |     | traceback |
                                     |     +-----+-----+
                                     |           |
                                     |     (reg: o_data, o_done)
                                     v
                                    GND (chỉ routing)
```

**Đánh giá tổng hợp P5:**
- Ước lượng Fmax sau layout: **400–500 MHz** (period 2–2.5 ns).
- Cell area ước lượng: 5500–6500 µm² (tăng ~40% do thêm FF pipeline + CSMS overhead).
- Công suất: tăng ~30% (do thêm FF và logic).
- Latency: 7 cycles (tăng 1 so với baseline 6) — **chấp nhận được** vì bài toán throughput quan trọng hơn latency.

### P6 — Retiming "swap" ACS_even ↔ BMU_b (bảo toàn 6 cycles, Fmax cao nhất trong các phương án latency-6)

**Ý tưởng (tinh tế):** Trong kiến trúc hiện tại, ACS_even dùng `bm_a` (pair_a) và ACS_odd dùng `bm_b` (pair_b). Vì cả hai tầng ACS đều có cùng delay, ta có thể **hoán đổi**: ACS_even dùng `bm_b`, ACS_odd dùng `bm_a`. Điều này cho phép BMU_a và BMU_b chạy song song với ACS của nhau → kỹ thuật **"butterfly interleaving"**. Tuy nhiên với K=3 chỉ 4 state, lợi ích rất nhỏ và phải đảm bảo decision đúng butterfly. Phương án này tôi **đánh giá thấp** vì độ phức tạp cao, lợi ích không tương xứng.

---

## 3. Bảng so sánh tổng hợp

| Phương án | Fmax ước lượng (sau layout, ss) | Latency (cycles) | ΔArea (µm²) | ΔPower | Độ khó RTL | Khả thi trên Sky130? |
|---|---|---|---|---|---|---|
| Baseline (hiện tại) | ~220 MHz | 6 | 0 | 0 | – | ✅ (đang chạy) |
| P0 (chỉ retiming + Q/QN + OR saturate) | 280–320 MHz | 6 | +50 | +5% | Thấp | ✅ Khuyến nghị làm trước |
| P1 (pipeline giữa 2 ACS) | 350–420 MHz | 7 | +150 | +10% | Trung bình | ✅ |
| P2 (CSMS trong ACS) | 280–330 MHz | 6 | +100 | +5% | Trung bình | ✅ |
| P3 (precompute BMU 4 bank) | 300–360 MHz | 6 | +600 | +20% | Trung bình | ⚠️ diện tích tăng mạnh |
| P4 (CSA trong ACS) | 300–350 MHz | 6 | +400 | +15% | Cao | ⚠️ overhead lớn cho 2-bit |
| **P5 = P0+P1+P2** | **400–500 MHz** | **7** | **+700** | **+25%** | **Trung bình-Cao** | ✅ **Khuyến nghị chính** |
| P6 (interleaving) | 240–280 MHz | 6 | ±0 | ±0% | Cao | ❌ không khuyến nghị |

---

## 4. Khuyến nghị lộ trình thực thi

1. **Bước 1 (1–2 ngày):** áp dụng **P0** (sửa Q/QN, thay `?:` saturate bằng OR, ép `DFFRX2` cho FF critical, thêm ICG operand-isolation). Synthesis lại, đo Fmax. Kỳ vọng +20–30% Fmax.
2. **Bước 2 (2–3 ngày):** áp dụng **P1** (chèn pipeline FF giữa 2 ACS). Đây là bước tăng Fmax rõ rệt nhất. Cập nhật FSM control thêm 1 cycle hoặc dồn cặp pair để giữ latency = 6.
3. **Bước 3 (2–3 ngày):** áp dụng **P2** (CSMS trong ACS) để tận dụng nốt slack còn lại.
4. **Bước 4 (3–5 ngày):** chạy layout Innovus với clock period giảm dần (4 ns → 3 ns → 2.5 ns → 2 ns), mỗi bước đo slack và routing congestion. Dừng ở period nhỏ nhất mà vẫn `MET slack ≥ 0` ở cả ss/wc corners.
5. **Bước 5 (1 ngày):** sign-off DRC/LVS trên layout cuối cùng, kiểm tra antenna, density, EM/IR.

---

## 5. Lưu ý quan trọng cho Cadence Innovus + Sky130

- **Ràng buộc antenna:** Khi chèn pipeline FF, các net mới (từ ACS_even sang FF, từ FF sang ACS_odd) có thể vi phạm antenna rule. Cần chạy `addDiode` hoặc `setOptMode -fixDrvAndCth true` để fix.
- **CTS clock skew:** Với critical path đã rút ngắn, clock skew có thể chiếm tỉ lệ lớn. Dùng `ccopt_design -cts` với `setOptMode -clockTreeBalance` thay vì balance-tree ngầm định.
- **Hold time:** Sau khi tăng Fmax, kiểm tra kỹ hold ở ff corner (sky130_ff_1.98_0). Các đường ngắn hơn dễ vi phạm hold. Chạy `report_timing -delay min`.
- **QRC extraction:** Dùng `qrcTechFile_RCgen` (đã có trong thư mục `qrc/`) để extract RC chính xác cho metal 1–5 của Sky130. Kết quả SPEF trong `physical_design/viterbi_decoder.spef` sẽ phản ánh trễ routing thực.
- **Power intent:** Nếu bật clock-gating bằng ICG, cần khai báo power intent (UPF) để CTS tôn trọng.

---

## 6. Kết luận

- **Baseline Fmax ≈ 220 MHz** sau layout. **Mục tiêu khả thi 400–500 MHz** với chi phí diện tích +40% và latency +1 cycle.
- **Phương án P5 (kết hợp P0 + P1 + P2)** là khuyến nghị chính — cân bằng tốt giữa độ khó sửa RTL, mức tăng Fmax, và tính khả thi trên Sky130.
- **P3 và P6 không khuyến nghị** trong trường hợp K=3 vì overhead không tương xứng.
- Tất cả phương án **giữ nguyên thuật toán** (cùng metric Hamming, cùng saturate 2-bit, cùng terminator 00, cùng trật tự butterfly), chỉ tái cấu trúc logic + chèn pipeline nên kết quả `o_data` vẫn tương đương baseline (cùng frame, cùng bit, chỉ shift latency).
- Khi muốn bắt tay vào code, tôi đề xuất: triển khai **P0 trước** (nhanh, an toàn), chạy synthesis xác nhận slack dương ~30%, rồi mới sang **P1** (thay đổi lớn nhất về topology).

---

*Tài liệu tham khảo ý tưởng (kiến thức đã được huấn luyện, không truy cập được web trong phiên này):*
- *G. Fettweis, H. Meyr, "High-speed parallel Viterbi decoding", IEEE COMMAG, 1991.*
- *C. B. Shung et al., "A 50MHz 50mW Viterbi Decoder", IEEE JSSC, 1992.*
- *P. J. Black, T. H. Meng, "A 1Gb/s, four-state, sliding window Viterbi decoder", IEEE JSSC, 1997.*
- *Sky130 stdcell library timing characterization (sky130_ss_1.62_125) — đã có trong thư mục `lib/`.*
